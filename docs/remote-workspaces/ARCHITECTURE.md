# Remote workspace architecture

Status: implementation design, 2026-10-05, with the [implementation record](#implementation-record) of what was built. The wire contract is [the protocol](PROTOCOL.md). Read [vision](VISION.md) and [implementation](IMPLEMENTATION.md) together with it.

## Existing baseline and intake

The source inspected for this design was GitLama `14b81a32a3333011496fb7cef0cb26227540d50f` with shared `devmil-git` checkout `4daa8611fdd43d42e3c3ea8720458dd14806e345`. Both trees were clean at inspection. The CI preparation script names the same shared revision. These are provenance, not permanent feature pins; re-inspect committed APIs before implementation.

| Existing boundary | Observed shape | Required remote adaptation |
| --- | --- | --- |
| `lib/repositories/repository_session_repository.dart` | `open(String path, generation)` and lossless `openIdentity`; many typed read/mutation methods | Add a location-aware service backend contract; preserve local behavior and reject unsupported remote commands before transport |
| `lib/services/repository_session_service.dart` | Tabs, generations, requests, event draining, drafts and workflow policy | Route by typed location/backend; retain one UI workflow owner; separate connection freshness from repository phase |
| `rust-core/src/api.rs` | `OwnedRepositorySession` owns shared Repository, subscription, graph/diff projections and preview maps | Extract reusable GitLama application projections/use cases behind headless Rust entry points; FRB exports remain a local adapter |
| `rust-core/application/src/operations.rs` | Mutation coordination and existing uncertain/degraded states | Audit classifications for remote crash/cancellation; add durable receipts rather than treating SSH exit as Git outcome |
| `rust-core/application/src/storage.rs` | Schema 12; Unix-byte/Windows-UTF-16 `NativePathIdentity`; worktrees keyed by native paths | Migrate to explicit local/remote location keys and separate remote profiles/intents; do not convert remote bytes to client paths |
| `rust-core/application/src/view_cache.rs` and local view-cache service | Disposable cache keyed by a local native path | R1 bypasses disk content cache for remote sessions; keep received snapshots in bounded memory only |
| `rust-core/application/src/transfer.rs`, `clone.rs`, `integrations.rs` | Native credentials, process actions and recovery assume local execution | Disable remotely until each location/credential/recovery contract is implemented |
| `rust-core/src/cli_forwarding/` | User-local authenticated command-forwarding protocol | Do not reuse its token or expose it remotely; SSH protocol is a distinct boundary |

Generic Git process/parsing/watcher changes belong in `devmil-git`; GitLama graph presentation, preview policy, receipts and wire DTOs belong here.

## Selected design and alternatives

Use a foreground helper with a versioned protocol over an SSH command's stdin/stdout. One SSH process supports at most sixteen open repository sessions and is owned by one local connection object. A helper runs as the SSH account and is started for that connection, with no public listener or installed system service.

| Alternative | Decision and reason |
| --- | --- |
| SSHFS/network-mounted checkout with client-side Git | Not the supported backend: filesystem semantics, many metadata round trips and remote environment differences complicate correctness |
| One `ssh host git ...` call per query | Useful only in experiments; does not supply session ownership, efficient event delivery, lossless command data or durable outcomes |
| Local mirror plus synchronization | Different product semantics; cannot represent the remote index and unfinished work faithfully |
| Persistent helper daemon exposed by TCP | Unnecessary service/authentication/upgrade surface for the initial feature |
| Foreground helper over SSH | Selected; transport security/authentication remains OpenSSH, work stays beside the repository and protocol is application-owned |

The helper can reconnect to durable identity/receipts, but cannot reattach to a prior live process. Each new SSH connection starts a new helper incarnation. Operation receipts, not a retained process, provide crash/reconnect continuity.

## Components and dependency direction

```text
Flutter widgets / command registration
  -> RepositorySessionService (tabs, drafts, preview UX, application policy)
      -> RepositoryBackend service port / BackendRouter (typed location routing)
          -> LocalRepositoryBackendService
              -> existing NativeRepositorySessionRepository -> FRB -> Rust use cases
          -> RemoteWorkspaceService
              -> RemoteRepositorySessionRepository (Dart network adapter)
                  -> owned dart:io SSH process + bounded wire codec
                      -> SSH stdin/stdout
                          -> gitlama-remote-helper (Rust, no Flutter dependency)
                              -> GitLama headless use cases / projections
                                  -> devmil_git::Repository + shared Git primitives
                                  -> remote private identity/receipt/recovery store
```

`RepositoryBackend` is a service-facing contract with the currently supported typed repository commands plus `WorkspaceLocation` and capabilities. `BackendRouter` lives in the service layer; it dispatches by authoritative session identity, never by a user-visible path string. `LocalRepositoryBackendService` owns the existing native repository; `RemoteWorkspaceService` owns the remote network repository. Other services, including History and Operation Center, call backend service ports rather than obtaining a second owner of a repository. Extract the smallest routing/ownership slice; do not rewrite every screen or duplicate repository workflows.

Register implementations in `lib/di/app_components.dart`, expose initialized services through `AppRuntime`, and test with isolated composition. Transport/protocol mapping never belongs in widgets. The existing FRB path remains the only in-process native bridge. The remote adapter is a network boundary, not a second C ABI or platform-channel Git interface.

The local SSH child is **Dart-owned** using `dart:io Process.start` with `runInShell: false`; a qualified owner drains stdout/stderr and owns exit/cancellation. This avoids introducing an unqualified native child reaper inside Flutter. It runs asynchronous I/O; frame decoding above the per-turn budget moves to an owned Dart worker isolate. The helper is a standalone Rust executable, so its shared Rust Git subprocess owner operates outside the Dart runtime. Test both situations through their actual runtime entry paths.

Proposed Rust organization after the extraction proof:

```text
rust-workspace/
  Cargo.toml / Cargo.lock              # workspace members, one locked graph
  application/                        # headless GitLama session/use-case/projection library
  remote-protocol/                     # serde wire DTOs, validation, fixtures
  remote-helper/                       # Linux and macOS executable; stdin/stdout, stores, lifecycle
rust-core/                            # existing FRB crate, depends on application/protocol
lib/models/remote_workspace.dart
lib/services/repository_backend.dart
lib/services/remote_workspace_service.dart
lib/repositories/remote_repository_session_repository.dart
lib/repositories/impl/ssh_remote_repository_session_repository.dart
```

Final crate paths must be chosen in RW-02 after checking hook/packaging assumptions. Prefer a single root Cargo workspace that includes `rust-core`; the schematic above is organizational guidance, not permission to leave excluded manifests unverified. Every external source reached by the native hook must be an invalidating input. The helper must build without FRB/Flutter, keychain SDKs, OAuth/provider runtime or image renderer dependencies it does not use. Remote R1 image previews use an explicit unsupported state until bounded transport/decoder acceptance is added.

## Host profile and SSH contract

R1 profiles contain a random UUID, a display name, an OpenSSH destination alias and the last explicitly verified remote store/account identity. No password, key bytes, arbitrary command, environment assignment or free-form SSH options are persisted. The normal user/system SSH configuration is the authority for host, port, identity files and ProxyJump/ProxyCommand.

Destinations accept a host alias, hostname or `user@host`, up to 128 ASCII characters total. Each part starts with an ASCII letter or digit and contains letters, digits, dots, underscores or hyphens. Ports, SSH options, whitespace and shell syntax are rejected. Existing SSH keys and agent authentication are used; the host must already be trusted. Password prompts and reuse of another application’s live SSH connection are unsupported. The same rule applies to the host form, `--remote` and `ssh://` links.

Build an argument array, never a local shell command. Use a resolved installed OpenSSH client; do not search the repository directory. R1 invocation policy:

| Setting | Required value / behavior |
| --- | --- |
| TTY and stdin | `-T`, `RequestTTY=no`, `StdinNull=no`; stdin carries protocol and must not use `-n` |
| Authentication | `BatchMode=yes`; existing loaded agent/noninteractive key/certificate; no GUI password or passphrase prompt |
| Host keys | `StrictHostKeyChecking=yes`; existing user/system known-hosts and certificate policies; never `accept-new`, `no` or automatic `ssh-keyscan` trust |
| Forwarding | `ForwardAgent=no`, `ForwardX11=no`, `ClearAllForwardings=yes`, `GSSAPIDelegateCredentials=no` |
| Ownership | `ControlMaster=no`, `ControlPath=none`, `ForkAfterAuthentication=no`; do not borrow or kill a user's master connection |
| Execution | `RemoteCommand=none`, `SessionType=default`, `PermitLocalCommand=no`; one application-controlled helper launch command |
| Connect/liveness | `ConnectTimeout=10`, `ConnectionAttempts=1`, `ServerAliveInterval=15`, `ServerAliveCountMax=3`; application handshake and frame deadlines are separate |

Evaluate these overrides against supported OpenSSH versions in RW-04; unsupported flags are a typed setup failure, not an invitation to remove trust/ownership restrictions. User SSH config is trusted executable configuration: ProxyCommand, Match exec and user helpers can run programs. Do not import configuration from a repository. Jump hosts have their own config/trust; qualify the configured chain rather than assuming destination overrides cover every hop.

SSH remote execution is a shell-command boundary: OpenSSH joins supplied remote command arguments with spaces. Consequently the launch string contains only a fixed quoted helper location with a validated lowercase hex build ID and fixed `--stdio` arguments; no repo paths, refs, commit messages or user input. Read [ssh(1)](https://man.openbsd.org/ssh) and [ssh_config(5)](https://man.openbsd.org/ssh_config) before implementing this boundary.

R1 uses `"$HOME"/.local/lib/gitlama/remote/<build-id>/gitlama-remote-helper --stdio` under a POSIX-compatible remote command shell, with the actual launch expressed as `exec` and each application-controlled word safely quoted. `$HOME` comes from the remote environment; it is never interpolated from a client field. The build ID is the 40-character lowercase hexadecimal application source commit; signed artifact metadata additionally binds target and binary digest. Random nonces/incarnations/store/session/token/operation/epoch IDs use 16 cryptographically random bytes encoded as 32 lowercase hex characters. Profile UUIDs use the application's canonical UUID representation and remain configuration IDs. Custom helper paths and arbitrary login-shell sourcing are outside R1. Non-POSIX remote command shells receive a generic bootstrap/setup failure unless a structured probe establishes the cause.

On failure before a valid helper hello, an SSH exit status of 255 is only `sshConnectionFailed`. Do not classify authentication vs host key vs DNS by localized stderr prose or assume it reports a Git exit. Offer stable setup guidance and a connection test outside the app. Stderr is continuously drained with a byte cap and discarded after stable diagnostics; never display or persist its raw bytes. Specific missing-helper/protocol/platform errors are reliable only after structured bootstrap/hello validation, or through a separate tested fixed bootstrap status contract.

Cancel first closes admission, retires generation, sends protocol cancellation if possible, closes stdin, waits two seconds, then terminates the owned SSH process and waits another two seconds before force kill where available. Windows requires a tested process-tree strategy/job boundary, including ProxyCommand descendants; a PID kill alone is not acceptance. Application shutdown is bounded to five seconds locally; unresolved remote mutation outcomes remain pending/unknown. A failed cleanup is surfaced with a stable event code.

## Helper distribution, identity and authority

R1 installation is manual and explicit. Ship a helper artifact with build ID, version, target triple, shared dependency revision, protocol major/minor and SHA-256 in a signed release manifest. Reuse the existing release trust root/verification machinery with a separate helper artifact kind; never treat a digest obtained from the same untrusted download as authenticity. Users install only into their account's private versioned directory. Do not overwrite an active helper, run sudo or automatically download anything on connection.

A helper emits a hello even if Git is missing, so Git discovery cannot masquerade as connection failure. Hello includes protocol versions, build ID, remote platform/architecture, Git availability/version, random per-process incarnation, private-store UUID and effective-account identity. After the client confirms hello, normal requests begin. Host-key validation authenticates the machine/channel; store UUID and account bind application state across sessions. Neither UUID is a security substitute for SSH.

The store UUID is created once in a user-owned, no-follow private directory with atomic write/sync and concurrent-start locking. The account descriptor includes effective UID and a bounded account name; display data never replaces the UID/store binding. A changed store/account on the same profile transitions to `identityChanged`, blocks automatic attachment and presents an explicit rebind action. Rebinding creates a new authority namespace; it never transfers pending intents or drafts silently. Restoring/cloning a host/store can duplicate UUIDs: profile IDs remain separate by default, and merging profiles/workspace history is outside R1. Backup restoration of receipts cannot justify a resend.

Each session receives random helper-local session IDs and an opaque worktree/repository binding. Canonical root, Git dir/common dir and their filesystem identity are resolved by the helper. A path that resolves to a different repository, replaced directory inode, changed store/account or reassigned profile is not the same workspace. On reconnect the helper checks the saved binding; a rename/replacement prompts explicit reopening. Do not migrate authority by matching commit OIDs alone.

## Wire format and limits

Use a 4-byte unsigned big-endian payload length followed by UTF-8 JSON. The protocol crate and Dart codec share committed golden fixtures; generated FRB DTOs are not serialized as the wire contract. Reject invalid UTF-8, duplicate object keys, invalid envelopes and out-of-range values before allocating nested DTOs. Use closed command tags, with additive optional fields allowed only according to negotiated minor versions. Unknown commands return `unsupportedCommand`; unknown critical envelope versions close the channel.

Integer IDs/revisions/offsets are decimal strings, losslessly mapped to Rust `u64`/Dart `BigInt` with range checks; random IDs are fixed lowercase hex strings. Unix native paths/ref names/content bytes are canonical padded base64 fields, never lossy UTF-8 JSON strings. Decode only after encoded-size validation; use escaped safe display strings separately. JSON arrays/objects have explicit cardinality/nesting limits as well as frame limits.

Every post-hello envelope carries `protocolMajor`, `connectionNonce`, `helperIncarnation`, `requestId`, `kind` and a typed payload. Session requests also carry session ID, workspace binding and client generation; publications carry helper repository revision and monotonically increasing publication sequence. Responses additionally carry the query/request revision they answer. The client rejects mismatches before changing UI or completing a different future. Counter overflow retires the connection rather than wrapping.

Client request IDs start at `1` and are not reused during a connection. Unsolicited snapshot/progress/liveness publications use `requestId: "0"`, with their own sequence and optional `causedByRequestId`; they cannot complete an outstanding future. A client-origin request using `0` is invalid. The remote adapter wraps helper-local IDs in a tagged backend/session identity rather than converting random remote IDs into the existing local numeric-ID namespace.

| Bound | Initial contract |
| --- | --- |
| Frame payload | 4 MiB hard maximum; zero-length frames invalid; hello at most 64 KiB |
| Incomplete frame | 15 seconds since first byte; partial byte arrival does not reset the absolute deadline |
| Hello | 10 seconds after transport establishment; no scanning banners until magic JSON appears |
| JSON | Nesting at most 16; collections at most 4096 items unless a smaller command limit applies |
| Remote path / directory entry name | 16 KiB decoded native bytes; no NUL; absolute POSIX path for typed open |
| Directory listing | 200 entries/page; stable opaque cursor; at most 32 KiB name/display data per entry |
| History | 256 rows/page; commit-file lists 200/page; metadata batches 128 OIDs |
| Diff/blob chunks | 256 KiB decoded per chunk; 16 MiB decoded document total; use existing smaller preview limits where applicable |
| Commit message | 1 MiB decoded UTF-8 total; no NUL; remote existing validation still applies |
| Outstanding requests | 32/connection, 8/session; replies/control commands have reserved capacity |
| Connections / sessions | 4 live connections/app, 16 sessions/connection (raised from 8 for real-use experiments; the helper cache is 64 MiB per session with no connection aggregate, so up to 1 GiB per connection), 16 remote tabs/app |
| Transport buffered bytes | 8 MiB/direction/connection hard cap; progress/snapshots coalesce; accepted terminal results are not dropped |
| Snapshot assembly | 16 MiB decoded/session; one transaction/session; 32 MiB/connection aggregate; explicit truncated counts beyond the bound |
| Remote client content cache | 64 MiB/session, 256 MiB/app; no disk content cache in R1 |
| Helper Repository cache | 64 MiB/session through shared cache options; the 512 MiB/connection aggregate is not enforced |
| Admission/read deadlines | Admission 5 seconds; interactive reads 30 seconds; bulk reads 120 seconds; expiry is not proof of remote cancellation |

These are named constants/fixtures, not UI pixel values. Negotiate the smaller supported value for each limit and reject zero/invalid limits; a peer cannot raise a local hard ceiling. Reserve four of the 32 connection request slots and two of the sixteen session slots for cancel/close/lookup/liveness; control handling is independent of blocked data reads. Reserve 2 MiB within each 8 MiB outbound buffer for accepted terminal/control delivery. Tune limits only with measured evidence and update both codecs/tests together. For a large status/refs snapshot, use `SnapshotBegin`/bounded section chunks/`SnapshotEnd` under one revision/sequence transaction; publish only the complete transaction. History/index/graph construction stays remote; never send an unbounded full topology to the client. Blob/diff transfer uses opaque handles bound to request/query/session and ordered chunks with total size/digest; changed files cannot splice different revisions into one document.

Helper queues admit interactive reads ahead of bulk work, with FIFO within classes. Shared Repository remains the read/watch/cache authority; the wire adapter only bounds transport. It does not introduce a second Git read scheduler/cache that bypasses the facade. Queue priority cannot preempt an already running Git command.

When a subscriber is too slow, discard only replaceable projections and send `ResynchronizeRequired` followed by a coherent replacement snapshot. Operation receipts and terminal outcomes have a separate reserved lane. If reserved delivery cannot make progress, close the channel and require durable lookup; do not grow queues indefinitely. Cancel/close/control processing cannot be queued behind a read that it must release.

## Commands and capability negotiation

R1 command families are `HelloAck`, `ListDirectory`, `OpenRepository`, `CloseRepository`, `Refresh`, `Subscribe`, history/metadata/selection, commit/files/diff, working-tree diff, tree/blob, blame, reflog, `CancelRequest`, `Ping`/`Pong` and `Shutdown`. Exact field schemas are frozen in RW-03; no `RunGit`, `RunShell`, arbitrary executable, config edit or general file-write command exists.

Capabilities are a closed negotiated set. Client visibility/enabled state is the intersection of client support, helper support, milestone feature gate, repository kind/state and connection freshness. The helper enforces the same decision independently. Merely hiding a toolbar button is insufficient. Bare repositories expose history/ref reads but no working-tree functions; unborn repositories show empty history with usable status. Image previews, diff search, restore, Git transfers, submodule/LFS commands, external renderers, tools and provider actions are disabled until explicitly mapped and tested. Unknown capabilities are ignored; absent capabilities never default to enabled.

R2 adds only `PreviewStage`, `ExecuteStage`, `PreviewCommit`, `ExecuteCommit` and `LookupOperation` plus operation progress/cancel. “Stage” includes unstage but excludes discard. Whole-file/hunk/line identities retain original bytes and preconditions. Normal commit excludes amend and commit-and-push. Every later mutation gets a specific command schema and semantic reconciliation strategy before enabling it. The first such mutations, refs and checkout (including remote rename), stash, Git transport and discard/clean, are specified as child packages RW-19.A, RW-19.B, RW-21.A and RW-19.C in [the implementation plan](IMPLEMENTATION.md#child-packages-brought-forward) and in [the protocol](PROTOCOL.md#r2-writes); reset, merge, rebase, cherry-pick, revert and undo were added later with their own families; see "Later write families" in the implementation record.

## Remote filesystem and trusted repository boundary

Directory listing is read-only metadata within the logged-in account's normal permissions, not an unrestricted download API. Return names/kinds and opaque identities; do not follow symlink loops or special files during listing. Typed paths are absolute; no `~`, environment expansion or shell globbing. The picker may start at the helper-reported home handle. Scan at most 10,000 entries, 2 MiB total native-name bytes or two seconds, whichever comes first; sort the bounded result and explicitly report `entriesTruncated` when incomplete. Retain at most four directory cursors/session for 60 seconds, bound to directory inode/metadata version. A detected directory change invalidates the cursor and prompts restart; pagination is not a promise of an atomic filesystem snapshot. Truncated folders still support typed absolute-path open without a deep scan.

Repository discovery, canonicalization, native bytes, index access and watcher lifetime stay remote. Relative repository paths are interpreted against the discovered remote root; symlink targets outside it are not opened as ordinary preview files. Stream Git blob content through shared APIs, not path concatenation. FIFOs/devices/sockets are rejected as preview content. Linked worktrees have distinct worktree/index identity but share common Git-dir lock domains.

Opening a repository trusts its Git configuration in the same way as local GitLama. Disable client-side arbitrary executable selection and unsolicited network reads; explicitly set `GIT_OPTIONAL_LOCKS=0` and `GIT_NO_LAZY_FETCH=1` for R1 reads where supported and disable private-index installation. Shared APIs must prove these policies are propagated, or R1 is blocked on an upstream addition. Disable external diff/textconv execution for R1 commands where the shared command supports it. These mitigations do not sandbox Git or all configured filters, and the UI/help must not claim hostile-repository isolation.

SSH trust establishes encrypted authenticated access; it does not make returned content safe. Validate every frame, path handle, count, image/text payload and URL. Remote labels/content can be intentionally displayed as product data but never enter operational logs, exceptions, telemetry or fixtures from real user repositories. All remote failures map to stable localized codes.

## State and reconnect

Connection state and repository phase are orthogonal. Connection states: `idle`, `connecting`, `handshaking`, `ready`, `disconnecting`, `disconnected`, `failed`, `identityChanged`, `retired`. Repository phase keeps the existing `unloaded/loading/ready/failed/closed` semantics, plus an explicit freshness value `current/stale/unavailable`. Do not overload “clean working tree” to mean “connected”.

| Event | Required transition / effect |
| --- | --- |
| Connect | Allocate fresh generation/nonce and SSH owner; no tab authority until hello/account validation |
| Open | Verify location binding, subscribe before load and publish incomplete refs/history then coherent status |
| EOF/read error/heartbeat loss | Retire generation, complete accepted read futures with typed disconnect, preserve received views as stale and writes as pending/unknown |
| Reconnect | User action or the bounded automatic policy below; new process/incarnation/session; verify identity, lookup pending operations, then replace snapshot and enable eligible actions |
| Sleep/wake | Mark session stale when liveness fails; show reconnect and the next automatic attempt; never replay writes or silently create multiple SSH owners |
| Tab close | Reject new tab requests immediately, cancel reads and close session; retain unresolved operation identities independently of the tab |
| Last tab close | Graceful helper shutdown then bounded SSH teardown; pending writes get durable reconciliation entry |
| App restart | Restore disconnected tabs/profiles/drafts and pending intents; connect the hosts of restored remote tabs once; never fetch or execute at bootstrap |

Automatic reconnect (decided 2026-10-09, `RemoteReconnector`): a host whose open tabs lost their connection is reconnected after 2, 5, 15 and 30 seconds and then every minute, for at most ten minutes after the loss. Only failures a later attempt can overcome are retried: a lost connection, a timeout, a failed SSH connection, a helper that did not answer or start. A changed identity, a missing or mismatched helper, missing Git, a deleted profile, a user disconnect and a canceled attempt are never retried. Each attempt is an ordinary reconnect: a new incarnation, writes withheld until it is ready, nothing resent, pending operations looked up. The tab banner names the reason and the next attempt and offers Reconnect now and Stop; after the attempts end it offers Try again. A restored tab's host is connected once at startup without announcing it; a later reconnect shows a notification. Manual repeated reconnect requests share one attempt; cancel creates a fresh attempt only on the next user action. A background tab cannot steal focus when its connection fails or recovers.

Shared watchers on the helper deliver external Git changes. Transport liveness pings do not trigger status scans. Watcher overflow or failure produces coherent refresh or typed degraded state using shared policy. Client selection remains OID/path identity plus query revision; after reconnect revalidate it, show missing selections explicitly and do not select a different item by row position.

## Persistence and location keys

Introduce `WorkspaceLocation = Local { NativePathIdentity } | Remote { profileId, verifiedStoreId, accountBinding, remoteRootBytes, repositoryBinding, worktreeBinding }`. Profile ID is configuration identity; remote canonical bindings are execution identity. Current code must never call `native_path()` on the Remote variant. Render a display label separately and include host context anywhere actions could target two identical paths.

Migrate existing local worktree keys unchanged into Local variants. Profiles, remote tab layout/navigation and locally entered drafts use versioned atomic Rust persistence with explicit absent/unreadable/corrupt/unsupported outcomes. Unknown future remote fields do not turn into Local paths. Profile deletion leaves disconnected tabs/drafts recoverable and never deletes remote files. Editing the alias creates a new verification requirement; old pending operations stay bound to the old verified authority.

R1 persists no fetched remote file/diff/status/history content. Memory snapshots survive a disconnect only while the app is running. On restart the tab is disconnected with its label/layout/draft, not fabricated status. Local view-cache behavior remains unchanged. A future opt-in remote disk cache needs scope, quotas, confidentiality and authority migration tests.

R2 local pending intent stores random operation ID, admission epoch, verified authority/worktree, command family, canonical payload digest, preview summary/precondition references, admission/receipt state and timestamps. Exact request bytes are sent only from the active intent; pending persistence need not retain a complete patch/message for replay. Durable user drafts remain separate. No credential or raw stdout/stderr goes in this store.

Remote state under the account's private store contains UUID, operation receipts and promised recovery objects. Use owner-only directories/files, no-follow directory capabilities, atomic replace plus file/parent sync, bounded parsing, exclusive store/operation locks and migration/corruption reporting. The store must be on a qualified local filesystem; network filesystem lock/durability behavior is outside R2.

R1/R2 remote store layout is fixed under the helper-reported absolute home at `.local/state/gitlama/remote-helper/`: `identity.json`, `admission.json` (R2 epoch metadata), `locks/<common-dir-identity-digest>.lock`, `receipts/<epoch>/<operation-id>.json` and `recovery/<worktree-binding>/` when a recovery capability is implemented. All generated path components are validated hex identifiers; no client path is appended to these roots. Directory/file modes are 0700/0600. Local pending intents live under the current application's durable data root in `remote/pending/`, using the existing platform path discovery and atomic storage owner. Neither store uses preferences, repository files or the disposable view cache.

## Mutation admission and durable outcomes

SSH exit, a deadline, an acknowledged cancel request or absence of a local reply is never a Git commit point. Durable receipts reduce uncertainty but cannot make Git and a separate receipt file one atomic transaction. Exactly-once effects across crashes are not promised; **at-most-once admission plus no blind replay** is the contract.

1. The helper creates a one-use preview token bound to helper incarnation/session, current durable admission epoch, workspace/account binding, exact canonical intent digest, repository preconditions and a 120-second monotonic expiry. Reconnect or epoch rotation invalidates it. Previews grant no execution authority on another connection.
2. On user execution, the client creates a cryptographically random 128-bit operation ID and atomically persists the pending intent **before sending Execute**. Persistence failure prevents sending.
3. The helper validates capability, token, epoch, scope and digest, checks for an existing `(epoch, operationId)`, then acquires the common-Git-dir mutation lock across helper processes. It also uses the shared Repository mutation lease. Revalidate target/index/ref/working-byte preconditions under the lock immediately before execution; Git locks still arbitrate external writers. Under the short store lock recheck current epoch **and operation-ID absence/digest** before exclusive Prepared insertion; rotation or a competing request on another common Git directory cannot race an unrecorded admission. Never overwrite an existing receipt to admit a duplicate.
4. Write/sync a `Prepared` receipt with the operation's exact authority/digest and recovery anchors if promised. Consume the preview and write/sync `Started` before spawning Git. If either durable write fails, do not spawn. Send `Accepted` only after durable admission; failure to deliver Accepted does not permit resending under a new ID.
5. Perform the typed operation using shared commands/cancellation; drain and bound hook/child output. Write/sync a terminal receipt containing confirmed commit point and result identities, then reconcile/recover as separate outcomes. A terminal receipt write failure after mutation gives `outcomeUnknown` or confirmed success with receipt durability degradation, as supported by observed evidence.
6. Reply with receipt identity and typed result. The client durably records terminal status before removing the pending indicator. A local save failure retains a reconciliation task, even if the in-memory UI knows success.
7. After disconnect/restart, `LookupOperation` reads only the old authority/epoch's receipt. The command ID and digest must match. Duplicate Execute for a retained receipt returns it without executing, even if unresolved. A reused ID with a different digest/authority is `operationIdConflict`. If no receipt exists for a retired epoch, Execute is rejected as `admissionEpochRetired`; absence cannot become a new execution.

Cancellation before durable admission can yield `notAdmitted`. After `Started`, cancellation requests process-tree termination but may leave partial index/ref/worktree effects. The helper reconciles before reporting definite not-applied; hooks may also have independent side effects. User cancellation does not imply rollback. Explicit close/EOF stops admission, cancels reads and requests cancellation of writes; helper allows at most 30 seconds for cleanup/receipt reconciliation, then records unknown where possible and exits. Remote SSH-server termination can kill it sooner; tests must cover abrupt death.

R2 writes have a 120-second absolute execution deadline and up to 30 seconds of helper reconciliation/cleanup. The client waits at most five seconds for admission evidence; an expired wait preserves the pending intent and triggers lookup rather than reporting definite failure. After Accepted it shows progress, with a 150-second overall result deadline from that acceptance; lack of a terminal result leads to pending/unknown and read-only lookup. Progress frames do not extend those deadlines. Closing/killing local SSH at its five-second deadline cannot prove the remote write stopped.

Cross-process advisory locks are keyed by verified common-Git-dir filesystem identity in the private store. They coordinate helpers, not external Git. Store state/receipt updates have their own short lock; never hold the global store lock while waiting for Git/network. Release locks explicitly when guard scopes end; test cloned/inherited handles and close-on-exec. Revalidate filesystem identity if the repository moves/replaces; deny when locking/identity cannot be established.

Initial receipt bounds are 10,000 entries or 64 MiB total, 64 KiB/receipt, and 30-day retention for resolved outcomes. Never silently evict unresolved/admitted operations. Reject new writes with `receiptCapacity` if safe compaction cannot free space. Do not prune individual receipts from the current admission epoch: first rotate/sync the random current epoch under the store lock, invalidating all old preview tokens, then compact eligible resolved records from retired epochs. Execute accepts new IDs only in the current epoch; retained old IDs can be looked up but never started again. Retain unresolved records across epochs within the same total quota. A missing old-epoch record remains unknown, even after its retention window, and cannot authorize replay. Store corruption/unreadability blocks writes and means unknown, not not-admitted. Backup restoration cannot prove receipt continuity, so pending clients do not replay even if an old current epoch reappears.

## Reconciliation contract for R2

| Receipt/evidence | Allowed result |
| --- | --- |
| Existing Prepared, proven no executor started after exclusive lock/recovery inspection | `notApplied`; a new preview/user execution is needed |
| Started with still-live owner | `running`; retain operation, do not spawn another executor |
| Durable terminal success with result OID/index evidence | `succeeded`; refresh/recovery degradation remains separate |
| Started after owner death; exact expected final index matches stage receipt target | `desiredStateObserved`; do not claim proven execution or undo eligibility |
| Started commit; expected parent/index tree plus matching resulting commit/ref/reflog evidence | `desiredStateObserved` unless a durable result proves authorship; matching content alone cannot prove this operation caused it |
| Unexpected state, missing receipt, lost store, expiry, unreadable/corrupt store, partial effects | `outcomeUnknown` or `partial`; manual inspect/recovery, no automatic resend |

State observations are useful but do not reconstruct hook side effects or prove which process made a commit. A new operation may be offered only after current-state inspection, explicit acknowledgement of remaining uncertainty and a fresh preview. Preserve the original record. Remote recovery anchors/ledgers stay remote; a local receipt is not a backup. R2 promises no undo UI until its remote recovery contract is qualified.

## Credentials and integrations

SSH login uses local OpenSSH credentials; Git operations from the remote host to a Git remote use that host's credentials. Hosting-provider API requests for local and remote repositories run on the client computer using its configured accounts. Received Git remote URLs use the existing provider host/path mapping, account disambiguation and explicit binding overrides; binding keys retain the complete remote authority and path. Provider resources, review and browser actions do not depend on SSH write permission or a live SSH connection once repository metadata is available. Checkout still requires the host's live refs capability. Provider failures retain the existing typed authentication, permission and network states; the client does not fall back to host accounts or route provider HTTP over SSH. Do not copy credentials or enable agent forwarding implicitly.

R2 normal commit uses the remote Git identity, hooks and signing configuration. No TTY is allocated. Interactive credential/signing prompts are unsupported and must terminate with a typed bounded failure/degraded/unknown outcome as appropriate. The helper isolates stdout of Git/hooks from protocol stdout and retains only bounded redacted Activity content for deliberate display. Ordinary logs use fixed event/failure codes.

R1 disables open-terminal/editor/file-manager, external diff/merge/renderers, custom commands, local patch export/import and OS file drag-out for remote paths. Later integrations distinguish a remote terminal/editor URI from a deliberate downloaded temporary file. Any export uses the platform's local destination picker, validates size/digest, writes atomically and handles overwrite/cancellation; never pass a remote path to a local file API.

## Security and compatibility gates

All launch paths and wire commands are allowlisted. Remote content never becomes Dart code, executable markup, shell text, arbitrary config or unvalidated provider URLs. Trust the selected SSH account to execute the helper; do not describe the helper as a sandbox against that account. The same account can replace its helper/store, so verify binaries/ownership for supply-chain integrity without promising protection from a malicious account owner.

Protocol major must match; negotiated minor is the minimum supported version and gates optional fields/capabilities. R1 requires an exact approved helper build ID for the client release; a later compatibility matrix may relax it after fixture proof. A helper update never replaces running binaries or changes an active session's protocol. Connect the next session to a selected immutable build and keep rollback artifacts. Wrong architecture/glibc, missing executable permission, noexec storage, full disk, missing Git and unsupported Git version are separate setup states when structured evidence permits them; otherwise retain generic bootstrap failure.

Verification covers golden codecs, fuzz/malformed bounds, real-Git fixtures, loopback SSH fault injection, embedded Flutter SSH ownership, three client installed artifacts and each advertised helper target. Test actual ProxyJump, watcher backend and filesystem behavior before making those claims. R0 measurements and local tests are not user-host or physical-platform acceptance.

## Implementation record

Recorded 2026-10-05 against GitLama branch `t3code/3a25bd1e` and shared `devmil-git` `e5f08d1713ebef061372b9140d7002096c6718ee`. Where the build differs from the sections above, this record is authoritative; the reason is given with each difference.

| Concern | Built | Relation to the design |
| --- | --- | --- |
| Headless application backend (RW-02) | `gitlama_core` has a default `desktop` feature (Flutter bridge, keychain, image codecs, CLI forwarding, hosting). The helper links the core without it and executes the same `repository_session_*` API in its own process. | Replaces a separate `application` crate: one projection implementation serves both backends, so remote/local projection parity holds by construction. `cargo clippy -p gitlama_core --no-default-features` guards the headless build. |
| Rust workspace | `rust-core/Cargo.toml` is the workspace root with members `.` (`gitlama_core`, the FRB facade and desktop-only services), `contract` (`gitlama_contract`, the bridge types), `application` (`gitlama_application`, domain, use cases and the wire adapter) and `remote-helper`; one lockfile. The Flutter build hook builds only the core package; the helper depends on the application crate without its image codecs, never on the core. | As designed; split into crates on 2026-10-12 (LAY-7). The helper, contract and application have version `0.0.0`; the helper's identity is the build ID. |
| Wire DTOs (RW-03) | `tooling/remote_wire/generate.py` derives strict Rust and Dart codecs from the bridged types and the read allowlist (`tooling/remote_wire/surface.json`). Field names are the Dart names. | Generated rather than hand-written DTOs; R1 binds client and helper to one build ID, so the generated shape is the versioned contract of that build. `--check` keeps it fresh. |
| Call seam | `NativeRepositorySessionRepository` calls a generated `RepositorySessionCalls` interface. Locally it forwards to the bridge; remotely `RemoteSessionCalls` encodes allowlisted reads and rejects every other call before sending. | The remote adapter reuses every existing model mapping. |
| Location and authority (RW-02/08) | `NativePathIdentity.remote` (`RemoteAuthority`: profile, store, account) marks remote identities in Dart and Rust persistence; local path conversions in Rust (`native_path`, `native_identity_bytes`, open identity, view cache) and Dart (session open, view cache, icons) reject them. `RepositorySessionIdentity.backend` routes sessions; remote session IDs are allocated from 2^62 upward. | Realizes `WorkspaceLocation` without renaming every local key. Helper-local session IDs are the core's sequential IDs inside the helper process, which serves exactly one connection; the client never uses them as local IDs. |
| Routing | `RepositoryBackendRouter` (services) implements every repository session interface and is the `RepositorySessionService` repository. | As designed (`BackendRouter`). Unsupported calls fail asynchronously with a typed `unsupported` failure. |
| Read-only Git policy | `IndexRefreshPolicy::PrivateOnly` (new in `devmil-git`) keeps status stat-cache refreshes private; commit and comparison diffs pass `--no-textconv` (new); the helper sets `GIT_NO_LAZY_FETCH=1` and `GIT_TERMINAL_PROMPT=0` for every child. | As designed; the two shared changes were published upstream. |
| Protocol stdio isolation | The helper moves the protocol to private descriptors and points fd 0 at `/dev/null` and fd 1 at stderr before any work. | Strengthens "protocol is the only stdout writer". |
| Workspace binding | SHA-256 over the store ID and device, inode and canonical bytes of the worktree root and common Git directory. Bindings are remembered for the running app and checked on reopen. | Bindings are not persisted, so the first open after an application restart establishes a new binding instead of detecting a replaced repository. |
| Remote client cache | A bounded in-memory cache (32 MiB per connection) keeps successful content-addressed reads: commit inspection, tree pages and file content. Snapshots stay in memory only; nothing is written to disk. | Commit diffs are not cached because they set the helper's paged diff projection, so a repeated diff still costs one round trip; see the RW-07 evidence. |
| Intent digest | SHA-256 over a domain tag, the family, the binding and canonical JSON (sorted keys) of the typed request. | Deterministic encoding instead of the hand-specified binary layout. |
| Receipts and locks (RW-13/14) | Layout as specified; locks are `flock` on `locks/<common-dir-digest>.lock`; above 8 000 receipts the epoch rotates and resolved retired-epoch receipts older than 30 days are compacted. Evidence is the semantic index digest (`git ls-files --stage -z`) and HEAD identity. | As designed, with semantic evidence instead of raw index bytes. |
| Pending intents (RW-13) | `remote/pending/operations.json` beside the settings document, written atomically with file and directory sync (`rust-core/application/src/remote_pending.rs`). | As designed. |
| Feature gate | `SettingsDocument.remoteWorkspacesEnabled` (schema 13, default off). | Shipping enablement remains a per-target gate (G3/G5). |
| Helper delivery (RW-12, RW-22.A) | `scripts/package_remote_helper.py --target linux-x86_64|linux-arm64|macos-arm64|macos-x86_64` builds a reproducible archive bound to the source commit; Linux checks the glibc 2.35 floor (arm64 is cross-built on the same baseline), macOS builds for macOS 13 and signs ad hoc. Every desktop package bundles all four under `remote-helper/<platform>/`; a macOS package re-signs its macOS helpers with the Developer ID before recording their digests. The signed release manifest optionally carries one record per platform. | The release workflow builds both Linux helpers on the Ubuntu 22.04 baseline and the macOS helpers on the macOS runner; see the manual gates in the implementation plan. |
| Helper identity | Since 2026-10-10 the build ID is the helper compatibility version declared in `rust-core/remote-helper/COMPATIBILITY`, as 40 decimal digits, embedded by `rust-core/application/build.rs` in the core and the helper; `--version` and package metadata also carry the source commit. `scripts/check_helper_compatibility.py` (in `verify.sh`) fingerprints the helper sources, the application and contract crates (since 2026-10-12; before, only the wire codecs and session policy), the remote surface and contract, and records the devmil-git pin; it fails until a changed fingerprint raises the version. | Relaxes "an exact approved helper build ID for the client release": releases that keep the helper unchanged share the hosts' installed helper. A devmil-git behaviour change raises the version by developer judgment, recorded in `AGENTS.md`. Hello, launch and install formats are unchanged. |
| Helper installation | Installing stays explicit by default and is offered where a missing helper is reported: the failed tab, reconnect, recent open, the host dialog and Settings → Remote hosts. A per-host `autoInstallHelper` setting (withdrawn by an alias change or rebind) lets a connection attempt that finds the helper missing install the bundled helper of the host's platform once and retry. | Relaxes "installation is manual and explicit" for hosts the user opted in; the installation itself is unchanged and still never downloads anything. |
| Repository initialization | Since 2026-10-11 (helper compatibility 2) `initializeRepository` creates a repository in a missing or empty host directory with the core's own destination checks and `git init`, under its own capability `initialize`. The helper offers it with the other writes; the client requests it only when the user allows changes on the host, then opens the path as a remote tab. | It has no receipt, preview or lookup: the destination holds nothing to lose, the core refuses an existing repository or a non-empty directory, and an uncertain answer is resolved by asking again (which reports `existingRepository`) and opening the path. |
| Later write families | Since 2026-10-10 the helper also admits merge, cherry-pick and revert (`History`), interactive rebase, restack, bisect, conflict resolution and the sequencer (capability `history`); named snapshots, file restore, patch apply and index-lock removal (`recovery`); worktrees, submodules and LFS (`extensions`); and amend, skipped hooks, disabled signing and reset in the existing commit and refs families. Each runs the core's own preview/execute pair, or a direct call whose Execute repeats the digested request, under the same receipt, lock and evidence sequence. Undo and redo were removed on 2026-10-17. Outcomes come from the result's state and the family's evidence (PROTOCOL.md); conflicts and edit stops are `partial`; nothing is resent and a running write is not cancelled from the client. | Relaxes the R2 exclusions in VISION.md for hosts where the user allows changes. A patch travels as bytes and is kept privately on the host until applied. External merge tools, local editors, terminals, file browsers, custom commands, credential prompts and retries of uncertain writes stay local-only. Since 2026-10-13 inspection windows open for remote repositories: they read through the main window's connection (`RemoteInspectionHostService`, read allowlist only, one helper session per window). |
