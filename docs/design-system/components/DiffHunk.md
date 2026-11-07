# DiffHunk

One hunk: a sticky header strip (range, enclosing context, actions), then line rows with old and new line numbers, a sign column and code in `code` (JetBrains Mono 12/18). The consumer provides `range`, `context`, `lines` (`t` is ' ', '+' or '-', plus `o`, `n`, `text`, `picked`), `staged` and `picked` (switches the action to "Stage lines").

Added lines are `added-bg`, removed lines `deleted-bg`, with the changed words wrapped in ⟦ ⟧ and highlighted in `added-strong` / `deleted-strong`. The sign is a real − (U+2212) in the status colour, so it survives colour-blindness and greyscale. Picked lines get a 3px `polar` inset rail. Click or drag in the gutter, or press ⇧↑↓ then S, to stage lines. Discard always asks.

Specimen: [`../specimens/components/DiffHunk.html`](../specimens/components/DiffHunk.html). Reference implementation: `GitLama.DiffHunk` in `reference/bundle.js`, props in `reference/index.d.ts`.
