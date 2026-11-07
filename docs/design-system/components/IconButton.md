# IconButton

A single icon command for toolbars, island headers and row hover actions. The consumer provides `icon`, a required `label` (used for the tooltip and the accessible name), `size="sm"` in rows and headers, `active` for toggles (view mode, filters, which get `polar-soft` plus `polar-ink`), and `onGround` when it sits on `ground` rather than an island.

Idle icons are `ink-muted` and go to `ink` on hover. Use an IconButton only where the icon is unambiguous in Git terms. Anything else needs a Button with a label.

Specimen: [`../specimens/components/IconButton.html`](../specimens/components/IconButton.html). Reference implementation: `GitLama.IconButton` in `reference/bundle.js`, props in `reference/index.d.ts`.
