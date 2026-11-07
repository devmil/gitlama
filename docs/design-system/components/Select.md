# Select

Select, and the Menu it opens (the same component is used for context menus). The Select trigger looks like a secondary Button showing the current value. The consumer provides `value` and `width`. Menu takes `items`: `label`, `icon`, `kbd`, `hint`, `danger`, `disabled`, `hl` (the keyboard-highlighted row), or `{type:'sep'}` / `{type:'header'}`.

Menus float: `raised`, `radius-xl`, `shadow-float`, rows `size-row`. The highlighted row is solid `polar`. Put the object's name in the label ("Merge into windows-soak-cleanup"). Destructive items go last, in `danger`, after a separator.

Specimen: [`../specimens/components/Select.html`](../specimens/components/Select.html). Reference implementation: `GitLama.Select` in `reference/bundle.js`, props in `reference/index.d.ts`.
