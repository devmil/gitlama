# Avatar

Author initials on a lane colour, picked from a stable hash of the name, so the same person keeps the same colour across repositories. 16px in rows, 28px (`size="lg"`) in the Detail header. Gravatar images, when the user opts in, replace the fill but keep the size and round shape. The avatar always sits next to the name as text, so it's `aria-hidden`.

Specimen: [`../specimens/components/Avatar.html`](../specimens/components/Avatar.html). Reference implementation: `GitLama.Avatar` in `reference/bundle.js`, props in `reference/index.d.ts`.
