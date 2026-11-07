# StatusGlyph

A file's Git state as a 16px mono letter tile. `status`: M modified, A added, D deleted, R renamed, C copied, U conflicted, ? untracked, ! ignored. Each tile pairs its letter with its colour, so the state never relies on colour alone. The accessible name is the full word.

Use it at the start of every file row, in the Changes and Detail file lists, and in tree folders (a folder shows the "strongest" state inside it, in order U › D › M › A).

Specimen: [`../specimens/components/StatusGlyph.html`](../specimens/components/StatusGlyph.html). Reference implementation: `GitLama.StatusGlyph` in `reference/bundle.js`, props in `reference/index.d.ts`.
