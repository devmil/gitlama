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
- Meridian QML: breadcrumbs, text area, keycaps, radio; dialog title spacing as in Flutter.
- Commands: registry shortcuts bound in the window, command palette, availability state for the
  shared policy; transfers (fetch/pull/push/push tag/delete remote branch with host keys,
  credentials, failure guide, refetch offer), references (create/rename/delete/checkout
  branches, tags with remote deletion, remotes, reset, edit branch with upstream), stashes
  (create/apply/pop/drop/rename/stash-and-switch) and commit checkout with stash choices.
- Meridian list row slots (`leading`, `titleTrailing`, `trailing`, `semanticValue`).

- Settings: appearance, Git (automatic fetching with the background scheduler, per-repository
  override and reset), diff view (stored preferences drive every diff), shortcuts (Meridian
  shortcut recorder), accessibility, diagnostics (detailed capture, clear, preview, save) and
  licenses (Meridian license dialog with Qt runtime notices).

- History rewrites: merge / cherry-pick / revert (input, merge conflict prediction, preview,
  set-aside revert), branch integration, interactive rebase (target, editor with reorder by
  grip/arrows/keys, drag-to-squash, actions, reword, autosquash; preview with todo), restack
  (root, review with published acknowledgement); busy overlay with Cancel.
- Conflicts: repository conditions banner (failures, detached HEAD, conflict count, paused
  operations with Continue/Skip/Abort); the resolver (steps guide, conflicted files with ticks
  and bulk sides, details, whole-file and deletion decisions, side-by-side comparison with
  region toolbars and click-to-take, result editor with region bands at fixed 25px lines via
  the native TextFormatter, panes following each other, resolved page with merge message and
  undo, footer navigation). Merge drafts and sessions live in Rust.

- Operation center: the logbook panel (filters, timeline rows with marks, folded background
  fetches, details with output, Retry/Cancel/Dismiss/Copy/Details, Dismiss all), toolbar badge and
  Compass progress from the polled center, the activity island; Meridian floating panel.

- Clone: source dialog, destination, progress with Cancel, failure banner with credential and
  host-key retries (a new folder for a partial destination), the new tab adopted.

- Inspector lenses: Contents (line numbers, show binary as text), Blame (lazy pages, author
  bands, blame before, line history, show commit, copy hash), File/Line history (paged list,
  renames, the selected commit's change). Fixed the inspector's state binding.

- File actions: the shared catalogue (`workbench/src/file_actions.rs`, the spec §7.1 matrix with
  tests) behind a QML `FileActionMenu`; the Changes file menu (stage, discard/clean, open in
  editor, reveal, copy path, add to .gitignore with the ignore dialog, Blame/History at HEAD);
  the History commit context menu; the integration launcher (configured or discovered editor,
  terminal and file manager with each platform's arguments, confirmation of configured tools)
  for Open in editor/terminal/file manager; command details behind a disclosure as in Flutter.
  Inspector file menus: lenses of the shown or listed commit, open/reveal when the file exists in
  the working tree, external diff tool, restore this version with its size confirmation.
- Patches: the patch dialog (create: destination, preview of scope/format/name/size, overwrite,
  write, show in folder; apply: check, files, command, apply) from Create/Apply patch, the commit
  menu, the Changes and inspector file menus; remote repositories save the host's patch locally.
- Select changed lines: the line-picking dialog (hunk and line checkboxes, picked count, select
  all, load more) staging, discarding or making a patch of the chosen lines.
- Worktree deletion from the sidebar: confirmation, refusal banner under the worktrees, reload.
- Changes tree mode per list (stored List/Tree choice, Meridian path tree ported to
  `workbench/src/path_tree.rs`), folder rows with folding, folder selection and folder menus.
- Inspector file sidebar: Changed/All scope, changed files as list or tree (stored mode), the
  All files tree (folders read on demand with paging and retry, the path to the shown file
  opened, unchanged files listed only there), folder and tree-file menus.
- Diff toolbar (path, hunk navigation, wrap, whitespace, context lines, minimap, text encoding,
  layout, markers, create patch) for the inspector and the working diff; wrapped lines, the
  minimap, Latin-1 decoding and Show more lines (transient wider context) in the diff view.
- Find in diff (Meridian QML find bar, added to meridian_ui): whole-diff search in Rust, match
  position, case toggle, stepping with wrap-around, matches marked in rows and minimap.
- About, repository icon dialog (icon, colour with the Meridian colour picker, image file) and
  tab group dialog (preview, name, colour, icon); Meridian QML colour swatch, picker, well and
  choice row added to meridian_ui.
- Named snapshots panel (capture, list, inspect, restore with preview and acknowledgement,
  branch from, delete); one floating panel at a time in the shell.
- Repository details: the Compass morphs into the health header, path, branch/upstream/changes
  tiles, paused operations, activity, Git version and Open in file manager.
- Shortcut reference; save snapshot as ZIP (progress, cancel, result with missing submodules
  and LFS pointers).
- Image diffs (committed and working): both sides decoded by the core, side by side, swipe and
  onion skin over a checkerboard with sizes.
- Power tools: diff content search (scope, case, limits, reveal in History), statistics and
  bisect with a confirmed command per step; floating, or docked under History's query bar
  with a section switch. Bisect fields resolve HEAD, branch, remote-branch and tag names to
  their commits (the core takes object IDs only); commit choices with subjects and the remote
  host's history-write check wait for the history projection and remote workspaces.

- Extensions panel: worktrees (open, open in file manager, delete with their other tabs
  closed first and reopened when the deletion does not happen, create from a reference into
  a chosen folder), submodules (initialize, update, open) and Git LFS (pull, track, untrack,
  pointer details); Track LFS pattern opens it with the pattern field focused.

## Next
Dialogs and panels not ported yet (Dart files in `lib/app/workspace` unless noted):
- Integrations panel and settings page, status acceleration settings.
- History: branch filter editor, view options (other refs), search scopes, reflog, collapse,
  notices (stale upstream, filtered out, collapsed), selection glide, lane lighting/draw/landing
  motion, sync entrance, hosting chips, Gravatar.
- Hosting (pull requests, checks, links), updates (Sparkle/AppImage and its settings page),
  CLI forwarding, drag and drop, macOS window configuration.
- Remote workspaces (remote_workspace, remote_hosts_settings, remote_directory_picker,
  remote_host_dialog, remote_operations) and inspection windows (inspection_window_app).
- Inspector: search in contents/blame, +/− counts in the files header; changed-word marks on
  wrapped lines.
- Logbook: user failures recorded from workflow failures (with their support report); clone
  retry from the logbook; row entrance/exit stagger.
- Conflict resolver: wrapped comparison lines, syntax colours, external merge tools, tree mode
  of its file list, the Continue pulse, file action menus.
- Settings pages: integrations, repository binding, remote hosts, custom commands, diff
  renderer, updates; diagnostics Share on macOS/Windows.
- Changes: drag between lists, flight animation.
- Working-tree Blame/History opens an inspection window in Flutter when windows are available;
  the port shows it in the History inspector until inspection windows are ported.
- Release work: lint gate for GitLama QML, verify.sh, license generator, packaging and CI for
  every target plus Arch, docs, changelog, performance comparison, moving the checkout.

## Deferred / notes
- Found while porting (pre-existing, Flutter too): devmil-git's `parse_unified_patch` rejects
  `git format-patch` output because of its `-- ` signature trailer, so Apply refuses the email
  patches GitLama itself writes (plain unified diffs apply). Fix belongs in devmil-git (helper
  version raise).
- Transfer failure guide: lock listing and removal (repository lock inspection) not yet.
- Palette: custom integration commands, background run (Cmd+Enter), scope cycling (Tab).
- Sidebar: MeridianGlide check indicator between current branches; hosting checks/pull
  requests.
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
