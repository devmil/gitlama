# RefChip

A ref label in a commit row or the detail header. `kind`: **head** (the checked-out branch, solid `ink`; there is never a separate "HEAD" chip), **local** (`polar-soft`, with a dot in its lane colour), **remote** (outlined, cloud icon), **tag** (notched, `tag-bg`) or **stash** (outlined pill). Also takes `name`, `lane`, `ahead`/`behind`, and `upstream`.

**Tracking pairs:** when a local branch and its upstream point at the same commit, pass `upstream: 'origin'` to draw one chip, `● main | ☁ origin`, instead of two. When they diverge, draw them separately and give the local chip ↑/↓. This halves chip noise in busy histories. Chips cap at 220px and truncate in the middle of long names.

Specimen: [`../specimens/components/RefChip.html`](../specimens/components/RefChip.html). Reference implementation: `GitLama.RefChip` in `reference/bundle.js`, props in `reference/index.d.ts`.
