# QML adaptation of Meridian

GitLama's interface is Qt Quick. It builds on Meridian's QML module, which is
vendored from `meridian_ui` into `qml/Meridian` by `scripts/sync-meridian.sh`
at an exact commit (`qml/Meridian/MERIDIAN_REVISION` records it and a content
hash; `scripts/check_dependencies.py` rejects a drifted copy). The token file,
specs and component guidelines in this folder are the source; this file says
how the QML consumes them. No design decision blocks the port: where the code
differs from the design, the code changes.

| Concern | GitLama code |
|---|---|
| Theme | Meridian's `Theme` singleton with the GitLama brand; `Main.qml` binds its light, dark or system mode and its density to the appearance settings |
| Tokens | `Theme.colors`, `Theme.space`, `Theme.radius`, `Theme.size`, `Theme.type` and `Motion` from Meridian; GitLama-only geometry in `qml/GitLama/GitLamaLayout.qml` |
| Git colours | `GitColors`, generated from `tokens/gitlama-tokens.json` into `qml/GitLama/GitColors.qml` by `scripts/generate_meridian_theme.py`. `added` is Meridian's `success`, `modified` its `warning`, `conflict` its `attention`, `lane-N` its `series-N` |
| Icons | Meridian's Lucide 1.37.0 set (`IconData`); GitLama's semantic names (`fetch`, `push`, `close`) are aliases in `qml/GitLama/GitLamaIcons.qml`, installed as `Theme.iconAliases` |
| Primitives | `Meridian…` components from the vendored module; a generic control GitLama lacks is added to `meridian_ui` first |
| Dialogs | Every application dialog is a `MeridianDialog` (or `MeridianSettingsDialog`); one scrim when a dialog opens another |
| Menus | OS-native: context and action menus are `CommandMenu` models shown by the native menu presenter; Meridian's selects and menu buttons reach it through the same presenter |
| Domain components | `Compass`, `RepositoryTabs`, `RefChip`, `FileRow`, `CommitEditor`, `TimelineRow`, `WorkflowHeader`, `StatusGlyph`, `SyncBadge`, the history graph (the native `GraphRow` scene-graph item from `GitLamaNative`) and the diff views stay in GitLama |

## Rules the checks enforce

- `scripts/check_meridian_usage.py`: no Qt Quick Controls element besides the
  attached scroll bars (filled with `MeridianScrollBar`) and listed Templates
  bases; no colour literal outside `GitColors`; no literal geometry outside
  `GitLamaLayout`; no local copy of a Meridian component.
- `scripts/check_architecture.py`: QML imports only Qt modules, Meridian and
  GitLama; menus only through `CommandMenu`.
- `scripts/check_design_contract.py`: this folder's inventory, tokens,
  contrast floors, oracles, icon aliases and the QML contracts above.
- `scripts/verify.py`: `qmllint` with no warnings over every GitLama file.

## Token names

QML names are the token names in lowerCamelCase: `pane-alt` → `paneAlt`,
`on-polar-muted` → `onPolarMuted`, `lane-3` → `Theme.colors.series3`,
`space-4` → `Theme.space.s4`, `radius-lg` → `Theme.radius.lg`.
`python3 scripts/check_design_contract.py --write-css` regenerates
`tokens/gitlama-tokens.css` for the specimens.
