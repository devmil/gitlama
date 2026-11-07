# Flutter adaptation of Meridian

## Since the move to meridian_ui

GitLama builds on the shared `meridian_ui` package. The sections below this one record how the migration was planned from the old GitLama theme; read the class names in them as history. Today:

| Concern | GitLama code |
|---|---|
| Theme | `buildAppTheme` in `lib/app/app_theme.dart` calls `buildMeridianTheme(brand: MeridianBrands.gitlama)` and adds `GitLamaGitColors` |
| Tokens | `context.meridian` (`MeridianTheme`), `context.colors`, `context.text`, `context.git`; `MeridianSpace`, `MeridianSize`, `MeridianLayout`, `MeridianDurations`; GitLama-only values in `GitLamaLayout`, `GitLamaOpacity`, `GitLamaMotion` (`lib/app/gitlama_layout.dart`) |
| Git colours | `GitLamaGitColors`, generated from `tokens/gitlama-tokens.json` into `lib/app/gitlama_tokens.g.dart`. `added` is Meridian's `success`, `modified` its `warning`, `conflict` its `attention`, `lane-N` its `series-N` |
| Icons | Meridian's Lucide 1.37.0 set; GitLama's semantic names (`fetch`, `push`, `close`) are aliases in `lib/app/gitlama_icons.dart` |
| Primitives | `Meridian…` widgets from the package (appendix D of the migration plan maps every old `GitLama…` component) |
| Menus | OS-native: both app roots install `NativeMenus.scope` (Meridian's `meridian_native_menus` companion, pinned with `meridian_ui`), which shows every Meridian menu and text field menu natively; GitLama's menus go through `lib/widgets/native_menu.dart`, the only user of the package |
| Domain components | `GitLamaCompass`, `GitLamaRepoTabs`, `GitLamaRefChip`, `GitLamaFileRow`, `GitLamaComposer`, `GitLamaTimelineRow`, `GitLamaWorkflowHeader`, `GitLamaStatusGlyph`, `GitLamaSyncBadge`, the history graph and the diff views stay in GitLama |

Status: adopted 2026-09-25. The shared controls and shell are migrated; workflow and acceptance checks remain open (see [Migration status](#migration-status)).

This contract maps Meridian onto Flutter. The token file, specs and component guidelines in this folder are the source; this file says how Flutter consumes them. Where the current code differs, the code migrates. The design does not bend back.

## Token pipeline

- [`tokens/gitlama-tokens.json`](tokens/gitlama-tokens.json) is the only token source. The Dart theme is derived from it; widgets never hard-code colours, radii or spacing.
- `GitLamaTheme` (a `ThemeExtension`) holds every colour token for the active theme as `const Color` fields, plus the lane list, shadows and density. Widgets read it through `GitLamaTheme.of(context)`. Material `ColorScheme` gets the closest subset (`primary = polar`, `onPrimary = on-polar`, `error = danger`, `surface = pane`, `onSurface = ink`), but it is never the token source.
- `AppTokens` holds the spacing, radius and size tokens as `double`s, and the motion table as `Duration`s.
- Dart names are the token names in lowerCamelCase: `pane-alt` → `paneAlt`, `on-polar-muted` → `onPolarMuted`, `lane-3` → `lanes[2]`, `space-4` → `AppTokens.space4`, `radius-lg` → `AppTokens.radiusLg`, `size-row` → `density.rowExtent`.
- `python3 scripts/check_design_contract.py --write-css` regenerates `tokens/gitlama-tokens.css`. The check fails when the CSS is stale or a contrast pair drops below its floor.

### Colour mapping from the current theme

| Current `GitLamaTheme` field | Meridian token(s) |
|---|---|
| `background` | `ground` |
| `surface` | `pane` |
| `surfaceRaised` | `raised` (floating) and `pane-alt` (inset). Split by role |
| `foreground` | `ink` |
| `muted` | `ink-muted`; disabled text moves to `ink-faint` |
| `border` | `line`; control boundaries move to `control-edge`, button outlines to `line-strong` |
| `accent` / `accentForeground` | `polar` / `on-polar`, plus new `on-polar-muted` and `polar-ink` |
| `selection` | `polar` in the focused island, `polar-soft` elsewhere |
| `hover` | `pane-hover` on islands, `ground-hover` on chrome |
| `focusRing` | `focus` |
| `danger` / `warning` | `danger` (+ `on-danger`, `danger-bg`) / `modified` (+ `modified-bg`) |
| `added` / `deleted` | `added` / `deleted` |
| `addedBackground` / `deletedBackground` | `added-bg` / `deleted-bg` |
| `addedHighlight` / `deletedHighlight` | `added-strong` / `deleted-strong` |
| `conflictCurrent` / `conflictIncoming` | `side-ours` / `side-theirs`, plus new `conflict`, `conflict-bg` |
| `lanes` (8) | `lane-1` … `lane-8` |
| — (new) | `renamed`, `tag-ink`, `tag-bg`, `scrim`, `fjord` |

### Geometry mapping

| Current `AppTokens` | Meridian |
|---|---|
| `GitLamaDensity` 22 / 24 / 28 | 24 / 28 / 32 (`size-row-compact`, `size-row`, `size-row-comfortable`) |
| `spaceXSmall` 4, `spaceSmall` 8, `spaceMedium` 12, `spaceLarge` 24 | `space-1` 2 … `space-9` 32 (see tokens) |
| `radius` 4 | `radius-xs` 3, `radius-sm` 5, `radius-md` 7, `radius-lg` 10, `radius-xl` 14, `radius-pill` |
| `controlHeight` 32, `compactControlHeight` 26, `inputHeight` 30 | `size-control` 28, `size-control-sm` 22 |
| `toolbarHeight` 52 | `size-toolbar` 52 |
| `tabStripHeight` 32 | `size-tabbar` 34 |
| `sidebarWidth` 260, `sidebarRailWidth` 72 | `size-sidebar` 248 (200–360), rail 56 |
| `iconSize` 16 | `size-icon` 16 (14 in chips and small controls, 18 in the toolbar) |
| `paneSplitterExtent` 8 | Island gutter `space-3` 6, which is also the hit target |
| `interactionDuration` 80 ms | Motion table in [`specs/interaction-accessibility.md`](specs/interaction-accessibility.md#motion) |
| — (new) | `size-lane` 14, island radius and gutter, `shadow-pane`, `shadow-float`, `shadow-control` |

### Typography

- `sans` is the platform face. Flutter uses the default system family (SF Pro on macOS, Segoe UI Variable on Windows, the fontconfig default on Linux). No UI font is bundled.
- `mono` is JetBrains Mono Regular, bundled from `assets/fonts/` (copy in [`assets/fonts/`](assets/fonts/)). Layout that depends on mono metrics waits for the font to be ready.
- `TextTheme` mapping: `displaySmall` = `display`, `titleLarge` = `title`, `titleMedium` = `subject`, `bodyMedium` = `body`, `bodyLarge` = `body-strong`, `labelLarge` = `label`, `labelSmall` = `caption`, `labelMedium` = `overline` (uppercased at the call site). `code` and `hash` are `GitLamaTheme.codeStyle` and `hashStyle`.

## Rendering and measurement

- Logical coordinates belong to Flutter layout. Device pixels matter only in golden comparison and image decoding.
- Islands are `DecoratedBox`es with `pane`, `radius-lg` and `shadow-pane`, laid out with `space-3` gaps on a `ground` `ColoredBox`. The 6 px gutters are the splitters and their hit target (drag resizes, double-click resets). Islands never nest.
- The focused island is tracked by a `FocusScope` per island. The island reads `hasFocus` to switch selection paint between `polar` and `polar-soft` and to draw its 1 px `polar-soft` halo.
- Graph rows: one fixed-extent virtualized row per commit. Rust supplies identity, lanes, shapes, segments and occupied ink. Flutter measures the pinned metadata first, then clips graph, ref and subject ink before the metadata gap. The painter draws cubic S-curves per [`specs/graph.md`](specs/graph.md) and never infers parentage from neighbouring rows.
- Diffs: bounded row pages, fixed-extent rows (18 px), unified and split. Syntax and intra-line work run off the UI isolate. Wrapping uses a bounded expanded-row model.
- Overlays (menus, Logbook, Palette, Dialogs, the drag badge) use the root overlay with a focus scope. A barrier with `scrim` is used only for modal Dialogs. Escape dismisses. Focus is restored by stable control identity, and overlays reposition at screen edges.

## Component mapping

| Meridian component | Flutter widget | Change |
|---|---|---|
| Button | `GitLamaButton` | Variants `primary`, `secondary`, `quiet`, `danger`, `dangerQuiet`; sizes `regular` / `small`; optional `Kbd` |
| IconButton | `GitLamaIconButton` | `small`, `active` toggle, `onGround` hover |
| ToolbarButton | `GitLamaToolbarButton` | Icon over caption; badge `Count`; split caret |
| TextField | `GitLamaTextField` | `control-edge`, search variant, trailing text, error message line |
| Segmented | `GitLamaSegmented` | Inset track, raised selected tile |
| Checkbox, Switch | `GitLamaCheckboxListTile` → `GitLamaCheckbox`, new `GitLamaSwitch` | Mixed state; Switch for immediate settings |
| Select, Menu | `GitLamaSelect` (new) opening `native_menu.dart` | Menus stay OS-native (`AGENTS.md`). Meridian defines the menu model: order, groups, destructive last, shortcuts. Only the Select trigger is painted |
| Compass | new `GitLamaCompass` | Replaces the centred title/branch label and the Operations chevron |
| Palette | new `GitLamaPalette` | Command palette opened from the Commands button beside the Compass |
| RepoTabs | tab strip in `workspace_shell.dart` | Pill tabs on `ground` |
| SidebarRow, SidebarSection | sidebar rows in `workspace_shell.dart` | `overline` headers, sync badges, hover `plus` |
| Island | new `GitLamaIsland`; replaces `GitLamaPaneHeader` | Rounded islands; header 36 px |
| StatusGlyph | `_ChangeStatusGlyph` → `GitLamaStatusGlyph` | Letter tile on the status tint |
| RefChip | ref pills in `history_graph_view.dart` | Tracking pairs, notched tags, solid head chip |
| Avatar | `author_avatar.dart` | Initials on a lane colour |
| Graph, CommitRow | `history_graph_view.dart` | Spline curves, Meridian node shapes, inset selection bar |
| FileRow | Changes rows in `workspace_shell.dart` | Hover actions, counts |
| DiffHunk | `diff_view.dart` | Sticky 30 px header strip, 44 px gutters, text selection with a `polar` line frame and floating selection actions |
| Composer | commit editor in `workspace_shell.dart` | Docked on `pane-alt`, 50/72 counter |
| Banner | `GitLamaBanner` | Tones `info`, `warning`, `conflict`, `error`; no border |
| Logbook | `OperationCenterPanel` (the Operations popover) | Floating 420 px surface under the Compass; timeline rows with expandable command output |
| Activity | `_ActivitySlot` | Island above the status bar; rows use the Logbook row style |
| Kbd, Count | new `GitLamaKbd`, `GitLamaCount` | — |
| Dialog | `gitlama_dialog.dart` | `raised`, `radius-xl`, `shadow-float`, `scrim` |
| SettingsRow | settings pages | Label-left grid; replaces floating-label dropdowns |

Every component exposes rest, hover, focus, pressed, disabled, loading and error states where they apply. A disabled action keeps its accessible label and exposes its reason in the tooltip and the semantics. `GitLamaInteraction` stays the single hover/press/focus layer; Material `InkWell`, splash and ripple stay banned.

## Icons

Interactive and navigational icons come only from Lucide static 1.37.0 in `assets/icons/lucide/` (mirrored in [`assets/icons/`](assets/icons/) with [`inventory.json`](assets/icons/inventory.json)). SVG license headers and the ISC/Feather notice stay with the assets. `GitLamaIcon` loads them at 14, 16 or 18 logical px with a 2 px stroke (1.75 in the toolbar). No icon fonts, Unicode action glyphs, hand-drawn substitutes or second icon family. Adding an icon means copying it from the same lucide-static version into both folders, adding it to `inventory.json`, and updating `THIRD_PARTY_NOTICES.md`, in the same commit.

## Focus, semantics and input

- Each island and chrome region is a `FocusTraversalGroup` in the F6 order from [`specs/interaction-accessibility.md`](specs/interaction-accessibility.md#island-focus-order).
- Menus, dialogs, the Palette and the Logbook capture the invoking control's stable identity and restore it on close.
- `Semantics` distinguishes selected, focused, current checkout, expanded, busy and disabled. Status never relies on colour, lane or shape alone.
- Every drag route has a menu or keyboard command. macOS uses ⌘, and Linux and Windows use Ctrl. Text editors get first refusal on editing chords, and bare-letter commands work only in documented list focus modes.
- Shortcut overrides use portable modifier names, resolve separately against the macOS and Windows/Linux defaults, and cannot shadow another effective command on either platform.

## Captures

[`specs/capture-matrix.json`](specs/capture-matrix.json) defines the five viewports, both themes, three densities and 130% text scale. Flutter goldens live under `test/goldens/meridian/`. The HTML specimens are the visual reference; Flutter captures are the acceptance artefact.

## Migration status

- [x] Meridian tokens, foundations, component guidelines, specimens, assets and specs adopted in `docs/design-system/`.
- [x] Behaviour oracles (graph topology and row layout, diff, conflict, patch scope) carried over under GitLama schemas; `rust-core` graph tests read them from `docs/design-system/specs/`.
- [x] `lib/app/app_theme.dart` regenerated from `tokens/gitlama-tokens.json` (colours, densities 24/28/32, radii, spacing, shadows).
- [x] Shared controls in `lib/widgets/` migrated per [Component mapping](#component-mapping), with a Meridian gallery in `test/support/component_gallery.dart`.
- [x] Shell recomposed as islands on `ground`, with the Compass, Logbook and Palette.
- [x] Graph painter switched to spline curves and Meridian node shapes (`rust-core` `LANE_PITCH` 16 → 14, origin 14 → 9).
- [ ] Goldens re-baselined against `capture-matrix.json`.

No design decision blocks the migration. The remaining acceptance work is the side-by-side specimen review and physical accessibility checks.
