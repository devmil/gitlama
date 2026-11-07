# SyncBadge

Ahead/behind relative to the upstream. ↑N in `polar-ink` (yours to push), ↓N in `modified` (theirs to pull). The consumer provides `ahead`, `behind` and `showZero` (draws a check mark when in sync; used in the Compass). It renders nothing when both are 0 and `showZero` is false, which is the norm in the sidebar. Numbers are tabular. The tooltip spells it out: "3 ahead, 6 behind".

Specimen: [`../specimens/components/SyncBadge.html`](../specimens/components/SyncBadge.html). Reference implementation: `GitLama.SyncBadge` in `reference/bundle.js`, props in `reference/index.d.ts`.
