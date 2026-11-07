# Graph

The spline graph cell for one commit row. Lanes are 2px strokes `size-lane` (14px) apart. They change column along an S-curve that leaves and lands vertically, never a diagonal. The consumer provides `cols`, `height` (the row height) and `segs`: `v` (straight through), `top` / `bot` (into or out of the node), `in` / `out` (curving between columns into or out of the node), `x` (a curve crossing the whole row). Each takes `lane` and optionally `faint`. `node` takes `c`, `lane` and `kind`.

Nodes: **commit** is a 9px ring in the lane colour, filled with the row's background. **HEAD** is a filled dot inside a ring. **merge** is a ring with a centre dot. **stash** and **wip** are dashed rings. `lane-1` always belongs to HEAD's first-parent line. On a focused (polar) row, every stroke turns `on-polar`. Hovering a node for 400ms highlights that commit's first-parent line and fades other lanes to 30%.

Specimen: [`../specimens/components/Graph.html`](../specimens/components/Graph.html). Reference implementation: `GitLama.Graph` in `reference/bundle.js`, props in `reference/index.d.ts`.
