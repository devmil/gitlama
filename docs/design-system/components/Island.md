# Island

The rounded work surface. History, Changes, Detail, Diff and Conflict resolver are each an island on `ground`: `pane`, `radius-lg`, `shadow-pane`, `space-3` (6px) apart, and `space-3` from the window edge. The consumer provides `title`, optional `subtitle` (meta text), `actions` (IconButtons and small Buttons for the header), `focused`, and the content.

Only one island is focused at a time (⌘1–⌘4 or Tab moves between them). The focused island gets a 1px `polar-soft` halo and a solid `polar` selection. The gutters between islands are the splitters: dragging one resizes, and a double-click resets it. Islands never nest.

Specimen: [`../specimens/components/Island.html`](../specimens/components/Island.html). Reference implementation: `GitLama.Island` in `reference/bundle.js`, props in `reference/index.d.ts`.
