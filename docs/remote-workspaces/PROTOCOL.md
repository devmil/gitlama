# Remote workspace protocol, version 1.0

Status: implemented contract for the R1 read surface and the R2 write families. The Rust
helper (`rust-core/remote-helper`) and the Dart client (`lib/repositories/impl/remote/`) both
follow this document. Capabilities, write families and their capabilities, outcomes, error
codes, bulk methods and limits come from one source, `tooling/remote_wire/contract.json`, which
`tooling/remote_wire/generate.py` turns into `rust-core/application/src/wire/contract.rs` and
`lib/models/remote_contract.g.dart`. Both test suites read the accept/reject vectors in
`rust-core/remote-helper/fixtures/contract_vectors.json` (`remote-helper/tests/contract.rs`,
`test/remote/contract_vectors_test.dart`), and the helper test checks that the error codes below
match the contract. Change the contract, this document and the vectors together.

The helper runs as `gitlama-remote-helper --stdio`, started by the client through a fixed SSH
command (see [launch](#launch)). Stdout carries only protocol frames. Stdin carries only
client frames. Stderr is diagnostic noise; the client drains and discards it.

## Framing

A frame is a 4-byte unsigned big-endian payload length followed by that many bytes of UTF-8
JSON. The payload is one JSON object.

| Bound | Value |
| --- | --- |
| Frame payload | 1 byte to 4 MiB (4 194 304). Zero is invalid. The reader checks the length before allocating. |
| Hello frame | At most 64 KiB |
| Incomplete frame | 15 seconds from the frame's first byte, regardless of later partial bytes |
| Nesting | 16 levels |
| Array/object items | 4096 per collection in one frame; 262 144 inside a reassembled transaction |

JSON parsing is strict: duplicate object keys, numbers with a fraction or exponent, numbers
beyond ±2^53, invalid UTF-8, lone surrogates and trailing bytes are rejected. Any framing or
parsing failure is a protocol violation and closes the connection.

### Value encodings

- 64-bit integers, identifiers, revisions and offsets are canonical decimal strings: digits
  only, no leading zeros except `"0"`, optional leading `-` for signed values, never `"-0"`.
- Small integers (`u32`, `i32`, `u16`) are JSON numbers.
- Byte strings (native paths, ref names, content) are canonical padded base64. A decoder
  re-encodes and rejects any other spelling.
- UTF-16 or Unix path unit arrays are base64 of little-endian 16-bit units.
- Random identifiers (incarnation, nonce, store, operation) are 32 lowercase hex characters.
- Build IDs are 40 lowercase hex characters. Since helper compatibility version 1 they are the
  helper's compatibility version from `rust-core/remote-helper/COMPATIBILITY` as 40 decimal
  digits (version 3 is `0000000000000000000000000000000000000003`), not the source commit; the
  helper's `--version` also reports its `sourceCommit`.
- Objects carry exactly their declared keys. Absent optional values are `null`, never missing.
  Unknown keys are rejected: a helper is bound to clients of its own compatibility version, and
  any change to what it accepts or returns raises that version.

The repository value types (`NativeHistoryResult`, `NativeDiffResult` and so on) are encoded by
generated codecs (`tooling/remote_wire/generate.py`). Field names are the Dart (camelCase)
names; enum values are the Dart value names.

## Launch

The client runs the installed OpenSSH client with an argument array (never a local shell):

```
ssh -T -o RequestTTY=no -o StdinNull=no -o BatchMode=yes -o StrictHostKeyChecking=yes
    -o ForwardAgent=no -o ForwardX11=no -o ClearAllForwardings=yes
    -o GSSAPIDelegateCredentials=no -o ControlMaster=no -o ControlPath=none
    -o ForkAfterAuthentication=no -o RemoteCommand=none -o SessionType=default
    -o PermitLocalCommand=no -o ConnectTimeout=10 -o ConnectionAttempts=1
    -o ServerAliveInterval=15 -o ServerAliveCountMax=3 -- <alias> <launch>
```

`<launch>` is one fixed POSIX shell string. Its only variable part is the validated build ID:

```
h="$HOME/.local/lib/gitlama/remote/<build-id>/gitlama-remote-helper"; p="$(uname -s)/$(uname -m)"; case "$p" in Linux/x86_64|Linux/aarch64|Darwin/arm64|Darwin/x86_64) ;; *) printf 'GITLAMA-BOOTSTRAP 1 platform\n'; exit 3;; esac; case "$p" in Darwin/*) for d in /usr/local/bin /opt/homebrew/bin; do [ ! -x "$d/git" ] || PATH="$d:$PATH"; done; export PATH;; esac; [ -x "$h" ] || { printf 'GITLAMA-BOOTSTRAP 1 missing %s\n' "$p"; exit 3; }; exec "$h" --stdio
```

No repository path, ref, message or other user input is ever part of the command. It runs under
the account's login shell, including macOS's default `zsh`. On a Mac a noninteractive login sees
only Apple's Git shim, so a Git in `/opt/homebrew/bin` or `/usr/local/bin` comes first when
present.

Before a hello, stdout may instead hold exactly one bootstrap line followed by end of file:

| Bytes | Meaning |
| --- | --- |
| `GITLAMA-BOOTSTRAP 1 missing <host>\n` | No executable helper for this build is installed; `<host>` is `Linux/x86_64`, `Linux/aarch64`, `Darwin/arm64` or `Darwin/x86_64` and selects the helper to offer |
| `GITLAMA-BOOTSTRAP 1 platform\n` | The host is none of those platforms |

Any other bytes before end of file, or a frame that is not a valid hello, are a generic
bootstrap failure. An SSH exit status of 255 before a hello is only `sshConnectionFailed`;
authentication, host key and name resolution failures are not told apart.

## Installation

Installation is a separate SSH invocation that runs after the user confirmed it, or while
connecting a host the user allowed to install automatically, at most once per connection attempt
and only after the launch reported the helper missing. It uses the same options with a fixed POSIX script in place of `<launch>`. Its only
variable parts are the validated build ID, the lowercase SHA-256 of the helper and the host
platform the helper was built for:

1. `umask 077`; refuse a host of another platform than the helper's, and a host with neither
   `sha256sum` nor `shasum`.
2. Refuse a symbolic link at `~/.local/lib/gitlama`, its `remote` directory, the build directory
   or the helper path; create the directories with mode 0700.
3. Read at most 128 MiB + 1 byte of standard input with `head -c` into
   `<build-dir>/.gitlama-remote-helper.<pid>`, removed on exit by a trap.
4. Check the size (`wc -c` without its padding), the SHA-256 (`sha256sum`, else
   `shasum -a 256`), mode 0700, and that `--version` reports `"buildId":"<build-id>"`.
5. Rename the file over `<build-dir>/gitlama-remote-helper`.

The client writes exactly the helper bytes, closes standard input and reads the last non-empty
line of at most 4096 output bytes (login scripts may print first):

| Line | Meaning | Client failure |
| --- | --- | --- |
| `GITLAMA-INSTALL 1 installed` | The helper is in place (exit 0) | – |
| `GITLAMA-INSTALL 1 platform` | Not the helper's platform | `unsupportedPlatform` |
| `GITLAMA-INSTALL 1 tools` | Neither `sha256sum` nor `shasum` | `installFailed` |
| `GITLAMA-INSTALL 1 directory` | A symbolic link or an uncreatable directory | `installDirectory` |
| `GITLAMA-INSTALL 1 write` | Writing or renaming failed, or the input was too large | `installWrite` |
| `GITLAMA-INSTALL 1 digest` | The received bytes do not match | `installDigest` |
| `GITLAMA-INSTALL 1 execute` | The helper does not run or reports another build | `installExecute` |

No line and exit status 255 is `sshConnectionFailed`; anything else is `installFailed`. Cancel
and a 10-minute timeout terminate the SSH process. An installation is idempotent: retrying
uploads and verifies again, and a running helper keeps its open file.

## Handshake

The helper writes a hello frame first, before any repository or Git work except a bounded
`git --version` probe:

```json
{
  "kind": "hello",
  "magic": "gitlama-remote-helper",
  "protocolMajor": 1,
  "protocolMinor": 0,
  "buildId": "<40 hex>",
  "platform": "linux",
  "architecture": "x86_64",
  "gitState": "available",
  "gitVersion": "2.43.0",
  "helperIncarnation": "<32 hex>",
  "store": {"state": "ready", "storeId": "<32 hex>"},
  "account": {"uid": "1000", "name": "alice"},
  "capabilities": ["read", "listDirectory", "stage", "commit", "refs", "stash", "transfer"],
  "limits": {
    "frameBytes": "4194304",
    "transactionBytes": "16777216",
    "requestsPerConnection": "32",
    "sessionsPerConnection": "16"
  }
}
```

- `gitState` is `available`, `missing` or `unsupported` (older than 2.39.0); `gitVersion` is
  `null` unless Git answered.
- `store.state` is `ready` or `unavailable`; `storeId` is `null` when unavailable. A client
  never attaches workspace state to an unavailable store.
- `account.name` is display data, at most 128 bytes; `uid` is the effective user ID.
- Capabilities are a closed set: `read`, `listDirectory`, `stage`, `commit`, `refs`, `stash`,
  `transfer`, `discard`, `history`, `recovery`, `extensions` and `initialize`. Unknown values are
  ignored by the client; absent values are never assumed. The write capabilities (all but `read`
  and `listDirectory`) appear only when the receipt store is usable.
- Each limit is a decimal string. The effective limit is the smaller of the two peers' values.

The client answers within 10 seconds:

```json
{
  "kind": "helloAck",
  "protocolMajor": 1,
  "protocolMinor": 0,
  "buildId": "<echo>",
  "helperIncarnation": "<echo>",
  "connectionNonce": "<32 hex, fresh per connection>",
  "capabilities": ["read", "listDirectory"]
}
```

The client sends an acknowledgement only when the major version is 1, the build ID equals its
own, `magic` matches and Git is available. Its capabilities are a subset of the hello's. The
helper checks the major version, build ID, incarnation, nonce syntax and capability subset; on
any mismatch, or without an acknowledgement within 10 seconds, it writes a `fatal` frame and
exits without opening a repository or listing a directory.

## Envelopes

Every frame after the acknowledgement, in both directions, is an envelope with exactly these
keys:

```json
{
  "protocolMajor": 1,
  "connectionNonce": "<32 hex>",
  "helperIncarnation": "<32 hex>",
  "requestId": "<decimal>",
  "kind": "<kind>",
  "payload": {}
}
```

A peer rejects an envelope whose major, nonce or incarnation differs from the handshake.

Client request IDs start at `1` and strictly increase; `0` is invalid from a client. Helper
messages answering a request carry its ID. Unsolicited publications carry `"0"` and a
`sequence` that starts at `1` and strictly increases. A counter that would overflow retires the
connection.

### Client kinds

| Kind | Payload | Helper answer |
| --- | --- | --- |
| `call` | `{"method": <name>, "args": {...}}` | One `result` with the same request ID |
| `cancel` | `{"target": "<request id>"}` | None. A queued call is dropped and answered `canceled`; a running call cannot be preempted and its late result is still sent. |
| `ping` | `{}` | `pong` |
| `shutdown` | `{}` | `goodbye`, then the helper closes every session and exits |

### Helper kinds

| Kind | Payload |
| --- | --- |
| `result` | `{"ok": <value>}` or `{"error": {"code": "<code>"}}` |
| `publication` | `{"sequence": "<decimal>", "type": "sessionEvents", "sessionId": "<decimal>", "events": <NativeRepositoryEventsResult>}` |
| `chunk` | See [transactions](#transactions) |
| `pong`, `goodbye` | `{}` |
| `fatal` | `{"code": "<code>"}`; the helper exits afterwards |

### Transactions

A `result` or `publication` larger than 1 MiB is sent as a transaction of `chunk` frames. Each
chunk's request ID is the request ID of the carried envelope (`"0"` for a publication):

```json
{
  "transaction": "<decimal, from 1, strictly increasing per connection>",
  "index": "<decimal, from 0>",
  "count": "<decimal, 2..16>",
  "totalBytes": "<decimal, at most 16 MiB>",
  "digest": "<64 hex SHA-256 of the complete carried bytes>",
  "data": "<base64 of at most 1 MiB>"
}
```

The carried bytes are the complete JSON of the inner envelope. Chunks of one transaction arrive
in index order; chunks of different transactions may interleave. The client keeps at most four
assembling transactions and 32 MiB of assembled bytes per connection. Only after the last chunk,
an exact length match and a digest match does it parse the inner envelope (with transaction
bounds) and process it as if it were one frame. The inner envelope's request ID must equal the
chunks'. Any mismatch is a protocol violation. A partial transaction is discarded on disconnect
and is never presented.

## Methods

Request arguments and results for repository reads are the generated codecs of the bridge
function of the same name (`repositorySessionHistoryLoad` and so on). The method set is closed;
`READ_METHODS` in `rust-core/application/src/wire/generated.rs` and `remoteReadMethods` in
`lib/repositories/impl/repository_session_calls.g.dart` list the reads. Every other name is
answered `unsupportedCommand`. There is no command that runs Git, a shell, an arbitrary
executable or writes a file on behalf of the client.

`repositorySessionPatchExportContent` builds a patch on the host and returns its file name and
first page of at most 1 MiB; `repositorySessionPatchExportContentPage` returns the rest of the
same bytes by offset. The host never writes the patch: the client saves it on its own computer.

`repositorySessionChangeSource` and `repositorySessionWorkingChangeSource` keep the stored bytes
of both sides of a changed file (at most 64 MiB each) and return their sizes;
`repositorySessionChangeSourcePage` reads either side by offset, 1 MiB at a time.
`repositorySessionDiffRendererInput` returns the input a diff renderer reads for a loaded diff (at
most 8 MiB). The helper decodes no images and runs no tools: the client decodes images, runs
external diff tools on private copies and runs diff renderers on its own computer.

The reads also cover the state the history, recovery and extension writes act on: conflicts
(`repositorySessionConflicts`), isolated conflict prediction
(`repositorySessionConflictPredictionBegin`, `…Prediction`, `…PredictionCancel`; it writes only
temporary object storage outside the repository), rebase and restack plans, fixup suggestions,
named snapshots, bisect state, the repository's
worktrees, submodules and LFS files (`repositorySessionExtensions`, `repositorySessionLfsPointer`,
`repositorySessionSubmoduleEnter`) and the statistics and content-search jobs
(`repositorySessionStatisticsStart`/`Poll`, `repositorySessionDiffContentSearchStartConfigured`/
`Poll`, `repositorySessionPowerJobCancel`). Plans, prediction and fixup suggestions are bulk.

`sessionId` arguments name helper sessions as returned by `openRepository`. The helper rejects a
session ID that it did not open on this connection with `unknownSession`.

Reads are interactive (30-second client deadline) or bulk (120 seconds): `repositorySessionHistoryComplete`,
`repositorySessionHistoryQuery`, `repositorySessionBlameLoad`, `repositorySessionPathHistory`,
`repositorySessionRangeHistory` and `repositorySessionDiffSearch` are bulk. The helper serves
interactive work before bulk work. A deadline is not proof that the helper stopped the work.

### `listDirectory`

```json
{"directory": "<base64 absolute path>" | null, "cursor": "<opaque>" | null}
```

`null` lists the account's home directory. The result:

```json
{
  "directory": "<base64 canonical absolute path>",
  "parent": "<base64>" | null,
  "entries": [{"name": "<base64>", "kind": "directory", "repository": false}],
  "cursor": "<opaque>" | null,
  "truncated": false
}
```

`kind` is `directory`, `file`, `symlink` or `other`. Pages hold at most 200 entries sorted by
name bytes. The scan reads at most 10 000 entries, 2 MiB of names or two seconds; `truncated`
reports a bounded scan. `repository` is a cheap check for a `.git` entry, not a full discovery.
Cursors are bound to the directory's device, inode and modification time, expire after 60
seconds and at most four live per connection. A changed directory answers `directoryChanged`.
Symbolic links are never followed while listing; listing a symlink path resolves it once to its
canonical directory, which the result reports.

### `openRepository`

```json
{"path": "<base64 absolute path>", "generation": "<decimal>", "expectedBinding": "<64 hex>" | null}
```

Paths are absolute, at most 16 KiB, without NUL and without `~`, variables or globs. The helper
opens a shared Repository session (subscribing before load), waits up to ten seconds for the
discovered identity and answers:

```json
{"binding": "<64 hex>", "open": <NativeRepositoryOpenResult>}
```

The binding is SHA-256 over the store ID and the device, inode and canonical bytes of the
worktree root and common Git directory. With `expectedBinding`, a different binding closes the
new session and answers `identityMismatch`. At most sixteen sessions are open per connection.

### `initializeRepository`

```json
{"path": "<base64 absolute path>", "initialBranch": "main", "bare": false}
```

Needs `initialize`; without it the helper answers `writeNotPermitted`. The path follows the rules
of `openRepository`; missing directories are created. The helper runs the core's destination
checks and `git init [--bare] -b <initialBranch> <path>` and answers:

```json
{"failure": null | "<NativeRepositoryFailureKind>"}
```

`existingRepository`, `destinationNotEmpty`, `destinationNotDirectory` (a file or a symbolic
link), `permissionDenied`, `discovery`, `missingGit`, `initializationFailed` and `invalidOptions`
(an unacceptable branch name) report why nothing was created. The client then opens the new
repository with `openRepository`.

Initialization has no receipt, preview or lookup, unlike the R2 writes. It only creates a
repository where there is nothing to lose: a missing or empty directory. An answer lost to a
disconnect is resolved by asking again, which reports `existingRepository` when the first call
ran, and by opening the path; a repeated call never initializes twice, because it finds the first
call's repository.

### `closeRepository`

`{"sessionId": "<decimal>", "generation": "<decimal>"}` answers a
`NativeRepositoryCommandResult`. Closing an unknown session is a successful no-op.

### Operation center

| Method | Arguments | Result |
| --- | --- | --- |
| `operationCenter` | `{"maximumEntries": 1–256}` | `<NativeOperationCenterResult>` of the helper's sessions |
| `operationDismiss` | `{"sessionId", "generation", "activityId"}` | `<NativeRepositoryCommandResult>` |

Both need `read`. The client shows the entries in its operation center under its own session
identifiers, never cancels or retries them, and asks often only while one runs or shortly after a
write; otherwise every few seconds.

### Session events

The helper drains each open session's events every 25 milliseconds and publishes them as a
`sessionEvents` publication. When stdout is congested it merges pending publications per
session, keeping only the newest snapshot event and every other event. Publications never
complete a request.

## Error codes

`invalidRequest`, `unsupportedCommand`, `unknownSession`, `capacity`, `canceled`, `timedOut`,
`pathInvalid`, `pathNotFound`, `permissionDenied`, `notDirectory`, `cursorExpired`,
`directoryChanged`, `identityMismatch`, `writeNotPermitted`, `previewExpired`,
`preconditionFailed`, `operationIdConflict`, `admissionEpochRetired`, `receiptCapacity`,
`storeUnavailable`, `internal`. Fatal codes: `protocolViolation`, `handshakeRejected`,
`handshakeTimeout`, `shutdown`.

## Liveness and shutdown

The client pings every 15 seconds; no frame for 45 seconds marks the connection disconnected.
Pings never trigger repository work. On `shutdown`, end of stdin or a protocol violation, the
helper stops admitting work, closes every session and exits within five seconds. A helper never
listens on a socket and never outlives its SSH channel.

## R2 writes

Writes are admitted only when both peers negotiated the capability and the client enabled
writes for the verified host. See the R2 section of [the architecture](ARCHITECTURE.md) for the
receipt contract.

| Method | Arguments | Result |
| --- | --- | --- |
| `previewStage` | `{"sessionId", "generation", "request": <NativeStagingRequest>}` | `{"token", "epoch", "digest", "expiresInMs"}` |
| `executeStage` | `{"sessionId", "generation", "token", "epoch", "digest", "operationId", "request": <NativeStagingRequest>}` | `{"operation": <operation>, "result": <NativeStagingExecutionResult> | null}` |
| `previewCommit` | `{"sessionId", "generation", "request": <NativeCommitRequest>}` | `{"token", "epoch", "digest", "expiresInMs", "preview": <NativeCommitPreviewResult>}` |
| `executeCommit` | `{"sessionId", "generation", "token", "epoch", "digest", "operationId"}` | `{"operation": <operation>, "result": <NativeCommitExecutionResult> | null}` |
| `previewRefs` | `{"sessionId", "generation", "request": <NativeRefMutationRequest>}` | `{"token", "epoch", "digest", "expiresInMs", "preview": <NativeRefMutationPreviewResult>}` |
| `executeRefs` | `{"sessionId", "generation", "token", "epoch", "digest", "operationId"}` | `{"operation": <operation>, "result": <NativeRefMutationExecutionResult> | null}` |
| `previewStash` | `{"sessionId", "generation", "request": <NativeStashRequest>}` | `{"token", "epoch", "digest", "expiresInMs", "preview": <NativeStashPreviewResult>}` |
| `executeStash` | `{"sessionId", "generation", "token", "epoch", "digest", "operationId"}` | `{"operation": <operation>, "result": <NativeStashExecutionResult> | null}` |
| `previewTransfer` | `{"sessionId", "generation", "request": <NativeTransferRequest>}` | `{"token", "epoch", "digest", "expiresInMs", "preview": <NativeTransferPreviewResult>}` |
| `executeTransfer` | `{"sessionId", "generation", "token", "epoch", "digest", "operationId"}` | `{"operation": <operation>, "result": <NativeTransferExecutionResult> | null}` |
| `previewDiscard` | `{"sessionId", "generation", "request": <NativeDiscardRequest>}` | `{"token", "epoch", "digest", "expiresInMs", "preview": <NativeDiscardPreviewResult>}` |
| `executeDiscard` | `{"sessionId", "generation", "token", "epoch", "digest", "operationId"}` | `{"operation": <operation>, "result": <NativeDiscardExecutionResult> | null}` |
| `lookupOperation` | `{"epoch", "operationId", "digest"}` | `{"operation": <operation>}` |

The later families follow the same two shapes. A previewed family's Execute carries no request;
a direct family (marked *) has no core preview, and its Execute repeats the previewed request,
which must match the digest. Requests that are not a bridge type are objects with exactly these
keys (absent values `null`):

| Family (`preview…`/`execute…`) | Capability | Request | Core call |
| --- | --- | --- | --- |
| `History` | `history` | `<NativeHistoryMutationRequest>` (merge, cherry-pick, revert) | `repository_session_history_mutation_*` |
| `Rebase` | `history` | `{"planToken", "instructions": [<NativeRebaseInstruction>], "acknowledgePublishedHistory", "applyAutosquash"}` | `rebase_preview`, `rebase_execute` |
| `Restack` | `history` | `{"planToken", "acknowledgePublishedHistory"}`; the plan's token is executed | `restack_execute` |
| `Bisect` | `history` | `{"action", "good", "bad"}` | `bisect_preview`, `bisect_execute` |
| `Conflict`* | `history` | `{"action": "chooseSide" \| "takeRegion" \| "saveResult" \| "undoResolution", "path", "expectedFingerprint", "side", "regionIndex", "region", "result"}` | `conflict_choose_side` and so on; a merged result is at most 8 MiB |
| `Sequencer`* | `history` | `{"action": "continue_" \| "skip" \| "abort", "message"}` | `conflict_continue` / `…_with_message` |
| `Snapshot`* | `recovery` | `{"action": "create" \| "delete" \| "branch", "name", "includeUntracked", "keepIndex", "snapshotId", "branch"}` | `named_snapshot_create`, `…_delete`, `…_branch` |
| `SnapshotRestore` | `recovery` | `{"snapshotId"}` | `named_snapshot_restore_*` |
| `Restore` | `recovery` | `{"commit", "path", "byteLimit"}` | `restore_preview`, `restore_file` |
| `IndexLock` | `recovery` | `{"token"}` from `repositorySessionInspectIndexLock` | `remove_index_lock` |
| `Patch` | `recovery` | `{"content"}`, the patch bytes (at most 8 MiB) | `patch_apply_preview`, `patch_apply_execute` |
| `Extension`* | `extensions` | `<NativeExtensionMutationRequest>`; a worktree root is a host path without remote authority | `extension_execute` |

The helper keeps a patch to apply in a private file under
`~/.local/state/gitlama/remote-helper/patches/` from its preview until its execution or expiry,
because the core checks the file again before applying it; files older than two preview lifetimes
are removed when a helper starts. Cancelling a running write is not offered: the client only
drops a preview it never executed.

Each preview and execute needs its own capability (`previewRefs` needs `refs`, and so on);
`lookupOperation` needs any write capability. `refs` covers branch create, rename, delete and
checkout, tags, upstreams, remote configuration and reset; a reset names its mode and only a
reset has one. A commit may amend, skip hooks or disable signing when the user chose to, as on
this computer. A transfer runs
with the host's own Git credentials and host keys and never prompts; credentials are never sent
to the helper. Before every preview except staging the helper reloads the session's snapshot,
because it sees no file events between refreshes.

The outcome of a later family follows the `state` its result reports: `completed`,
`alreadyContained`, `reconciledWithWarning`, `restored` and `aborted` are `succeeded`;
`conflict`, `interrupted`, `editStop` and `partial` are `partial`; `stale` is `notApplied`;
`canceled` is `notApplied` when the evidence is unchanged; `outcomeUncertain` is `unknown`; any
other failure is `failed` with unchanged evidence and `unknown` otherwise. A conflict resolution
succeeds when its result reports no failure, an index-lock removal when it reports `removed`.

`<operation>` is `{"operationId", "epoch", "state", "outcome", "resultObjectId"}`:

| `state` | Meaning |
| --- | --- |
| `prepared` | Admitted durably; no executor started yet |
| `started` | Durably recorded before Git ran; the outcome may be unrecorded |
| `terminal` | The outcome below is recorded |
| `absent` | Lookup only: no receipt exists. Absence never proves the write did not run |

`outcome` is `null`, `succeeded`, `failed` (Git ran and refused, for example a rejecting hook,
with every piece of the family's evidence readable and unchanged), `notApplied`,
`desiredStateObserved`, `partial` (the operation ran and left work to finish, such as a stash
pop with conflicts; its result says what remains) or `unknown`. A failed push, tag push or
remote branch deletion is `unknown` unless it ended before the server could update a ref
(a local precondition, authentication, host key or the server's refusal). A
lookup also reports `running` while the receipt's owner still holds the repository lock, and
reports a `prepared` receipt of a dead owner as `notApplied` and a `started` one as `unknown`.
Executing an operation identifier that already has a receipt returns that receipt with a `null`
result and never runs Git again; the same identifier with a different digest or binding is
`operationIdConflict`.

Tokens are single use, expire after 120 seconds, belong to one session and incarnation and are
invalidated by an epoch rotation. The intent digest is SHA-256 over a domain tag, the family,
the workspace binding and the canonical JSON of the typed request (objects with sorted keys).
Evidence of a write is semantic, never raw index bytes whose stat data Git refreshes on its own:

| Evidence | Digest of | Families |
| --- | --- | --- |
| `index` | `git ls-files --stage -z` | all except bisect |
| `head` | what HEAD names and resolves to | commit, refs, stash, transfer, history, rebase, restack, sequencer, bisect, snapshot, snapshotRestore, extension |
| `refs` | every ref with its target and symbolic target | refs, stash, transfer, history, rebase, restack, sequencer, bisect, snapshot, snapshotRestore, extension |
| `config` | `git config --local --list -z` | refs, transfer, extension |
| `stash` | every stash entry (`git log -g refs/stash`) | stash, snapshot |
| `worktree` | porcelain v2 status, the binary diff of tracked changes and the size, time and mode of untracked files | refs, stash, transfer, discard and every later family except index lock |
