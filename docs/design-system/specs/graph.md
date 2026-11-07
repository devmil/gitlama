# History graph specification

Status: normative. Meridian 3.0, graph layout revision 2026-09-25.
Topology oracle: [`graph-fixtures.json`](graph-fixtures.json) (G-LANE-01). Row layout oracle: [`graph-row-layout-fixtures.json`](graph-row-layout-fixtures.json). Visual reference: the `Graph` and `CommitRow` components and [`../specimens/workspace.html`](../specimens/workspace.html).

## 1. Scope

The History island renders commit topology as spline lanes, one fixed-extent row per commit, virtualized to 100 000+ rows. Rust owns topology, lane assignment, ancestry lighting, selection identity and row geometry. Flutter paints the supplied projection and sends typed input. Graph, ref chips and subject share the left region of a row. Author, short hash and relative date form a group pinned to the right edge. Those fields line up across rows, but they are not configurable table columns.

## 2. Geometry

| Value | Meridian | Token |
|---|---|---|
| Row height | 24 / 28 / 32 px (compact / regular / comfortable) | `size-row-compact`, `size-row`, `size-row-comfortable` |
| Lane pitch | 14 px | `size-lane` |
| Lane origin X | 9 px from the selection bar's left edge | — |
| Lane stroke | 2 px; 2.5 px on the lit ancestry path | — |
| Commit ring | r 4.5, 2 px stroke | — |
| Unlit opacity | 0.3 (lanes and nodes); 0.5 (row text) | `GitLamaOpacity.unlit`, `unlitText` |
| Gap after occupied graph ink | 8 px | `space-4` |
| Gap before metadata / between metadata fields | 12 / 12 px | `space-5` |
| Metadata right inset | 12 px, inside scrollbar clearance | `space-5` |
| Node hit target | 14 px wide × row height | — |
| Selection bar | inset `space-2` from the island edge, `radius-sm` | — |

Lane colour is `lane-(laneIndex % 8 + 1)`. Lane 0 is always HEAD's first-parent spine, so your own line of work is always `lane-1` (blue). The lane count may go above 8; the colours then wrap. There is no global minimum or maximum graph width. Metadata space is reserved first. Dense topology clips at the metadata gap, including a node that falls beyond it. Clipping changes what is visible, never lane identity or topology.

For each row, Rust computes the rightmost occupied graph ink across the row's full height. That includes nodes, HEAD rings, collapsed nodes, crossing curves and incoming segments whose source is above the viewport. It includes lit stroke width, so hovering or selecting never shifts the text. The row's content starts at `ceil(rightmostInk + 8)`. An empty graph band uses the lane origin. Ref chips come before the subject in the remaining space.

All coordinates are logical pixels in the row's own coordinate system. Paint, semantics and hit testing use the same Rust-authored clip rectangle. A clipped graph can never intercept a metadata action.

## 3. Lanes and curves

- A lane that changes column does so along a cubic S-curve. The control points are `(fromX, midY)` and `(toX, midY)`, so the curve leaves and lands vertically. Never draw straight diagonals or right-angle elbows. This curve is GitLama's signature.
- A side branch joining the HEAD spine stays in its own column through intervening rows and curves into the spine on its actual parent row. Its lane remains reserved until that row, including when other branches appear between the child and parent.
- Segment kinds (see the fixtures): `straight` (same lane), `join` (child lane → parent lane), `merge` (the extra parent pulled into its lane on the merge row), `octopus` (merge edge to lane ≥ 2), `boundary`, `missing`, `collapsed-merge`.
- Edges never re-route around each other. Crossings are allowed; fixture `crossing-merge` proves the rule.
- Paint order: straight segments first, then curves. The younger commit's curve paints above the older edge it crosses.
- An edge takes the child commit's lane colour. A merge edge keeps the merge commit's lane colour.
- **Lane focus:** hovering a node for 400 ms, or selecting a commit, lights that commit's ancestry path at 2.5 px and full opacity. All other edges and nodes drop to 0.3, and the text of rows off the path (ref chips, subject, author, hash, date) drops to 0.5, which keeps it readable while the lit path stands out. Rust computes the ancestor set; Flutter never infers it.
- On a `focused` row (solid `polar` bar), every stroke and ring on that row paints in `on-polar`.

## 4. Node shapes

| Shape | Trigger | Rendering |
|---|---|---|
| `commit` | 1 parent or root | Hollow ring r 4.5 in the lane colour, filled with the row background |
| `head` | The commit HEAD points at | Filled dot r 4 in the lane colour, a 2 px row-background gap, then a 1.5 px ring at r 7 |
| `merge` | More than 1 parent | Ring r 4.5 with a centre dot r 1.75 |
| `wip` | Working-tree pseudo-commit | Dashed ring (2.2 / 2.2) in `ink-muted`. Mixed staging fills the lower half with `added-bg`. A conflicted worktree uses a `conflict` dashed ring. Under reduced motion it is static |
| `stash` | Stash decoration | Dashed ring in the lane colour |
| `boundary` | `boundary: "shallow"` | Hollow 7 px square, `ink-muted`, 1.5 px stroke |
| `graft` | `type: "graft"` | Ring plus a concentric 1.5 px ring at r 7 |
| `replace` | `type: "replace"` | Ring plus a 90° arc at r 7 |
| `missing-parent` | Parent object absent | Edge ends in a 2 px hollow `ink-faint` dot at the row edge |
| `collapsed-group` | Merge with hidden side branch | Pill node carrying a `Count` with the hidden commit count |

## 5. Lane assignment: G-LANE-01

Rust implements G-LANE-01 exactly as stated in `graph-fixtures.json → algorithmNotes`. The HEAD first-parent spine reserves lane 0, and non-spine commits never occupy lane 0. Freed lanes are reusable, and an assignment never changes once it has been emitted. The fixtures are acceptance tests: `expectedLanes`, `expectedShapes` and `expectedLaneSegments` must match exactly.

## 6. Ref chips

Chips follow the `RefChip` component.

- Order on a row: the checked-out branch (`head` chip, solid `ink`), then local branches (`polar-soft` with a lane dot), remote branches (outlined, cloud icon), tags (notched, `tag-bg`), stash (outlined pill), worktree, pull request. Never draw a separate "HEAD" chip.
- **Tracking pair:** when a local branch and its upstream point at the same commit, draw one chip `● main | ☁ origin`. When they diverge, draw them separately and give the local chip ↑/↓ counts.
- Detached HEAD: the head chip shows `circle-dot` and the short hash, and the Compass says "Detached at 857ece8".
- `maxPills` 2 chips are visible by default, and the rest collapse into a `+N` chip. Overflow opens a bounded ref list rather than widening the row. Chips never wrap. A chip is as wide as its name up to `refChipMaxWidth`; it never reserves that maximum. Longer names keep both ends around an ellipsis (`MeridianMiddleEllipsis`), and the tooltip shows the full name.
- A commit with a stash decoration gets a Stash submenu (Apply, Pop, Rename, Drop) that acts on that stash's object identity.

## 7. Pinned metadata

- Order: shared content, then author (Avatar + name), then short hash, then date. The group is anchored to the right edge and each field is right-aligned within its width.
- There is no header band, divider, resize handle, reorder gesture or column-visibility menu. Filters and search live in the History island header.
- Reserve metadata first. Author prefers 132 px and may shrink to 80 px before eliding. The date uses the relative format ("7 min", "2 h", "3 d"), then an absolute one ("24 Sep", "24 Sep 2025"); a setting switches to ISO 8601. The hash is 10 characters in rows, and more when Git needs them to disambiguate. It is mono (`hash` style); dates use tabular numerals.
- Resolve field widths once per viewport, font scale and date format, and supply the same widths to every row.
- At the minimum window width and 130% text scale, all three fields stay visible. Elide the author and shorten the date before taking more graph space. The graph may clip completely for an extreme row; it never covers metadata.
- Clicking the hash copies the full OID.
- The selection bar spans the complete row, metadata included. HEAD and ref colours never imply selection.

## 8. Selection and keyboard

The single selection contract is in [`interaction-accessibility.md`](interaction-accessibility.md). For History:

- ↑↓ move current; Home/End jump; PageUp/PageDown move by page; ⇧↑↓ extend; ⌘/Ctrl-click toggles.
- Two selected commits form a comparison. Selection order defines old → new, and the Detail header shows `857ece8 → f4b3427`.
- ↵ opens Detail; Space toggles selection; ⌘A / Ctrl A selects the visible filtered range.
- → jumps to the first parent, ← to the child. ⌘C / Ctrl C copies the hash.
- Graph-focus mode (`focus` icon) maximises the History island; Esc restores.
- Clicking a branch or tag in the sidebar selects and reveals its commit without checking it out. Repeating the same target reveals it again. Newer navigation supersedes older pending requests.
- Filtering uses complete repository topology and refs. A retained selection outside the result is labelled as such. Detail and the graph always show the same commit, or an explicit loading state for the requested one.
- The graph starts from HEAD, local and remote branches, tags and the stash. Commits only other refs reach (notes, pull mirrors, other tools' checkpoints, `refs/gitlama/*`) are hidden with their labels until Show other refs in the island header's view options menu is checked. Revealing a hidden commit shows a notice with Show other refs instead of selecting nothing.

## 9. States

| State | Rendering |
|---|---|
| Empty repository | Centred empty state in `display`: "No commits yet", with a Button "Open Changes" |
| Initial loading | Three skeleton rows (`pane-alt` bars at `radius-sm`); the metadata placeholders occupy the pinned region; the Compass progress rule runs |
| Background loading | Topology, refs and summaries populate automatically, visible rows first. There is no manual "Load older" barrier |
| Incremental publication | Keeps selection and viewport anchor stable (fixture `incremental-loading`) |
| Navigation or filter pending | The island header shows the requested target or filter and Cancel. Previous rows are never presented as the new result |
| Summary unavailable | Keeps commit identity and geometry, with a typed per-row fallback ("Summary unavailable") |
| Load retry | Retry row with `rotate-ccw` and the error text; scroll position is kept |
| End of history | Footer row "End of history · N commits" in `caption` `ink-muted` (fixture `end-of-history`) |
| Shallow history | Boundary nodes per §4, plus a footer Button "Fetch more history" |
| Stale update | `Banner` tone `info`: "6 new commits on origin/main", with Refresh and Dismiss |

## 10. Virtualization

- Row height is fixed per density. The WIP row uses the standard height.
- Each row paints from its own projection slice (segments carry from/to lanes and kinds). Continuity is never derived from neighbouring widgets.
- Node hit area: 14 px around the lane centre on its row; the rest of the row is the row hit area. Fixtures carry `virtualization.realizedWindow` to test recycling.
- Search keeps matching rows at full contrast and dims non-matches (list and graph) to 0.3. The match count shows in the search field's trailing text.

## 11. Acceptance

1. `graph-fixtures.json`: `expectedLanes`, `expectedShapes` and `expectedLaneSegments` match on all 21 fixtures (`cargo test` in `rust-core`, `graph::tests`).
2. `graph-row-layout-fixtures.json` resolves the sparse, dense, offscreen, clipped and 130% cases exactly.
3. Scrolling the 40-row virtualization window across [0, 40) causes zero lane reassignments and no seams at window edges.
4. Flutter captures follow [`capture-matrix.json`](capture-matrix.json): both themes, all densities, 130% text scale, 12-character hashes, long authors and refs, crossing and octopus edges, and a scrolled mid-history viewport.
5. Pointer, keyboard and screen-reader replay after filtering, same-target reveal, recycling, density change and resize select and copy the same OID.
