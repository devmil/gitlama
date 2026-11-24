# Application diagnostics

This application adopts the user-controlled diagnostics contract of
`devmil_logging`. Safe recent events stay in memory, with bounds of 1,000 events
and 256 KiB and a 2 KiB per-event ceiling. Detailed capture expires after fifteen
minutes or when GitLama exits. Settings provides enable/disable, Clear,
preview, Save to file, and text Share on macOS and Windows.
No application-owned temporary export files or automatic uploads are
used. Exports contain application/build and platform metadata, not stable device
identifiers. Saved or shared copies remain outside Clear history.

The history is `rust-core/desktop/workbench/src/diagnostics.rs`: events carry a reviewed
static code, a component and public or numeric fields, and every line passes redaction
(paths, URLs, e-mail addresses and secret assignments are replaced) before it is kept.
Secrets and private product content are excluded even in detailed mode, which additionally
admits `Fine` events and expires on its own. New events use static codes and bounded numeric
fields; arbitrary external error text is never recorded.

Transfer diagnostics are emitted by the transfer workflows (`transfers.rs`) for local and
remote fetch, pull and push attempts, including background fetch. The
`transfer_preview_*`, `transfer_execute_*`, `background_fetch_preview_*` and
`background_fetch_execute_*` event families record starts, results and failures. Numeric
`kind`, `state` and `failure` fields use the contract's transfer enums; failure `-1` means no
failure on a result or an unclassified failure. These events omit command arguments,
remote and branch names, paths, Git output, credentials and raw errors. Git output remains in
the repository's separate Activity view.

Native events recorded through `devmil-logging` in the core (`gitlama_core::api::
drain_native_diagnostics`) are drained into the same history whenever it is read; the native
buffer is capped at 256 events and 64 KiB. Detailed mode and Clear are forwarded to it. Qt and
platform frameworks outside app-owned logging may still write their own output; audit those
separately.

Workspace, History, Inspector, Diff and Sidebar diagnostics record repository open starts,
completions and failures (including native discovery, creation and load stage failures),
snapshot and watch failures, and History/diff failures at `INFO`/`WARNING`. When detailed
capture is enabled, `FINE` events additionally record elapsed timings and item counts for
repository open/close stages, snapshot updates, History preview and completion, commit
inspection, commit and working diff loads, diff/syntax pages and sidebar inventory reloads.

Settings → Diagnostics shows the controls. Preview renders the export (application, version
and platform, then the events); Save writes it to the file chosen in the platform dialog, and
on macOS and Windows Share offers the text to the platform's share sheet without writing a
file. Existing automatic log files from earlier versions are not imported or exported.

Automated verification and target-platform Save and Share acceptance are separate: do not
infer installed-artifact or share-sheet acceptance from host unit tests.
