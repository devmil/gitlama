# Inspector specification

Status: normative. It replaces the "Blame and path history" section of [`workflows.md`](workflows.md) and the "History Detail" bullet of [`changes-and-diff.md`](changes-and-diff.md) §8.
Requirements: FIL-01, FIL-02, GRF-03, DIF-01, UX-03.

## 1. Why this exists

GitLama used to show a commit, a commit's tree, a file's blame and a file's history through four unrelated surfaces. Two were in the Detail island, and the tree and blame windows were built by separate code. Each surface had its own header, back/forward stack, row styles and file actions, or none at all. The result:

- Some files had Blame in their menu, and some had no menu at all.
- Path history replaced the header, which hid back/forward, and offered a "Close" that discarded navigation.
- Going back did not restore the commit that had been shown.

This spec defines **one inspector**. It has one location model, one navigation stack, one file list and one action catalogue. The same widget runs in two **hosts**: the Detail island of the repository window, and an inspector window.

## 2. Vocabulary

| Term | Meaning |
|---|---|
| **Inspector** | The surface that shows a commit or comparison and the files in it. |
| **Host** | Where an inspector lives: the **pane** (the History Detail island) or a **window** (a separate OS window with its own read-only session). |
| **Location** | An immutable value naming what the inspector shows: target, scope, focus path, lens, optional line range, selected history entry and scroll anchor. Back and Forward move between locations. |
| **Target** | The commit (`CommitTarget`) or ordered pair of commits (`ComparisonTarget`, base → commit) being inspected. A stash is a `CommitTarget`. |
| **Scope** | Which files the sidebar lists: **Changed** (the target's changes) or **All files** (the complete tree at the target). Comparisons only have Changed. |
| **Focus** | The selected file or folder path. No focus means "All changes". |
| **Lens** | How the focused file is shown: **Diff**, **Contents**, **Blame** or **History**. |
| **Location bar** | The strip at the top of every inspector. It holds Back, Forward, the breadcrumb, the lens switch and the host actions. |
| **Sidebar** | The file list at the left of the inspector body. In the History lens, the file's history list replaces it. |

## 3. Anatomy

### 3.1 Pane host (wide, ≥ 560 px island width)

```
┌ Location bar (islandHeader height, pane-alt) ───────────────────────────────────────────────┐
│ ‹  ›  │ ◉ 434cdea0 Move Meridian to 1.1.1 › lib › app › pubspec.lock │ Diff│Contents│Blame│History │ ⧉ ⤢ ⋯ │
├─────────────────────────────────────────────────────────────────────────────────────────────┤
│ Commit summary card (only when lens = Diff or there is no focus; MeridianDisclosure)          │
├──────────────── Sidebar (180–480 px, resizable) ─┬──────────── Content ──────────────────────┤
│ [Changed 2 │ All files]            [≡ │ ⌗]       │ lens toolbar (Diff: existing diff toolbar) │
│ ▸ All changes                                   │                                            │
│ M pubspec.lock                              ⋯   │                                            │
│ M pubspec.yaml                              ⋯   │                                            │
└─────────────────────────────────────────────────┴────────────────────────────────────────────┘
```

- **‹ ›** Back and Forward are `MeridianIconButton`s with the icons `back` and `forward`. They are **always present** in every lens, scope and host. Nothing replaces them.
- **Breadcrumb** (`MeridianBreadcrumbs`, added to `meridian_ui` in IN01):
  - **Target crumb.** For a commit it shows the `git-commit-horizontal` icon, the 8-character hash in `code-sm` and the subject in `body`, ellipsized first. For a comparison it shows `base → commit` as two hashes.
    - Activating it navigates to the target with no focus (All changes), keeping the scope.
    - Its context menu holds Copy Commit Hash, Show in Graph (pane: reveals the commit in the graph; window: Show in Main Window) and Open in New Window.
  - **Directory crumbs** are the focused path's folders. Activating one reveals that folder in the sidebar: it switches to All files if the folder is not in the Changed tree, expands the folder and scrolls it into view. This is **not** a navigation and adds no history entry.
  - **File crumb.** The last segment, shown in `body-strong`. It is not interactive, apart from its context menu, which is the file's action menu (§7).
- **Lens switch.** A `MeridianSegmented<InspectorLens>` (size small) with icons `file-diff`, `file-text`, `blame` and `history` plus labels.
  - Below 760 px width it shows icons only, with tooltips.
  - It is hidden when there is no focus.
  - A lens the focus cannot use is disabled, and its tooltip gives the reason (§4.3).
- **⧉ Open in New Window** (`app-window`, a Lucide icon added to Meridian in IN01) opens the current location in a new inspector window. The pane stays where it is.
- **⤢ Maximize** (`maximize-2` / `minimize-2`, pane host only) hides the History graph island so the inspector fills the workspace column. Pressing it again, or running the toggle command, restores the layout. Maximize is session state and is not persisted.
- **⋯** is the overflow `NativeMenuButton`. It always holds:
  - Browse All Files (switches the scope)
  - Show/Hide Files (sidebar)
  - Copy Commit Hash
  - the focused file's action menu (§7), under a header naming the file.
- **Commit summary card.** Beside the full hash, `archive` (Save Snapshot as ZIP…, pane host only) asks where to save a zip of every file and folder of the commit, the same command as the History row menu's. The zip holds one top folder named after the repository and the short hash; submodules are included at their recorded commits and Git LFS files with their content when available. Export rules in `.gitattributes` do not apply. A progress dialog counts files and can cancel; a repository on another computer builds the zip on its host.
- **Show/Hide Files** (`panel-left`) is in the ⋯ menu and the `inspectorToggleFiles` command. When the file list is hidden, a Show Files button appears at the start of the content. The sidebar header keeps its room for the scope and list/tree switches, which stay visible down to the default 280 px width.

### 3.2 Narrow pane (< 560 px)

The sidebar and content stack vertically. The sidebar takes 40 % of the height, at least 4 rows. The content takes the rest. The location bar keeps Back, Forward and the lens switch (icons only). The breadcrumb middle-ellipsizes its directory crumbs into one `…` crumb, whose activation opens a native menu of the hidden folders.

### 3.3 Window host

A window has the same location bar and body as the pane, with these differences:

- No Maximize, because the window is already dedicated.
- **Show in Main Window** (`locate`) reveals the target commit in the main window's graph and brings that window forward. If the repository is no longer open there, the action is disabled and its tooltip says "Repository is not open in GitLama".
- There is no Close button. The window closes through the OS title bar or ⌘W / Ctrl+W.
- The window title is `<repository name> — <location label>` (§5.4).
- Default size 1200 × 760; minimum 760 × 480 (unchanged).

## 4. Locations

### 4.1 Model

`InspectorLocation` holds:

| Field | Type | Notes |
|---|---|---|
| `target` | `CommitTarget(commit)` \| `ComparisonTarget(base, commit)` | Full 40- or 64-hex object ids. |
| `scope` | `changed` \| `all` | `all` is invalid for a comparison and becomes `changed` on construction. |
| `path` | bytes or null | The focused path. Null means All changes. |
| `directory` | bool | True when `path` names a folder. Only the History lens can show a folder (folder history). |
| `lens` | `diff` \| `contents` \| `blame` \| `history` | Ignored while `path` is null. |
| `lines` | `(first, last)` or null | Only with the History lens: restricts history to the line range (formerly "range history"). |
| `historyCommit` | object id or null | The selected entry in the History lens. |
| `anchor` | int ≥ 0 | The first visible row of the content: diff row, blame line, contents line or history row. It is restored on Back and Forward. |

Two locations are **equal** when every field except `anchor` is equal. Navigating to a location equal to the current one does nothing.

### 4.2 What each lens shows

| Lens | Content | Toolbar |
|---|---|---|
| *(no focus)* | The diff of every changed file of the target, as today, including the "too large" fallback to one file at a time. | The existing diff toolbar, without "Show all changed files". |
| Diff | The focused file's diff in the target. For a comparison, it is the file's diff between base and commit. | The existing diff toolbar, without "Show all changed files". |
| Contents | The file's bytes at the target commit (the comparison's `commit`), through `CommitFileContentView`. | Path, size, and a Find field that highlights matching lines and steps through them with Enter / ⇧Enter. |
| Blame | `BlameCodeView` at the target commit. Clicking an attribution band blames the line before that change; the row menu is §7.2. | — |
| History | Master-detail (§4.4). | Line-range chip when `lines` is set. |

### 4.3 Lens availability and fallback

| Focus | Diff | Contents | Blame | History |
|---|---|---|---|---|
| File changed in target (M, R, C, T, A) | ✓ | ✓ | ✓ | ✓ |
| File deleted in target (D) | ✓ | ✗ "Deleted in this commit" | ✗ "Deleted in this commit" | ✓ |
| File unchanged (All files scope) | ✗ "Not changed in this commit" | ✓ | ✓ | ✓ |
| Binary or image file | ✓ (image diff / binary fallback) | ✓ (binary fallback panel) | ✗ "Blame needs a text file" | ✓ |
| Submodule entry | ✓ (commit bump) | ✗ "Submodules have no contents here" | ✗ same | ✓ |
| Symlink | ✓ | ✓ (shows the link target) | ✗ "Blame needs a text file" | ✓ |
| Folder | ✗ | ✗ | ✗ | ✓ (folder history) |

**Sticky lens.** When the focus changes through the sidebar or a breadcrumb, the inspector keeps the current lens if the new focus can use it. Otherwise it falls back in this order:

1. Diff
2. Contents
3. History

Example: walking through files with Blame selected blames each file, and an unchanged file in All files opens in Contents if Diff was selected.

Binary detection for Blame: a file is binary when the change kind is `binary` or `image`, or, for unchanged files, when native reports a binary failure. In that case the Blame lens shows the reason inline and offers Contents.

### 4.4 History lens (master-detail)

```
┌ Location bar …  lens = History ──────────────────────────────────────────────────────────────┐
├ [Lines 12–30 ×]  (only with a line range) ──────────────────────────────────────────────────┤
├──────── History list (sidebar slot) ─────┬──────── Entry detail ─────────────────────────────┤
│ ◷ Move Meridian to 1.1.1      434cdea0   │ Move Meridian to 1.1.1                            │
│   Michael Lamers · Oct 5                 │ Michael Lamers · Mon, Oct 5 · 9:13 PM  434cdea0   │
│ ◷ Migrate unreleased Nibluma… f48d4264   │ [Show Commit] [Blame at This Commit] [Contents]  │
│   Michael Lamers · Oct 4 · renamed from …│ ───────────────────────────────────────────────── │
│ …                                        │ diff of this file in that commit (DiffView)       │
│ Load older history                       │                                                   │
└──────────────────────────────────────────┴───────────────────────────────────────────────────┘
```

- The list replaces the sidebar in the same slot, with the same width and splitter. Each row shows:
  - the `history` icon
  - the subject (`body`)
  - `author · date`, plus `· renamed from <old>` when the entry carries `oldPath` (`caption`, `ink-muted`)
  - the 8-character hash (`code-sm`, `ink-muted`)
- Rows use `MeridianListRow` at the density row extent with two lines. They are virtualized with a fixed extent, and a "Load older history" tail row appears while `nextOffset` exists.
- When a later page fails, the loaded rows stay and the tail row becomes "Retry".
- The first row is selected when the lens opens. Selecting a row **replaces** `historyCommit` and does not push.
- The entry detail shows that commit's subject, author, date and hash, three buttons, and that file's diff in that commit (compared with the commit's first parent; renamed entries use `oldPath` → `path`). The buttons:
  - **Show Commit** pushes `CommitTarget(entry.commit)`, focus `entry.path`, lens Diff.
  - **Blame at This Commit** pushes the same target with lens Blame.
  - **Contents** pushes the same target with lens Contents.
- A folder's history shows the entry's changed files under that folder as a compact list, not a diff. Each file has the full file action menu.
- With a **line range** (`lines`), the list uses `rangeHistory` and the chip reads "Lines 12–30". Its × replaces the location with `lines = null`. Range results have no `oldPath` and no paging.
- On an empty history the detail area says "No commits changed this path."

### 4.5 Changed and All files

- The scope switch is the existing `MeridianSegmented` in the sidebar header, labelled **Changed** (with the count) and **All files**. Comparisons disable All files with the tooltip "Not available for comparisons".
- **All files** is a lazily loaded tree of `commitTree` pages, one directory at a time.
  - Expanding a folder loads its page. A folder with `nextOffset` shows a "Load more" child row.
  - Files changed in the target keep their status glyph. Unchanged files show an empty glyph slot, so names align.
- The list/tree toggle applies only to Changed. All files is always a tree, so the toggle is hidden there.
- Esc in the sidebar while the scope is All files switches back to Changed (existing spec rule).
- "Browse tree" and "Close tree" no longer exist. The scope switch and the ⋯ menu's Browse All Files replace them.

## 5. Navigation

### 5.1 Push and replace

| Event | Effect |
|---|---|
| Graph selection of one commit, or of two commits for a comparison (pane only) | **push** the target with no focus and scope Changed. |
| Click, Enter or double-click on a sidebar file | **push** focus with the sticky lens. |
| Arrow keys moving the sidebar selection | **replace** focus with the sticky lens (keyboard browsing must not flood history). |
| Lens switch | **push**. |
| Scope switch | **push**, keeping the focus if it still exists in the new scope. |
| Show Commit, Blame at This Commit, Contents (history detail), blame row "Show Commit", "Blame Before This Change", "Line History" | **push**. |
| Selecting a history entry; Load more; expanding a folder; scrolling | **replace** (`historyCommit`, loaded pages and `anchor` only). |
| Up (Esc) | **push** the parent location (§5.3). |
| Breadcrumb target crumb | **push** with no focus. |
| Back, Forward or a Back/Forward history-menu entry | Move the index. Do not change the stack. |

The stack holds at most 100 locations; the oldest is dropped. Pushing truncates the forward entries, as a browser does.

### 5.2 Back and Forward input

- Buttons in the location bar.
- Commands `inspectorBack` / `inspectorForward`: ⌘[ / ⌘] on macOS, Alt+← / Alt+→ on Linux and Windows. They are editable in Settings → Shortcuts.
- The mouse back and forward buttons (`kBackMouseButton`, `kForwardMouseButton`) anywhere over the inspector.
- Right-clicking either button, or pressing and holding it for 500 ms, opens a native menu of up to 15 entries in that direction. Each entry is labelled with its location label (§5.4), and choosing one jumps there.

### 5.3 Up (Esc)

When focus is inside the inspector and not in a text field, Esc moves one level up:

1. History lens with `lines` set → the same location without `lines`.
2. A focus with a lens other than Diff → lens Diff if available. Otherwise no focus.
3. A focus with lens Diff → no focus.
4. No focus and scope All files → scope Changed.
5. Otherwise nothing; Esc propagates.

After Up, keyboard focus moves to the sidebar row of the path that was focused, when visible.

### 5.4 Location label

`<hash8>` for a target without focus, `<hash8> · <file name>` with focus, and `<hash8> · <file name> · <Lens>` for lenses other than Diff. A comparison uses `<base8>→<commit8>`. The same label is used in:

- Back/Forward menus
- window titles
- the polite live-region announcement after each navigation ("Showing Blame of pubspec.lock at 434cdea0")

### 5.5 Pane and graph synchronisation (pane host only)

- A graph selection pushes a location as in §5.1. If the inspector already shows that target with no focus, nothing happens.
- When Back, Forward, Show Commit or a crumb lands on a target different from the graph's selection, the inspector asks the graph to select and reveal that commit (or both commits of a comparison). That selection does **not** push again.
- A graph reload that keeps the selected commit keeps the inspector location. A reload that drops it clears the stack (today's `_resetInspection` rule).

## 6. Where inspection opens

**Setting:** Settings → Appearance → "Open file inspection in": **Detail pane** (default) or **New window**. It is persisted in appearance settings.

1. The setting applies to these commands, from any menu, command or shortcut: Blame, Contents, File History, Folder History and Line History.
2. Holding ⌘ (macOS) or Ctrl (Linux, Windows) while activating any of those commands, a history row, a blame row's Show Commit, or a sidebar file **inverts** the setting for that one activation.
3. Every file action menu also has an explicit **Open in New Window** item.
4. **Where no inspector is visible**, inspection always opens a window. This covers the Changes pane, the conflict resolver and pull-request review. Their target is the current `HEAD` commit, or the review's head commit when it exists locally. When `HEAD` is unborn, the actions are disabled with the reason "No commit yet".
5. The lens switch, the scope switch and the sidebar always act in their own host.

## 7. File actions

All file menus come from **one catalogue** (`FileActionCatalog`). The `⋯` button and the right-click menu of a row show the same items in the same order, and the focused file's actions in the location bar overflow show them too. Hosts that cannot perform an action omit it. They never show it disabled without a reason.

Groups, in order, separated by separators:

| # | Group | Action | Icon |
|---|---|---|---|
| 1 | Selection header | "N selected files" + selection actions (Changes only, as today) | — |
| 2 | Inspect | Show Diff | `file-diff` |
| | | Show Contents | `file-text` |
| | | Blame | `blame` |
| | | File History / Folder History | `history` |
| | | Open in New Window | `app-window` |
| 3 | Stage (Changes) | Stage / Unstage, Inspect Changes… (partial staging) | `plus` / `minus`, `inspect` |
| 4 | Export | Create Patch… | `file-diff` |
| | | Open in External Diff Tool (when a diff tool is configured) | `external-link` |
| 5 | Working copy | Open (default app) | `external-link` |
| | | Reveal in Finder / Explorer / File Manager | `folder-open` |
| | | Copy Path | `copy` |
| 6 | Ignore (Changes) | Add to .gitignore… | `eye-off` |
| 7 | Destructive | Discard / Clean (Changes) | `trash` |
| | | Restore File from This Commit… | `archive-restore` |

### 7.1 Matrix

✓ shown; ○ shown only when the condition in the note holds; blank means not shown.

| Action | Changed file (commit) | Changed file (comparison) | Unchanged file (All files) | Folder (All files / Changed tree) | History entry file (§4.4 folder list) | Changes: unstaged file | Changes: staged file | Changes: folder | Conflict file | Review file |
|---|---|---|---|---|---|---|---|---|---|---|
| Show Diff | ✓ | ✓ | | | ✓ | | | | | |
| Show Contents | ○¹ | ○¹ | ✓ | | ○¹ | | | | | |
| Blame | ○² | ○² | ○² | | ○² | ✓ HEAD | ✓ HEAD | | ✓ HEAD | ○³ |
| File / Folder History | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ HEAD | ✓ HEAD | ✓ HEAD | ✓ HEAD | ○³ |
| Open in New Window | ✓ | ✓ | ✓ | ✓ | ✓ | | | | | |
| Stage / Unstage | | | | | | ✓ | ✓ | ✓ | | |
| Inspect Changes… | | | | | | ✓ | ✓ | | | |
| Create Patch… | ✓ | ✓ | | ✓⁴ | | ✓ | ✓ | ✓ | | |
| External Diff Tool | ○⁵ | ○⁵ | | | ○⁵ | | | | | |
| Open | ○⁶ | ○⁶ | ○⁶ | | ○⁶ | ✓ | ✓ | | ✓ | ○⁶ |
| Reveal in file manager | ○⁶ | ○⁶ | ○⁶ | ○⁶ | ○⁶ | ✓ | ✓ | ✓ | ✓ | ○⁶ |
| Copy Path | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Add to .gitignore… | | | | | | ✓⁸ | | ✓⁸ | | |
| Discard / Clean | | | | | | ✓ | | ✓ | | |
| Restore File from This Commit… | ✓ | | ✓ | | ✓ | | | | | |

Notes:

1. Not when deleted in the target.
2. Not for deleted, binary, image, submodule or symlink entries.
3. Not offered yet: GitLama cannot tell cheaply whether the review's head commit exists locally. Review files offer Copy Path.
4. Changed tree folders only: a patch of the folder's changed files.
5. Only when an external diff tool is configured.
6. Only for a repository on this computer. A file missing from the working tree is reported by the editor or file manager integration's usual failure notice.
7. Inspector windows have no repository workspace of their own: they offer the inspection actions, Open in New Window and Copy Path, but not Open, Reveal, External Diff, Create Patch or Restore.
8. Unstaged side only. The dialog prefills the top-level `.gitignore` entry that matches exactly this file or folder (from devmil-git `ignore::exact_pattern`) and adds the edited entry to the worktree's top-level `.gitignore`. A tracked file is noted: the entry hides it only once it is untracked. On a repository on another computer it needs the host's extension writes, and is listed disabled with the reason otherwise.

### 7.2 Blame row menu

The menu lists:

- Show Commit
- Blame Before This Change
- Line History (the History lens with `lines` = the row's span)
- Copy Commit Hash
- Open in New Window, which opens the Blame location of that commit

Show Commit and Line History honour §6.

## 8. File rows and lists

- Every file row in the product is a `GitLamaFileRow`: commit files, All files tree, Changes, conflict list, review list and the history detail folder list.
- Folder rows use one shared `GitFolderRow`: disclosure chevron, folder icon and name, with the same indentation (`MeridianLayout.treeIndent`) and the same selection fill as file rows.
- Every file list is built from the shared list foundation (`GitFileList`, plan IN03). It provides:
  - a header with the title, `MeridianCount`, the optional scope switch, the list/tree toggle and optional extra actions
  - list and tree flattening through `MeridianPathTree`
  - fixed-extent virtualization
  - keyboard movement: ↑/↓, ←/→ collapse/expand, Enter activates, the context-menu key or ⇧F10 opens the menu
  - the "⋯" trailing button, revealed on hover or focus, which opens the same menu as right-click
- The list/tree mode is persisted for each list kind: Changes unstaged, Changes staged, and commit Changed files. A new appearance field is added for commit files.
- Changes keeps its multi-selection, drag-to-stage, filter and staging motion. It uses the foundation's header, flattening, rows and catalogue, not its scaffold.

## 9. States

| State | Presentation |
|---|---|
| Loading target | Location bar fully interactive. Body shows `CenteredState(progress)` with "Loading 434cdea0…". Back and Forward still work and cancel the load. |
| Loading lens content | The sidebar stays. The content shows a `MeridianProgressBar` above a spinner until the lens content arrives. |
| Failure | Inline `MeridianBanner(error)` in the content with a stable failure message and **Retry**. Never raw exception text. |
| Missing object | "This commit is not available in the repository." Back stays enabled. |
| Too large | Existing "Too large" behaviour for All changes. For Contents, the existing `CommitFileContentView` bounded fallback. |
| Repository closed (window) | Banner "The repository was closed." Everything except Back, Forward and Close is disabled. |

## 10. Accessibility and focus

- The location bar is a `Semantics(container: true, label: "Inspector location")` with traversal order:
  1. Back
  2. Forward
  3. breadcrumbs
  4. lens switch
  5. host actions
- Each navigation announces its location label through a polite live region. Lens changes and history-entry selection do not steal focus.
- Every icon-only control has an accessible name and tooltip from the ARB catalogs.
- Back and Forward keep focus on the invoking button.

## 11. Motion

- Lens and location changes switch the content in place, without a crossfade. A crossfade would keep the leaving diff pane alive beside the arriving one, and both would claim the diff pane `GlobalKey` (plan §1.4).
- The location bar and sidebar update in place.
- Maximize is immediate. The graph stays mounted (off stage, at its full size), so its scroll position and selection survive.
