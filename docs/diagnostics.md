# Application diagnostics

This application adopts the user-controlled diagnostics contract of
`devmil_logging`. Safe recent events stay in memory, with bounds of 1,000 events
and 256 KiB and a 2 KiB per-event ceiling. Detailed capture expires after fifteen
minutes or when the engine exits. Settings provides enable/disable, Clear,
preview, Save to file on desktop/web, and text Share on supported native
platforms. No application-owned temporary export files or automatic uploads are
used. Exports contain application/build and platform metadata, not stable device
identifiers. Saved or shared copies remain outside Clear history.

Product policy is in `lib/logging/diagnostic_policy.dart`: reviewed structured
events and exact static legacy messages are admitted; interpolated legacy text
and arbitrary external exception text are excluded. New events use static
`DiagnosticEvent` codes and bounded numeric fields. Secrets and private product
content are excluded even in detailed mode. Development console output requires
an explicit `DEVMIL_DIAGNOSTIC_CONSOLE=true` Dart define and a debug build.

Transfer diagnostics are emitted by the Dart session command owner for local and
remote fetch, pull and push attempts, including background fetch. The
`transfer_preview_*`, `transfer_execute_*`, `background_fetch_preview_*` and
`background_fetch_execute_*` event families record starts, results and thrown
failures. Detailed capture adds `*_timing` events with `elapsed_ms`. Numeric
`kind`, `state` and `failure` fields use the corresponding enums in
`lib/models/transfer.dart`; failure `-1` means no failure on a result or an
unclassified exception on a failed event. These events omit command arguments,
remote/branch names, paths, Git output, credentials and raw exceptions. Git
output remains in the repository's separate Activity view.

Applications with a Rust layer install its shared availability hook through their
existing FRB transport. Native history is capped at 256 events and 64 KiB;
only one notification is outstanding until Dart drains it. No raw native error
payload crosses this path. Platform frameworks and SDKs outside app-owned
logging may still have their own output; audit those separately.

Automated verification and target-platform Save/Share acceptance are separate.
Do not infer installed artifact, native bridge load, or platform share-sheet
acceptance from host unit tests. Existing automatic log files from earlier
versions are not imported or exported by the new history.

To qualify the actual host native library, build its Rust `cdylib`, set
`DEVMIL_LOGGING_NATIVE_LIBRARY` to that artifact, and run
`flutter test tool/native_diagnostic_hook_test.dart`. This checks the generated
FRB availability hook and drain/configure calls end to end. It does not replace
an installed application or platform share-sheet check.

## Adoption verification, 3 November 2026

Shared implementation pin: `e4b3ee5574235810992b4a02062bf8e5004b71e4`.
The library passes its Dart and Rust verifier, including bounded history,
privacy, consent expiry, export cancellation/failure, callback detach and pending
Clear regressions. A subsequent library commit strengthens only the teardown
mock; the application implementation pin remains immutable.

The standard `./scripts/verify.sh` passed (Flutter, Rust/Clippy, remote, package, architecture and dependency gates). Final dependency notice generation and pin checks also passed.
The final rebuilt Linux host library passed `flutter test tool/native_diagnostic_hook_test.dart`, proving a real FRB event reaches the shared history and complete stream retirement succeeds.

Platform Save/Share dialogs, installed artifact behavior, and other target hosts remain separate acceptance gates. No source session histories were required; the live checkouts were available.
