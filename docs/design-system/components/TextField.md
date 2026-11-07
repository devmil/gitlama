# TextField

Single-line input. The consumer provides `placeholder`, `value`, optional leading `icon`, `trailing` text (match counter, character count), `variant="search"` (a filled `pane-alt` well with no edge until focused, for filters in island headers), `size="sm"`, `error` and `message`.

The edge is `control-edge` (3:1). Focus adds a 1px `focus` ring on top of a `focus` edge. Errors show a `danger` edge plus one `caption` line below, saying what's wrong and how to fix it. Don't use floating labels: put a label to the left (see SettingsRow) or above.

Specimen: [`../specimens/components/TextField.html`](../specimens/components/TextField.html). Reference implementation: `GitLama.TextField` in `reference/bundle.js`, props in `reference/index.d.ts`.
