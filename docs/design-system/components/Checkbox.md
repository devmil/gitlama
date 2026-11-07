# Checkbox

Checkbox and Switch. Use a **Checkbox** for options that apply when you run a command (Amend, Sign, Include tags on this push). Use a **Switch** for settings that apply straight away (Fetch automatically). The consumer provides `checked`, `mixed` (a partial selection, e.g. some hunks staged), `disabled` and the label as `children`.

The box is 16px with a `control-edge` border and fills with `polar` when on. Clicking the label toggles it. Space toggles it on focus.

Specimen: [`../specimens/components/Checkbox.html`](../specimens/components/Checkbox.html). Reference implementation: `GitLama.Checkbox` in `reference/bundle.js`, props in `reference/index.d.ts`.
