# Components

Every Meridian component has a usage guideline (below), a live specimen in [`../specimens/`](../specimens/index.html), and a reference implementation in [`reference/`](reference/). The reference is plain React plus CSS, and it drives the specimens. It is the visual and behavioural oracle for the Flutter widgets in `lib/widgets/`. It is not shipped code.

| Group | Component | Summary |
|---|---|---|
| Actions | [Button](Button.md) | A labelled command. |
| Actions | [IconButton](IconButton.md) | A single icon command for toolbars, island headers and row hover actions. |
| Actions | [ToolbarButton](ToolbarButton.md) | A Git verb in the unified title bar: an 18px icon (1.75 stroke) over a `caption` label, on `ground`. |
| Inputs | [Checkbox](Checkbox.md) | Checkbox and Switch. |
| Inputs | [Segmented](Segmented.md) | Picks one of 2–4 peer options that change a view: diff layout, list or tree, theme. |
| Inputs | [Select](Select.md) | Select, and the Menu it opens (the same component is used for context menus). |
| Inputs | [TextField](TextField.md) | Single-line input. |
| Navigation | [Compass](Compass.md) | The centre of the title bar and GitLama's signature control. |
| Navigation | [Palette](Palette.md) | The command palette, opened from the Commands button beside the Compass or with ⌘P / Ctrl P. |
| Navigation | [RepoTabs](RepoTabs.md) | One tab per open repository, on `ground` under the toolbar. |
| Navigation | [SidebarRow](SidebarRow.md) | Rows of the repository sidebar, grouped by SidebarSection. |
| Git | [Avatar](Avatar.md) | Author initials on a lane colour, picked from a stable hash of the name, so the same person keeps the same colour across repositories. |
| Git | [CommitRow](CommitRow.md) | One commit in History: Graph, refs and subject, author with Avatar, 10-character hash, relative date. |
| Git | [Composer](Composer.md) | The commit message editor, docked at the bottom of the Changes island on `pane-alt`. |
| Git | [DiffHunk](DiffHunk.md) | One hunk: a sticky header strip (range, enclosing context, actions), then line rows with old and new line numbers, a sign column and code in `code` (JetBrains Mono 12/18). |
| Git | [FileRow](FileRow.md) | A changed file in Changes (unstaged or staged) or in a commit's file list. |
| Git | [Graph](Graph.md) | The spline graph cell for one commit row. |
| Git | [RefChip](RefChip.md) | A ref label in a commit row or the detail header. |
| Git | [StatusGlyph](StatusGlyph.md) | A file's Git state as a 16px mono letter tile. |
| Git | [SyncBadge](SyncBadge.md) | Ahead/behind relative to the upstream. |
| Feedback | [Banner](Banner.md) | A persistent, inline message about the state of the repository or the island it sits in. |
| Feedback | [Kbd](Kbd.md) | Keyboard keys and the Count badge. |
| Feedback | [Logbook](Logbook.md) | The operation history, dropped from the right end of the Compass. |
| Containers | [Dialog](Dialog.md) | A modal question. |
| Containers | [Island](Island.md) | The rounded work surface. |
| Containers | [SettingsRow](SettingsRow.md) | A desktop-native settings form: the label is right-aligned in a 200px column, controls sit on the left of the next column, and help goes below in `caption` `ink-muted`. |
| Showcase | [Workspace](Workspace.md) | The whole window put together from the system: toolbar with Compass, repo tabs, sidebar on `ground`, and the History and Detail islands. |

The Flutter widget for each component and its migration status are listed in [`../FLUTTER_ADAPTATION.md`](../FLUTTER_ADAPTATION.md#component-mapping).

## Intentional additions

- **Disclosure** replaces `ExpansionTile`: a `sizeRow`-high header with a 12 px `chevron-right`/`chevron-down` in `inkMuted`, `space3` before a `label` title in `ink`, a `paneHover` hover fill with `radiusSm`, and a body indented by `space6`. It exposes its expanded state to accessibility services.
