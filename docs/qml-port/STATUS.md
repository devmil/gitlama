# Port status

Updated as slices land. "Donor" is the Flutter source at 7b78369e
(`/home/mlamers/dev/claude-worktrees/gitlama-donor` locally).

## Done
- Foundation: crates (`desktop/workbench`, `desktop/qt`, `desktop/app`), qtbridge pump,
  embedded QML, Meridian vendored, l10n generator (ICU plurals/selects), git colour tokens,
  startup screen, Linux caption chrome, screenshot hook (`GITLAMA_SCREENSHOT`).
- Workbench runtime (`rt`): local executor, blocking pool, timers.
- Settings service (same native store and path), diagnostics history.
- Session call seam generated from api.rs + helper dispatcher
  (`tooling/remote_wire/generate_calls.py`): local + remote routing.
- Session model, history service, workspace service (tabs, groups, worktrees, drain,
  persistence) ported.

## Next
- RepositorySessionService composition, entry workflows (open/clone/initialize), welcome
  screen, workspace shell.

## Deferred / notes
- View cache persistence (disposable; `NoViewCache` for now; new format allowed).
- Remote workspaces: router, SSH transport, reconnector (`WorkspaceRemotes` is a stub).
- `tooling/remote_wire/generate.py` still parses the deleted Dart bindings; rewrite it to
  Rust-only inputs with byte-identical `generated.rs`.
- Remove `flutter_rust_bridge:ignore` comments from the contract crate
  (`--record --keep-version`).
- Move the diagnostics history into devmil-logging (shared code placement).
