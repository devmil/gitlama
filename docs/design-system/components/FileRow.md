# FileRow

A changed file in Changes (unstaged or staged) or in a commit's file list. It shows StatusGlyph, the directory in `ink-muted`, the file name in `ink`, and +/− counts in mono. The consumer provides `status`, `path`, `add`, `del`, `staged`, `state` and `depth` (tree mode).

On hover or focus the counts give way to hover actions: Stage/Unstage and Discard (unstaged only). Space stages or unstages the focused file. Every hover action is also in the context menu and has a shortcut. Dragging to the other list works too, but it's never the only way.

Specimen: [`../specimens/components/FileRow.html`](../specimens/components/FileRow.html). Reference implementation: `GitLama.FileRow` in `reference/bundle.js`, props in `reference/index.d.ts`.
