# Port status

Updated as slices land. "Donor" is the Flutter source at 7b78369e
(`/home/mlamers/dev/claude-worktrees/gitlama-donor` locally).

## Done
- Foundation: crates (`desktop/workbench`, `desktop/qt`, `desktop/app`), qtbridge pump,
  embedded QML, Meridian vendored, l10n generator (ICU plurals/selects), git colour tokens,
  startup screen, Linux caption chrome, screenshot hook (`GITLAMA_SCREENSHOT`).
- Workbench runtime (`rt`): local executor, blocking pool, timers.
- Settings service (same native store and path), diagnostics history; the main window keeps its frame (size, position where the platform allows it, maximized) in `appearance.window*` as Flutter did.
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
- Settings › Tools and commands (Custom commands): tools found on this computer, configured
  tools (run after a command preview, delete), and the add form validated by the core before
  it is stored; Add integration opens it with the name field focused.
- Status acceleration: the slow-status offer (once per session after a slow first scan,
  enable or dismiss) under the repository conditions, and Settings › Git › Faster change
  checks (untracked cache, file system monitor, last scan, turn on).
- History query bar: branch filter editor popover (tree of local and remote branches, search,
  toggle, focus, current branch, show all), view options (other refs, reloading History),
  find bar with search scopes, match position and stepping, apply filter, collapse merge,
  reflog view; History notices (pending search, failure, empty filter, target outside the
  ref scope, filtered-out selection, accepted filter, collapsed count) and the new upstream
  commits banner.
- Inspector: the contents lens header (path, size) with find (case, stepping, marked lines),
  and the +/− counts of the whole change in the files header.
- Diff renderer: Settings › Diff renderer (validated by the core, confirmed with its commands,
  stored, deleted) and Render diff in the inspector (preview with limits and exact commands,
  progress, fallback banner, plain-text output with Use built-in; Render with configured
  renderer command).
- Conflict resolver: external merge tools (one configured tool runs directly, several offer a
  native menu; exact command confirmed; the file counts as merged externally).
- Conflict resolver: list/tree file list (tree from the shared path tree, foldable folders),
  file action menus (context menu and the row's More button: copy path, open, reveal, blame,
  file history); the Continue pulse (MeridianPulse, added to meridian_ui) after the last
  conflict is resolved.
- CLI forwarding: `gitlama <path>`, `--open`, `--command repository.refresh|fetch|pull` are
  handed to the running window (exit 0) or refused with the localized message (exit 2); the
  window owns the instance, polls forwarded commands, raises itself, opens, refreshes, and
  starts fetch or pull with the requested strategy. Remote opens answer "precondition" until
  remote workspaces are ported. `scripts/run-dev.sh` gives each profile its own instance.
- Repository drops: folders dropped on the window open as repositories (others are
  rejected), with the drop prompt over the window while dragging and the summary after.
- Updates: Settings › Updates (installed version, release channel, check); Linux and Windows
  check the public release index over HTTPS with curl (bounded, no redirect) and offer the
  downloads page — checked live on Linux. macOS drives Sparkle through
  `desktop/app/src/native/sparkle_bridge.m`, which loads Sparkle.framework from the bundle at
  run time; it is NOT compiled or tested yet (no macOS here) and packaging must ship
  Sparkle.framework with `SUPublicEDKey`. The Updates category always shows (Flutter hid it
  where unsupported; only development builds are affected).
- Hosting (part 1): accounts and repository binding in Rust (`workbench/src/hosting.rs`:
  stored accounts validated at start, save/remove with credential cleanup, sign-in through
  OAuth or the GitHub/GitLab CLI followed every half second, binding override or automatic
  resolution, paged resources, batched branch pull-request lookups with pending/moved
  rechecks, head checks, linked pull requests); Settings › Hosting accounts (cards with
  enabled/background refresh, reauthorize, remove; add form with preset defaults, CLI
  detection, setup guide; sign-in progress with the device code) and Repository link. Not
  signed in against a real provider here. The persistent link cache is not ported (links are
  looked up again each run).
- Hosting (part 2): the Integrations panel (provider resources: refresh, Create pull request,
  filter, remembered groups, check out, open, load more; Review opens the page in the browser
  until the review workspace is ported), the Show integrations and Create pull request
  commands, the sidebar's pull request rows (yours first, merged, checks and conflicts,
  open/check out), and pull request chips after History's branch chips (at the head, or
  outdated on the remote-tracking chip with a recheck). Rendered without a provider only.
- Gravatar author images: loaded once per hash while enabled (data URLs), cache cleared when
  turned off; an avatar explains and offers Gravatar while it is off. Not loaded against
  Gravatar here.

- Release gate (2026-11-23): `scripts/verify.py` runs the Rust/QML lanes; qmllint with no
  warnings; architecture, dependency, Meridian usage, design contract, command inventory and
  localization checks rewritten for Rust/QML; license notices follow the shipped programs.
- Parity sweep driven by `docs/qml-port/l10n-pending.txt` (every Flutter message the port does
  not use yet): diff hunk actions, pinned hunk headers, copy lines/patch, binary details and
  Show as text; commit options dialog (co-authors, author, signing, fixup/squash, recent);
  repository lock list and Inspect index lock; Find, Report issue; history empty/retry states
  and row accessibility; Changes row hover actions, partial marker, pending spinner, drag by
  grip between lists, Clear queue; repository chooser tabs; stash file picker; blame ages;
  reference fields (normalize, segment suggestions, choices, picker); Edit branch as Flutter;
  Refresh with spin and failure; worktree open menu; grouped Compass titles. Meridian gained
  MeridianTextMenu (native Cut/Copy/Paste/Select All in every text control).

- Remote workspaces (2026-11-23): profiles, hosts dialog and editor, remote folder picker,
  helper installation (bundled, development builds via `scripts/build_dev_helpers.py`),
  reconnect, per-host access, stale-tab banner and failure page, remote recents and
  initialization, inspection windows over the main connection. Verified against the real
  helper locally and over a loopback OpenSSH fixture (`verify_remote_workspaces.py
  --ssh-loopback`, now Rust tests); not against a real remote host.
- Persistence parity: the view cache (new schema, disposable) and the hosting link cache (the
  format earlier releases wrote) are stored again; recovery was inert in Flutter too and is
  not wired.
- Platform hooks: macOS unified toolbar, reduce motion, open-document events (`open -a`,
  Dock drops, Open With) and the diagnostics share sheet; Windows reduce motion and Share UI.
  Not run on macOS or Windows here (no hosts in this environment).
- Motion: History lane lighting flow, lane drawing (first load, new working-tree row,
  transfer arrivals), commit landing and row slide, commit flash and search attention, sync
  rows entering; Compass glint again (sync tracker); island entrance on first open; rolling
  sync, dirty and conflict counts; Logbook entry entrance, failure shake and mark swap;
  command palette rows; description growth; commit failure reveal; diff layout crossfade.
  Meridian QML gained MeridianEntrance, MeridianMotionMemory, MeridianAttention,
  MeridianShake, MeridianRollingNumber and MeridianResize.
- Command palette: custom integration commands, as Flutter listed them.
- No Flutter build input, generated bridge or Dart reference is left (`check_dependencies.py`
  guards it); docs describe the Rust and Qt Quick application (ADR 0006).

## Performance against the Flutter build (2026-11-23)
Same Linux host (Omarchy, Hyprland, Wayland, Mesa), fresh profiles, the port's optimized
build against the installed Flutter release 0.1.0-beta.67 (build 68), opening the same
845-commit repository; process RSS and CPU time 22 s after launch, three runs each:

| | Flutter | Rust + Qt Quick |
| --- | --- | --- |
| CPU time to settle (repository) | 1.47-1.79 s | 1.71-1.77 s |
| Idle rendering | none | none |
| RSS, welcome screen | 157 MB | 207 MB |
| RSS, repository open | 207-209 MB | 322-323 MB |

Found and fixed on the way: a hidden drop zone kept an infinite animation (and 60 frames
a second) running; every dialog was built at startup (now created on first use: -184 MB,
-1.3 s); the QML is compiled to bytecode at build time (qmlcachegen, -0.2 s). The remaining
memory difference is the QML object tree of the open workspace. Not measured: macOS,
Windows, large repositories (100k commits), frame timing while scrolling.

## Remaining parity gaps
Known differences from the Flutter build, none of them data or workflow loss:
- Motion: Flutter's motion is ported, including the Changes stage flight, leaving and arriving
  rows, long-press drag with lift, the History selection glide and ref chip pop/leave, the
  Logbook's leaving rows, the rebase lift and strokes, sidebar section reveal and the palette
  growing out of the toolbar button (NH-6). Differences: the selection bar does not follow the
  slide of rows when a commit is inserted above it, and a sidebar toggle animates every row
  change for `motion-layout` + `motion-exit` + `motion-select` after the click.
- Conflict resolver: comparison lines wrap with the shared diff choice and both sides, the
  ancestor and the result are syntax-coloured (`text_syntax_page`, a native QSyntaxHighlighter
  for the editors). Wrapped row heights are computed from the code font's average advance, so
  lines with tabs or wide characters can be a line off.
- Tab strip accessibility move actions (Flutter custom semantics actions) have no QML
  equivalent.
- Memory: about 115 MB more resident memory than the Flutter build with a repository open
  (see Performance).
- Not verified here: macOS and Windows builds, packages and native hooks (including the
  qmlcachegen step there); signing; screen readers; physical displays at fractional scales;
  a real SSH host.

## Deferred / notes
- Found while porting (pre-existing, Flutter too): devmil-git's `parse_unified_patch` rejects
  `git format-patch` output because of its `-- ` signature trailer, so Apply refuses the email
  patches GitLama itself writes (plain unified diffs apply). Fix belongs in devmil-git (helper
  version raise).
- Move the diagnostics history into devmil-logging (shared code placement).
