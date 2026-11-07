# Palette

The command palette, opened from the Commands button beside the Compass or with ⌘P / Ctrl P; it grows out of that button. One field searches commands, branches, tags, repositories and files. Results are grouped under `overline` headers. The consumer provides `query` and `groups` (`title`, `items` as Menu items). Mark matched characters in a label with ⟦ ⟧.

Commands are phrased with their real targets ("Rebase windows-soak-cleanup onto origin/main"), so the palette doubles as a preview. Tab cycles the scope (All → Branches → Files → Commands). ⌘↵ runs the command in the background, and it shows up in the Logbook.

Specimen: [`../specimens/components/Palette.html`](../specimens/components/Palette.html). Reference implementation: `GitLama.Palette` in `reference/bundle.js`, props in `reference/index.d.ts`.
