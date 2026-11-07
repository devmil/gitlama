# Interaction and accessibility contract

Status: normative. Meridian 3.0.

## Identity and selection

Rust owns `current`, the persistent selected set, range anchors, comparison order and the focused island. A row widget receives those values and paints them. It never stores them.

| Input | Result |
| --- | --- |
| Click | Make the item current and replace the selection. |
| ⌘-click / Ctrl-click | Toggle the item and make it current. |
| ⇧-click | Select the rendered range from the Rust-owned anchor. |
| ↑ / ↓ | Move current one visible item and replace the selection unless a modifier extends it. |
| Home / End | Move to the first or last visible item. |
| PageUp / PageDown | Move by `floor(viewportHeight / rowHeight) - 1`. |
| ⌘A / Ctrl A | Select the visible filtered set. |
| ↵ | Open or run the default action for current. |
| Space | Toggle current in the selection (in file lists: stage or unstage). |
| Menu key / ⇧F10 | Open the context menu at current. |

Two selected commits create an ordered comparison: the first selected is old, the second is new. Deselecting either returns to single-commit detail.

History rows use the integrated layout in [`graph.md`](graph.md). Graph clipping never changes a row's selection identity, accessible subject or metadata. Activating a branch or tag in the sidebar selects and explicitly reveals its commit, including a repeated activation. Older pending navigation never overrides newer input.

## The focused island

Meridian's rule: **only one island owns the keyboard at a time, and you can see which one.**

- The focused island gets a 1 px `polar-soft` halo. Its selected rows are solid `polar` with `on-polar` text, and secondary text uses `on-polar-muted`.
- In every other island, selected rows are `polar-soft` with `ink` text.
- The keyboard-current row inside the focused island, when it differs from the selection, gets a 1 px `focus` inset outline on its `radius-sm` bar.
- Hover is `pane-hover` (on islands) or `ground-hover` (on the sidebar, toolbar and tabs). Hover never implies selection.
- Disabled controls use `ink-faint` labels, keep their accessible label, and show their reason in the tooltip and the semantics description.

## Island focus order

F6 / ⇧F6 cycle through regions. ⌘1–⌘4 / Ctrl 1–4 jump to Sidebar, first island, second island and Composer. Tab moves between controls inside a region. The order stays stable when islands are rearranged.

| Composition | F6 order |
| --- | --- |
| History | toolbar and Compass, repo tabs, sidebar, History, Detail files, Detail diff, status bar |
| Changes | toolbar and Compass, repo tabs, sidebar, Unstaged, Staged, diff, Composer, status bar |
| Rebase | workflow header, instruction list, footer actions |
| Conflict | workflow header, conflicted files, Current, Incoming, Result, region actions |
| Blame / path history | workflow header, source or history list, detail strip |
| Review | workflow header, changed files, diff, comments, review actions |
| Settings | page list, fields |

Opening a menu, popover, Logbook, Palette or Dialog records the stable identity of the control that opened it. Closing restores focus there if it still exists, otherwise to the nearest enabled control in the same region. Refresh, filtering, insertion, removal and model reset follow the same rule.

## Segmented controls

Use `Segmented` for 2–4 mutually exclusive view or setting choices. Segment positions and widths stay fixed as the selection changes. Icon-only segments carry accessible names and tooltips. Theme and density are always text segments. Tab enters the selected segment. ← / → move through enabled segments and wrap. Home / End select the first or last. ↵ and Space activate through the same command path as a click.

## Sidebar section actions

Sections with a creation flow (Branches, Remotes, Tags, Stashes, Worktrees) show an `IconButton size="sm"` `plus` at the right edge of the `overline` header. It appears on hover, focus or keyboard focus on that section. It replaces the section count while shown, and nothing else moves. Insert on the current section opens the same flow.

## Compass, Logbook and operations

- The Compass is one focusable target. ↵, Space, click and ⌘K / Ctrl K all open the Palette. ⌘L / Ctrl L opens the Logbook.
- Operations never open or close UI on their own. Starting work shows the Compass progress rule. Foreground work that lasts more than 300 ms may open the Logbook popover without moving focus. Background work never opens it.
- The Logbook has three `Segmented` filters, All / Mine / Background (Mine is the default), and the choice persists. Each entry expands to show the exact command, timing, status, and redacted, bounded stdout and stderr in selectable text. Failures stay until dismissed.

## Menus and tooltips

- Menu rows are `size-row` high. Order: leading icon or check, label, flexible gap, hint, shortcut (`Kbd`), submenu chevron. The keyboard-highlighted row is solid `polar`.
- Destructive items go last, after a separator, in `danger`.
- A menu whose items act on different things names them: a group title for the selection ("3 selected commits") with its items first, then a title for the item under the pointer ("Commit 4f8c1a2b9e") with its items. A menu for one item has no titles. Titles cannot be chosen.
- Context and action menu items carry the icon of their command. The operating system draws the icon in its own menu text colour. Pickers of values (context lines, encodings) have no icons.
- Icon-only controls show a tooltip after 500 ms: "Action · ⌘K". A tooltip is never the only place a disabled reason appears.

## Drag and drop

Dragging starts after 6 logical px. The drag badge (`raised`, `radius-md`, `shadow-float`) names the operation and target: "Stage 3 files → Index", "Push 2 commits → origin/main", "Squash 4f8c into a91d". Modifier changes update the badge before the drop. Invalid targets turn the badge `danger`, keep the reason visible, and reject the drop without changing anything.

Every drag has a keyboard route. Files use Space and the Stage/Unstage actions. Rebase rows use ⌘↑↓ / Ctrl ↑↓. Branch and commit operations are in the context menu and the Palette. Repository tabs move with ⌘⇧← / → (Ctrl ⇧← / → elsewhere), and the moved tab keeps focus.

## Screen reader contract

- Icon-only controls expose the action and shortcut as their name.
- The Compass announces "GitLama, branch windows-soak-cleanup, 3 ahead, 6 behind, 3 changed files. Open command palette."
- Graph rows announce refs, subject, author, date, hash, selection position and collapsed count. Lane position is announced as "branch line N". Decorative lanes and ring shapes are hidden.
- Diff rows announce old line, new line, kind (added, removed, context), staged state, selection state and text.
- File rows announce the status word, path, staged or partial state, binary or submodule kind, and any disabled reason.
- Banners use alert semantics only when attention is required (tone `error` or `conflict`). Progress uses status semantics.
- Tabs, menus, lists, trees, dialogs, text fields and progress use their matching Flutter `Semantics` roles.

## Colour and scaling

- Every text pair in `tokens/gitlama-tokens.json` meets WCAG AA (4.5:1) in both themes. Control edges, the focus ring, icons and lanes meet 3:1. `scripts/check_design_contract.py` enforces the named pairs.
- Added and removed lines always carry + / −. File status always carries a letter. Sync state always carries ↑ / ↓. Lane identity is backed by position and ref labels, never by hue alone.
- Text scale supports 100, 110, 120 and 130%. Breakpoints use logical width after scaling. At 130%, headers and banners may wrap, but actions stay fully labelled and reachable.
- Hairlines align to device pixels.

## Motion

Motion explains a change the person caused or needs to notice, and is gone before anyone waits for it. It never blocks input or delays focus, and every animation retargets when the next input arrives. Under Reduce Motion, movement becomes an instant state or a crossfade of at most 100 ms, and loops stop (the Compass indeterminate rule becomes a static 30% bar). Focus is preserved, and no motion is replaced by flashing colour.

The full contract (tokens, the highlights NH-1 to NH-7 and the micro-animations NM-01 to NM-82) is in [motion.md](motion.md). The shared rows (MM-xx) come from the Meridian motion guide in `meridian_ui`.

## Acceptance

1. Keyboard tests start from a named stable control and assert the final stable identity.
2. Semantics tests assert role, name, description, enabled, selected and value for each component family.
3. Captures include hover, selection in the focused island, selection in an unfocused island, current-with-focus, disabled, error and conflict states in both themes.
4. There is a 130% text-scale capture for the shell, the conflict resolver, Settings and the Palette.
5. Reduced-motion captures contain no intermediate animation state or delayed content.
