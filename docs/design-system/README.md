# Meridian: GitLama's design system

Meridian is GitLama's design language: a dense, keyboard-first Git workspace that feels calm. The work sits on rounded **islands** on a tinted ground. The **Compass** in the title bar shows where you are and what is running. History is drawn as a **spline graph**. One accent, `polar`, is spent only on intent.

Meridian grew here and was extracted into the shared Flutter package `meridian_ui`, which GitLama now builds on (pinned by Git commit in `pubspec.yaml`). The two own different parts:

- **`meridian_ui` owns the shared system:** the core tokens (surfaces, ink, status, series, spacing, radii, type, motion), the GitLama brand (`polar` is the brand's `accent`, cerulean since Meridian 1.2.0; the name is historical), and every primitive (buttons, fields, selects, segmented controls, rows, islands, banners, dialogs, panels, menus, suggestions). Its guidelines win when they differ from the shared component pages here.
- **This folder owns what is GitLama's:** the git colour tokens (`added-strong`, `deleted*`, `renamed`, `side-*`, `tag-*`), the domain components (Compass, Palette, Graph, CommitRow, RefChip, FileRow, DiffHunk, StatusGlyph, SyncBadge, Composer, Logbook, RepoTabs, Workspace), the specs and their oracles, and the specimens.

`scripts/generate_meridian_theme.py` generates the git colour extension from `tokens/gitlama-tokens.json` and fails when a shared value in that file drifts from the pinned `meridian_ui`. Nothing else outside `meridian_ui` and this folder defines tokens, components or visual behaviour.

## Contents

| Path | What it is |
|---|---|
| [`MANIFEST.json`](MANIFEST.json) | Version, file inventory, themes, densities, viewports, oracles. Validated by `scripts/check_design_contract.py` |
| [`foundations.md`](foundations.md) | The brand book: principles, window anatomy, signature patterns, content rules, colour, type, spacing, shape, depth, motion, states, accessibility, iconography |
| [`tokens/gitlama-tokens.json`](tokens/gitlama-tokens.json) | Every token: 46 colours × 2 themes, type families and 10 styles, spacing, radii, shadows, sizes. The single token source |
| [`tokens/gitlama-tokens.css`](tokens/gitlama-tokens.css) | CSS custom properties generated from the JSON (used by the specimens) |
| [`components/`](components/README.md) | 27 component guidelines, the Workspace composition, and the React/CSS reference implementation in `components/reference/` |
| [`specimens/index.html`](specimens/index.html) | Every component rendered live, with theme and density switches. [`specimens/workspace.html`](specimens/workspace.html) shows the whole window |
| [`assets/`](assets/README.md) | The app mark, the 81 Lucide icons with their inventory, JetBrains Mono with its licence |
| [`specs/graph.md`](specs/graph.md) | History graph: geometry, spline lanes, node shapes, G-LANE-01, ref chips, pinned metadata, states |
| [`specs/changes-and-diff.md`](specs/changes-and-diff.md) | Changes island, diff rendering, staging, file rows, fallbacks, Composer |
| [`specs/workflows.md`](specs/workflows.md) | Rebase, conflict resolver, blame, stashes, review, patch, deep graph tools, Settings, Palette |
| [`specs/interaction-accessibility.md`](specs/interaction-accessibility.md) | Selection model, focused island, focus order, menus, drag and drop, screen reader, scaling, motion |
| [`specs/motion.md`](specs/motion.md) | Motion: GitLama's highlights (NH-1 to NH-7) and git micro-animations (NM-xx) on top of the Meridian motion guide. [`specimens/motion-lab.html`](specimens/motion-lab.html) runs them |
| `specs/*.json` | Oracles: graph topology and row layout, diff, conflict, patch scopes, capture matrix |
| [`FLUTTER_ADAPTATION.md`](FLUTTER_ADAPTATION.md) | How Flutter consumes all of this, the mapping from the current theme, and migration status |

## Authority

1. The token JSON wins over any prose value.
2. `specs/*.md` and the JSON oracles define behaviour and geometry. The oracles are acceptance tests (`rust-core` reads the graph oracles).
3. `foundations.md` and `components/*.md` define usage.
4. The specimens and reference implementation illustrate 1–3. When they disagree with 1–3, the specimen is wrong.
5. `lib/` follows this folder. Where `lib/` still differs, that is migration work listed in `FLUTTER_ADAPTATION.md`.

## Working with it

- View: open `specimens/index.html` in a browser. It needs no build step or network.
- Change a token: edit `tokens/gitlama-tokens.json`, run `python3 scripts/check_design_contract.py --write-css`, then update `app_theme.dart`. The check enforces the contrast floors listed in the manifest.
- Change a component: update its `components/<Name>.md`, the reference in `components/reference/`, and its specimen together. Then bump `MANIFEST.json` `version`.
- Add an icon: see [`assets/README.md`](assets/README.md).
