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

- Welcome screen, entry workflows (open/initialize; clone pending), prompts (QML dialogs answer
  core workflows), notices/status messages.
- Command registry (`workbench/data/commands.json`, Rust-owned) + shortcuts catalogue, QML
  availability policy (`Commands.qml`), command menus.
- Workspace shell: toolbar + Compass (glint, rule, rolling counts), status bar, repository tabs
  with groups, rename, menus, worktree row; repository appearances (names, icons, images as
  validated PNG data URLs).
- Meridian QML additions (branch `feat/qml-gitlama` in meridian_ui): island header, section
  header, list-row match, icon aliases, nudge/spinning/badge tones, MeridianReveal,
  MeridianSwap, swap-text weight, tab strip with groups/chips/rename/grow/collapse/drag.

- Workspace body: sidebar (reference tree/filter/expansion in Rust, keyed `RowModel`, rail,
  splitter), History pane (lazy `HistoryModel` over every row, native C++ `GraphRow` painter,
  ref chips, metadata columns, search field, keyboard selection, reveal), History/detail split.
- Inspector: commit/comparison targets, summary card, changed files, diff lens (paged rows,
  idle syntax colours with contrast checks, changed-word marks, side by side), Back/Forward/Up.
- Changes: staging lists (queue, merge, phases, follow-the-move selection), filter, discard
  review, working diff with in-place reloads and line staging, commit editor (drafts per
  worktree, amend, skip hooks/sign-off, failure panel with retries, results).
- Meridian QML: breadcrumbs, text area.
- Meridian list row slots (`leading`, `titleTrailing`, `trailing`, `semanticValue`).

## Next
- Command execution (toolbar, menus, shortcuts): transfers (fetch/pull/push), ref dialogs,
  stash, checkout; operation center; command palette; settings dialog.
- Inspector lenses: contents, blame, file history, All files tree; tree mode of file lists;
  diff wrap, minimap, find, encoding, image diff, show more context.
- Changes: tree mode, drag between lists, flight animation, context menus (open, reveal,
  ignore, patch), conflict resolver flow.
- History: branch filter editor, view options (other refs), search scopes, reflog, collapse,
  notices (stale upstream, filtered out, collapsed), commit context menu, selection glide,
  lane lighting/draw/landing motion, sync entrance, hosting chips, Gravatar.
- Shortcuts bound from the registry; command palette; operation center; settings dialog.

## Deferred / notes
- Sidebar: MeridianGlide check indicator between current branches; hosting checks/pull
  requests; worktree deletion flow (`Actions.deleteWorktree` stub).
- Delegates built through `Loader` components log null reads at engine teardown only.
- Tab strip accessibility move actions (Flutter custom semantics actions) have no QML equivalent yet.
- Worktree open menu needs the extensions inventory (extensions family).
- Remote tab host marks (`hostBuilder`) wait for remote workspaces.
- View cache persistence (disposable; `NoViewCache` for now; new format allowed).
- Remote workspaces: router, SSH transport, reconnector (`WorkspaceRemotes` is a stub).
- `tooling/remote_wire/generate.py` still parses the deleted Dart bindings; rewrite it to
  Rust-only inputs with byte-identical `generated.rs`.
- Remove `flutter_rust_bridge:ignore` comments from the contract crate
  (`--record --keep-version`).
- Move the diagnostics history into devmil-logging (shared code placement).
