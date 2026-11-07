# Segmented

Picks one of 2–4 peer options that change a view: diff layout, list or tree, theme. The consumer provides `options` (`value`, `label` and/or `icon`, `title`), `value`, `onChange`, `size="sm"` and an accessible `label`.

The track is `pane-alt` with a `line` edge. The selected option is a `pane` tile with a `line-strong` edge and `shadow-control`. Use it for switching views, never for commands. More than four options → Select.

Specimen: [`../specimens/components/Segmented.html`](../specimens/components/Segmented.html). Reference implementation: `GitLama.Segmented` in `reference/bundle.js`, props in `reference/index.d.ts`.
