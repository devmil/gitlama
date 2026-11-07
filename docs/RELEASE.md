# Release preparation

GitLama has one canonical two-line `VERSION` file. Release preparation derives `pubspec.yaml`, `rust-core/Cargo.toml`, the GitLama package entry in `rust-core/Cargo.lock`, release documents, artifact names and the annotated tag from those two values.

The **Publish GitLama release** workflow (`.github/workflows/release.yml`) is started manually with exactly two choices:

- `channel`: `stable` or `beta`
- `bump`: `none`, `beta`, `patch`, `minor` or `major`

Every bump except `none` increments the global build. Stable patch, minor and major bumps produce stable SemVer. The same choices on the beta channel produce `-beta.1`; `beta` starts or increments the beta number. Stable rejects prerelease versions. Beta rejects versions that do not end in `-beta.N` or `-rc.N`.

## Flutter SDK archive

`.fvmrc` selects Flutter for both local and container builds. When changing it,
refresh `tooling/flutter-linux.sha256` from the exact stable Linux x64 entry in
[Flutter's official release manifest](https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json).
Keep the SHA-256 and archive filename together, for example
`<sha256>  flutter_linux_<version>-stable.tar.xz`.

`python3 scripts/flutter_linux_archive.py` validates the archive identity against
`.fvmrc` and prints the digest used by the release container. The qualifier runs
this before creating its stage or building the image; the image still checks
the downloaded bytes with `sha256sum -c` before extraction.

## Transaction

1. **prepare** requires a clean checkout of `main`. Before changing anything it
   decodes the release credentials from repository secrets, derives the public key from
   the protected release key and compares it with the versioned trust root
   `release/northspline-release-ed25519.pub`. A missing or mismatched credential
   therefore cannot create a release commit or tag. It then updates all canonical
   version consumers, promotes the selected pending section in both
   `CHANGELOG.md` and `RELEASE_NOTES.md` (copying the changelog items when the
   curated notes are empty; historical sections are never removed), runs the full
   source gate and pushes the preparation commit to `main`. Stable promotion
   clears both pending tracks; beta promotion leaves stable notes intact.
2. **helper** and **helper-macos** build the remote helpers from that exact commit:
   Linux x86_64 and arm64 in the Ubuntu 22.04 container, macOS arm64 and x86_64
   with the macOS SDK.
3. **macos**, **linux** and **windows** check out the same commit, bundle the
   helpers, build, sign where configured and qualify only their native packages.
4. **collect** accepts exactly the six target names, writes `release-state.json`
   with their byte counts and SHA-256 digests, verifies the diagnostics set, and
   signs the publication candidate: the signed manifest, its signature and the
   public key next to the six packages.
5. **publish** creates and pushes the annotated `vVERSION-BUILD` tag, creates a
   draft GitHub release for it, uploads every signed file, downloads each one
   again and compares exact bytes, and only then publishes the release. It then
   commits the verified signed metadata to `release/` and the website index to
   `webfront/`.
6. **website** deploys `webfront/` with GitHub Pages.

A failed target leaves the preparation commit untagged and runs no publication
job. Pushes made by the workflow token do not start other workflows, so the
release commits do not rebuild the application in CI. `scripts/ci_scope.py` reads
a pushed range: website, documentation and signed release metadata, and a
preparation whose `pubspec.yaml`, `rust-core/Cargo.toml` and `rust-core/Cargo.lock`
differ only in the version, run `scripts/verify.py --source` on one runner. Any
other path, a range without a known start, and a manual dispatch build and test
every platform.

The Linux container fetches the complete locked Rust graph before invoking
Flutter, while any shared-dependency Git rewrite is available. Native hooks
then use `CARGO_NET_OFFLINE=true` for GitLama’s prefetched workspace; hooks
intentionally filter out `GIT_CONFIG_*`. The `CARGO_GITLAMA_PREFETCHED` marker
leaves independent Cargokit plugin graphs online in their parent environment.
A cold container must not rely on another runner's Cargo cache.

macOS packaging prepares an owned source overlay for the pinned `objective_c`
9.3.0 hook to enable DWARF, verifies the original hook hash, and builds with
`--no-pub` so Flutter preserves that resolved overlay. It never edits the shared
Pub cache or relaxes required native-symbol coverage. A receipt of both hook
hashes is retained with diagnostic provenance; collection searches hook outputs
while their linked objects still exist. A dependency update requires reviewing
the hook patch again.

Windows installed-launch qualification uses `GITLAMA_PROFILE_ROOT` for each
synthetic profile and preserves the account’s `APPDATA` and `LOCALAPPDATA`,
which native Windows services and plugins may need. It prints one safe JSON record per probe
and retains `windows-launch-*.json` in the candidate artifact or, on failure,
`gitlama-windows-failed-qualification` (30 days). Records identify the cold-profile
or missing-Git probe, failed stage, elapsed time, PID, and pre-cleanup exit code
in decimal and hexadecimal. A null exit code means the probe terminated a still
running process; it is not a crash code. Output is drained concurrently with
bounded memory and reported only as byte counts and recognized static startup
failure categories, including reviewed forwarding enums and Win32 error codes.
Raw stdout/stderr, user profiles and Windows event messages
are never uploaded.

On failure, a bounded best-effort Application Error event lookup matches the
process PID and launch time and retains only the exception code, module basename
and fault offset. `queried` with no events does not rule out a crash: Windows may
write events later, or the app may have exited normally. Query failures are
reported separately without replacing the original qualification failure. The
five-second survival and 30-second settings-readiness gates remain required.

The Linux release soak remains a required 600-second gate. The Windows release
soak runs for 600 seconds as advisory evidence: its failure does not block the
remaining MSI qualification or publication. The MSI report records `soak` as
`passed`, `failed` or `not-run`, plus `soakAdvisory` and `soakExitCode`. The
separate Windows soak report retains resource samples and acceptance failures;
if the harness fails before writing one, a `soak_incomplete` report records that
no measurement was obtained. Neither an advisory failure nor missing samples
establish Windows resource acceptance. Local MSI qualification remains strict
unless `-SoakAdvisory` is supplied. Signing, installation, native launch and
uninstall checks remain required.

## Private crash diagnostics

Target jobs also collect matching native symbols, Dart maps and provenance from
the exact packaged build. Collection validates the seven archives before
publication and keeps them as a workflow artifact of the release run. They are
excluded from public release assets and the update manifest. See
[crash symbolication](CRASH_SYMBOLICATION.md) for coverage, vendor gaps,
retention and the investigation commands.

## Retry and recovery

Prefer **Re-run failed jobs** on the release run: the build, candidate and
signed-candidate artifacts of the run stay available for 90 days, so a failed
target, collection or publication resumes without rebuilding anything that
already passed. Publication is idempotent: an existing draft is completed from
the same signed bytes, and a release that already holds different bytes stops
the job.

Dispatching the workflow again with `bump=none` has two closed outcomes. An
untagged checkout whose release documents already contain the current version
resumes the interrupted preparation and rebuilds/qualifies the target packages.
An existing annotated tag switches to recovery. Recovery never runs a build or
signing job: `scripts/recover-publication.sh` downloads the signed metadata and
every file the GitHub release already holds, verifies them against the signed
manifest, publishes the release and updates the website index. A release that
lacks a signed file cannot be recovered; publish a higher build instead.
Rebuilding changed bytes under an existing tag is forbidden.

## In-app updates

[ADR 0004](adr/0004-in-app-updates.md) records the design. The release key also signs the macOS update package. `scripts/publish-candidate.sh` stores that signature in the signed index as `update_signature` and verifies it against the DMG before the candidate is retained. No additional secret is required.

The website step renders `webfront/appcast.xml` from the verified index, before it replaces the index pointer. Sparkle reads `https://devmil.de/gitlama/appcast.xml`. Linux and Windows read `https://devmil.de/gitlama/_data/releases.json` when the user checks for updates. Both are served by the GitHub Pages site of this repository.

`macos/Runner/Info.plist` pins the feed and the public key. Package qualification compares both with the versioned trust root in the mounted application. Releases published before the updater carry no update signature and stay out of the appcast; recovery of such a release publishes a feed without it.

`python3 scripts/generate-release-fixture.py` refreshes the index and appcast fixtures that the package tests and the Dart update tests share. They are signed with a key that exists only for tests.

## Local checks

`python3 scripts/release.py version` prints the canonical version. `plan` and `prepare` reject a dirty worktree; exercise them in a clean checkout:

```text
python3 scripts/release.py plan --channel beta --bump minor
python3 scripts/release.py prepare --channel beta --bump minor
./scripts/verify.sh
git commit
python3 scripts/release.py tag --channel beta
```

`python3 scripts/release-state.py candidate` closes a complete six-file directory.

## Signed metadata and immutable publication

The versioned trust root is `release/northspline-release-ed25519.pub` (the file
name predates the product name and is part of every published release). Its
private Ed25519 key is a distinct GitLama credential: locally it may be supplied
with `--key-file` or through `GITLAMA_RELEASE_PRIVATE_KEY`, either a
standard-base64 32-byte seed or PEM. CI decodes it from the
`RELEASE_SIGNING_KEY_BASE64` secret into a disposable owner-only file. Do not reuse another product's update key.

`scripts/release.py manifest` closes the exact six packages into a canonical,
bounded JSON document and retains the five newest stable and five newest beta
records. It verifies the previous document's detached signature before merging
and rejects a replayed build. `sign` signs the exact JSON bytes. `verify` works
offline with the versioned public key and can additionally verify one selected
package against its signed size and SHA-256 digest. OpenSSL 3 is required.
Package URLs point at `https://github.com/OWNER/REPOSITORY/releases/download/TAG/`.

Publication is append-only. `scripts/publish-candidate.sh` signs and verifies the
complete candidate without contacting a release host. `scripts/publish-release.py
stage` creates or resumes a draft release, uploads missing files, downloads every
file again and compares exact bytes before `publish` makes it visible. Duplicate
names, unexpected assets, changed sizes or hashes stop the transaction. Public
metadata and website pointers are updated only after that verification succeeds.

## Credentials

The release reads its signing material from repository secrets. Key files are
stored as base64 text (`base64 -w0 FILE` on Linux, `base64 -i FILE` on macOS):

| Secret | Purpose |
| --- | --- |
| `RELEASE_SIGNING_KEY_BASE64` | Ed25519 release key (PEM) that signs the manifest, the release index and macOS updates. It must match `release/northspline-release-ed25519.pub`. |
| `MACOS_DEVELOPER_ID_P12_BASE64` | Developer ID Application certificate and key (PKCS#12). |
| `MACOS_DEVELOPER_ID_P12_PASSWORD` | Password of that PKCS#12 file. |
| `MACOS_CODESIGN_IDENTITY` | Signing identity name, for example `Developer ID Application: NAME (TEAMID)`. |
| `APPLE_NOTARY_KEY_BASE64` | App Store Connect API key (`.p8`) for notarization. |
| `APPLE_NOTARY_KEY_ID`, `APPLE_NOTARY_ISSUER_ID` | ID and issuer of that API key. |

`scripts/lib/release-secrets.sh` decodes the key files into owner-only temporary
files and never prints a value. The prepare job checks that all three key files
decode and that the release key matches the versioned trust root before it
changes anything. The macOS job imports the certificate into a disposable
keychain and deletes the keychain and decoded files on every exit path. No
credential value is stored in Git.

Windows payloads and the MSI remain unsigned when both Windows signing values
are absent. Once either `WINDOWS_CERTIFICATE_THUMBPRINT` or `WINDOWS_TIMESTAMP_URL`
is configured, both are mandatory and the certificate must be in the runner's
certificate store; every executable, DLL and MSI must then sign and verify. There
is no configured-signing fallback to unsigned packages. GitHub-hosted Windows
runners have no certificate, so signing needs either a runner that holds one or
a signing service integrated into `scripts/sign-windows-candidate.ps1`.

## Windows qualification

Windows release setup first writes and deletes a new synthetic Credential
Manager entry. It does not read or replace existing credentials. A failed
capability check blocks the build and retains `windows-credential-preflight.json`
with the numeric Win32 error in the failed-qualification artifact. The check uses
the same persistence policy as IPC: machine persistence when permitted, or session
persistence when Windows advertises only that capability. Error 1312 alone does
not prove the credential store is unavailable: the requested persistence may
exceed the supported maximum. Inspect `genericMaximumPersistence` and the
selected `persistence` before attributing the failure to the logon session. Do not
bypass this gate or replace authenticated IPC with an insecure fallback.

The manual **Diagnose Windows IPC credential storage** workflow compiles and
tests the production Windows IPC/protocol modules directly through
`tests/native_windows_ipc`. It checks the supported-persistence policy and a real
Credential Manager token write/read/delete without a Flutter build. The release
runs this boundary check after Rust setup as well. The token remains inside
Windows Credential Manager; disabled credential storage still refuses startup,
and pipe ACLs, peer SID checks, replay protection and acknowledgements are
unchanged.
