# Banner

A persistent, inline message about the state of the repository or the island it sits in. The consumer provides `tone` (`info`, `warning`, `conflict` or `error`), a bold `title` sentence, the detail as `children`, and at most two `actions`.

Banners sit at the top of the island they concern, `radius-lg`, tinted in their tone's `-bg` colour, with no border. Use conflict (orange) for a paused merge, rebase or cherry-pick: it's work to do, not a failure. Transient results ("Pushed 3 commits") go to the Logbook, not a banner.

Specimen: [`../specimens/components/Banner.html`](../specimens/components/Banner.html). Reference implementation: `GitLama.Banner` in `reference/bundle.js`, props in `reference/index.d.ts`.
