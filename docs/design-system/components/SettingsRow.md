# SettingsRow

A desktop-native settings form: the label is right-aligned in a 200px column, controls sit on the left of the next column, and help goes below in `caption` `ink-muted`. SettingsGroup lays the rows out. SettingsRow takes `label`, `help` and the controls as `children`.

No floating labels, no Material outlines, no cards. Changes apply straight away with no Save button, and are confirmed by the control's own state. Settings open as a sheet in the window with a left-hand page list (Appearance, Git, Accounts, Tools, Diff, Shortcuts, Accessibility, Licenses).

Specimen: [`../specimens/components/SettingsRow.html`](../specimens/components/SettingsRow.html). Reference implementation: `GitLama.SettingsRow` in `reference/bundle.js`, props in `reference/index.d.ts`.
