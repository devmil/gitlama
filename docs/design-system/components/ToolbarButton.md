# ToolbarButton

A Git verb in the unified title bar: an 18px icon (1.75 stroke) over a `caption` label, on `ground`. The consumer provides `icon`, `label`, an optional `badge` (a count, such as commits to pull, shown as a `polar` Count) and `menu` (adds a split caret for variants such as Pull → Rebase or Push → Force with lease).

Order: Fetch, Pull, Push, Stash, then Branch and Merge. The Compass sits in the middle, and view toggles go on the right as IconButtons. Buttons sit on `ground` with no border. Hover is `ground-hover`.

Specimen: [`../specimens/components/ToolbarButton.html`](../specimens/components/ToolbarButton.html). Reference implementation: `GitLama.ToolbarButton` in `reference/bundle.js`, props in `reference/index.d.ts`.
