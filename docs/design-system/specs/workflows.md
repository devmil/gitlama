# Workflow specification

Status: normative. Meridian 3.0.
Companions: [`../tokens/gitlama-tokens.json`](../tokens/gitlama-tokens.json), [`interaction-accessibility.md`](interaction-accessibility.md), [`conflict-fixtures.json`](conflict-fixtures.json), [`patch-scopes.json`](patch-scopes.json).

## Scope

This file covers workflows that leave the normal History or Changes arrangement. They stay inside the repository window: the toolbar with the Compass, the repo tabs, the Logbook and the status bar remain available. A workflow replaces the islands to the right of the sidebar with its own islands.

Every workflow uses Rust-owned stable identities and typed commands. Flutter renders the current projection, restores focus by stable identity, and keeps no durable row state.

## Shared composition

- **Workflow header:** a 44 px strip on `ground` above the workflow islands. It holds the workflow title in `body-strong`, context chips (`RefChip`s for the branches involved), a bounded status ("3 of 7"), the primary `Button`, and "Exit" (quiet). The header is not an island.
- Minimum widths: center workspace 320 px, lists 180 px, editable code panes 220 px.
- Below 1100 logical px, secondary islands stack vertically and secondary actions move into a labelled overflow `IconButton` (`more`).
- A paused merge, rebase, cherry-pick or revert shows a persistent `Banner` (tone `conflict`) at the top of the first island, and the Compass shows the conflict count. Inline validation sits beside the control that caused it. A failed command also appears in the Logbook.
- Destructive actions name the affected ref, file or snapshot, and say what is lost, before they are confirmed. GitLama has no repository undo ([ADR 0005](../../adr/0005-no-repository-undo.md)): no review promises that an action can be taken back.

**Discard and Clean are irreversible.** Their `Dialog`s say so and name the exact file scope ("Discard 4 files", "Clean 12 untracked files"). They never promise a hidden snapshot. Clean is a labelled toolbar action (`brush-cleaning`), available from Changes and History and in the compact overflow.

**Operations:** foreground progress may open the Logbook after 300 ms without moving focus. Background work never opens it. Each Logbook entry offers "Output": the command, timing, status, a truncation indicator, and bounded, redacted stdout and stderr.

**Index lock:** lock-related failures offer "Remove index.lock…" behind a `danger` `Dialog`. The dialog distinguishes the lock from the index, asks the user to stop other Git processes, and explains the corruption risk. Nothing retries automatically. Rust refuses the removal if the lock changed since inspection or the repository has active work.

## Interactive rebase and autosquash

One island holds a virtualized instruction list. Rows are `size-row` for the current density. Row anatomy: drag handle (`grip-vertical`), action `Select` (Pick, Reword, Edit, Squash, Fixup, Drop), `hash`, subject, `RefChip`s or a "published" badge, a replacement-message field when needed, and a row menu. The action select is reachable without entering drag mode. A Drop row renders its subject struck through in `ink-faint`. Squash and Fixup rows are indented 14 px and show a lane-coloured curve joining them to their target.

The header shows "Rebase onto `origin/main`", the instruction count, the published count and the autosquash status. The footer shows the key legend (`Kbd`), the published-history confirmation `Checkbox`, and the primary "Start rebase".

| State | Presentation |
| --- | --- |
| loading | Three skeleton rows and Cancel. Rows never appear half-populated. |
| ready | Ordered rows; Start rebase is enabled when the plan validates. |
| reordered | The moved row keeps focus; 120 ms position transition. |
| autosquash preview | Fixup and squash rows show their resolved target. Unresolved targets use `modified-bg` and block Start. |
| replacement required | A Reword row opens an inline field. An empty replacement blocks Start and announces the error. |
| published rewrite | Published badges use `modified`. Start requires the confirmation checkbox. |
| running | Applied rows are read-only. The current row is the `polar` selection. Progress runs on the Compass rule. |
| conflict | The current row offers "Open conflict resolver". Continue stays disabled until every conflict is resolved. |
| failed | Inline `Banner` (error) with Details and Retry; raw output in the Logbook. |
| complete | Returns to History with the rewritten commits selected by stable identity. |

Keys: ↑↓ move current; ⌘↑↓ / Ctrl ↑↓ reorder; `p r e s f d` set the action when focus is in the list; ↵ edits the row; Esc leaves edit mode before it exits the workflow.

## Conflict resolver

The left island is the resizable conflicted-file list (220 px default, 180 px minimum) with the shared list/tree switch. Its splitter supports drag, keyboard adjustment and reset. It keeps file selection by identity while changing the view. It uses `StatusGlyph` U and an unresolved-count `Count` (tone `conflict`). The right island is the resolver. Text conflicts use three panes: **Current** (rail and label in `side-ours`), **Incoming** (`side-theirs`) and editable **Result**. Below 840 px of editor width, Current and Incoming share a horizontal split above Result. Short result panes use labelled icon actions to keep the result visible at large text sizes. Result always gets at least 40% of the height. Unresolved regions in Result sit on `conflict-bg` with a `conflict` rail.

A text file opens with its first conflict two rows below the top of the comparison. The comparison and Result scroll together: the start and end of every conflict sit on one line across both panes, unchanged text moves at the same pace, and a conflict whose result is shorter or longer than its sources absorbs the difference at no more than twelve times the other pane's pace. Result lines are as tall as comparison rows (25 px). Region toolbars are 42 px, or 58 px with the label above the actions below 800 px. Previous and Next start from the place shown and continue in the neighbouring file.

A marker-free comparison says Current / Incoming instead of Conflict 1 and omits the 0/0 region counter. It compares the actual side bytes, including an absent side as no content; it must never repeat the working result in both source columns. A summary distinguishes all seven unmerged presence combinations and separates identical bytes, changed content, line endings, final newline, UTF-8 BOM and whitespace-only differences. Unavailable preview bytes are not evidence of equality. Differences in recorded file modes/types are explicit, including executable files and symbolic links. Entry details show ancestor/current/incoming and the saved working entry with modes, sizes and available line-ending/BOM facts. A clean text result still needs explicit resolution while Git lists the path as unmerged. Presence stages cannot establish rename provenance; related paths require review.

Each region has Previous, Next, Take current, Take incoming and Take both. Take both writes current then incoming, with no separator. Hand edits are first-class. Continue is enabled only when every conflicted path is marker-free and marked resolved.

Current, Incoming, the ancestor and Result show syntax colours as diffs do: plain text first, colours once the user pauses, foreground only, and `ink` wherever a colour would read below 4.5:1 on a side's or a conflict's fill. The desktop parses these texts itself, for local and remote repositories alike: the conflict snapshot already holds them, and Result's own text changes with every edit. Unchanged lines keep their colours through an edit until the edited text has its own.

File-level conflicts show two selectable cards, Current and Incoming. Each card shows its branch `RefChip`, file status, and the last path-changing commit when Rust can verify it against the index stage (subject, author, date, `hash`). Unknown provenance says "Unknown" rather than showing an unrelated commit. Resolve requires a selected card and stages that complete version, including deletion, executable mode and symlinks. An absent side is distinct from an empty file. Resolution advances the queue and cancels pending result writes, so a deletion cannot recreate the file.

Required states are encoded in [`conflict-fixtures.json`](conflict-fixtures.json): merge markers, diff3 ancestor, multiple regions, hand-edited clean, empty result, add/add, delete/modify, binary, and huge-file external-tool fallback. Binary and huge files never create a text editor.

The header names the operation and progress ("Rebase paused at 3 of 7"). Continue, Skip (when supported), Abort and "Open external tool" stay visible. Abort uses a `danger` `Dialog` that names the recovery route.

## Blame and path history

Blame, file and folder history, file contents and the complete tree at a commit are lenses of the History inspector. The [inspector spec](inspector.md) defines them, their navigation and the windows that show them.

## Stashes

A creation panel on `pane-alt` sits above a virtualized stash list. The panel holds the name, `Checkbox` Include untracked, `Checkbox` Keep index, and "Stash changes". A warning checkbox is required before any action may replace the index or working tree.

Rows show the name, creation time, base `RefChip`, and staged / unstaged / untracked counts. Actions: Inspect, Apply, Pop, Create branch, Drop. Pop and Drop require confirmation. While a restore runs, its row stays visible and competing mutations are disabled.

States: empty, loading, ready, stashing, apply preview, apply conflict (opens the conflict resolver without dropping the stash), failed, paginated.

## Pull-request review

A 220 px changed-file island, the virtualized review diff, and a 280 px comment island on wide windows. Below 1280 px the comment island becomes a right-hand drawer (`raised`, `shadow-float`). Draft text persists per pull request.

Inline comments bind to stable diff anchors. Outdated anchors stay visible with an "Outdated" `Count` and a Re-anchor action. The footer has Comment, Approve and Request changes. Submitting opens a preview `Dialog` showing the repository, pull request, action and full body. Submit stays disabled until explicit authorization reaches the command boundary.

States: loading, no changes, ready, draft saved, comment pending, outdated comment, pagination, permission failure, offline, submission preview, submitting, submitted, failed with safe retry.

## Patch dialog

Create patch is a form-width (560 px) `Dialog`, no taller than Meridian's dialog height limit. It shows the inferred scope, format, destination, filename preview and overwrite state. The scope comes only from [`patch-scopes.json`](patch-scopes.json); the UI never infers it.

Every diff toolbar has Create patch, pinned at its end. It exports what the diff shows: the commit or comparison, limited to the open file, or the staged or unstaged changes of the open file.

States: ready, no valid scope (with the reason from `disabled`), choosing destination, overwrite confirmation, writing, complete (exact path plus "Show in folder"), failed. A failed write leaves no empty file.

Apply patch previews the target repository, affected paths, the `git apply --check` result and binary involvement. Apply stays disabled until the check passes.

## Deep graph tools

Diff-content search is a docked panel at the top of the History island: query, case, scope, a 10 000-commit bound, Search, Cancel, and an explanation when results are incomplete. Results select graph rows by stable identity without replacing the graph model.

Visual bisect is a panel with known-good and known-bad commit pickers, a command preview in `hash` style, and Start. While running it shows the current commit, tested count, remaining estimate, and Good / Bad / Skip / Reset. Every mutation first shows the exact redacted command. Reset is available after restart when Git reports an active bisect.

## Settings

Settings is a sheet (`raised`, `radius-xl`, `shadow-float`, 760 px) with a 190 px page list on the left and `SettingsRow` groups on the right. Pages: Appearance, Git, Accounts, Tools and commands, Diff, Shortcuts, Accessibility, Licenses. Below 900 px the page list becomes a `Select`.

Reversible visual preferences apply immediately. External tools, custom commands and diff renderers need "Validate and save". Shell-mode commands get a `Banner` (warning) and a separate run confirmation. "Reset repository settings" names the repository and restores focus to the control that started it.

States: loading, ready, dirty, validating, validation error, saved, integration unavailable, permission required, reset confirmation.

## Palette and shortcut reference

The Palette (`Palette` component) is 560–640 px wide, capped at 70% of the window height, and opens from the Compass. The query stays pinned above a virtualized result list. Rows show icon, label with the matched characters underlined, a hint, and the shortcut. Groups: Commands, Repositories, Branches, Files, Settings. An empty query shows recent commands; no match names the query. Tab cycles the scope, and ⌘↵ runs a command in the background.

The shortcut reference is a 760 px sheet with search and context groups. It shows effective bindings, conflicts and the winning command. Shortcuts can be rebound in Settings → Shortcuts through validated, persistent overrides. Malformed, duplicate, conflicting and OS-reserved chords are rejected. An empty binding unbinds, and valid changes apply live.

## Acceptance

1. Every state listed here has a deterministic capture in [`capture-matrix.json`](capture-matrix.json) or a fixture in its oracle file.
2. Every visible action has a pointer route, keyboard route, accessible name, enabled rule and typed command.
3. The 900 × 600 composition keeps the primary action, Exit, the Compass and the current item visible without horizontal scrolling.
4. Lists and diffs stay virtualized.
5. Closing a workflow restores the previous islands, the stable selection and the scroll anchor.
