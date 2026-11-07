# CommitRow

One commit in History: Graph, refs and subject, author with Avatar, 10-character hash, relative date. The consumer provides `graph`, `subject`, `refs` (RefChip props), `author`, `hash`, `when`, `state` (`selected` or `focused`), `wip` (the uncommitted-changes row, italic and muted, with a dashed node) and `dim` (filtered out but kept for context).

- Row height follows density (`size-row`, 28px by default). Selection is an inset `radius-sm` bar. When History has focus it's solid `polar` and the hash, author and date switch to `on-polar-muted`.
- Refs come before the subject, so the eye finds branches down one column.
- Authors and dates are sans. Only the hash is mono.
- Keyboard: ↑↓ move, ⇧↑↓ extend to compare two commits, ↵ opens Detail, ⌘C copies the hash, → jumps to the first parent, ← to the child.

Specimen: [`../specimens/components/CommitRow.html`](../specimens/components/CommitRow.html). Reference implementation: `GitLama.CommitRow` in `reference/bundle.js`, props in `reference/index.d.ts`.
