# Logbook

The operation history, dropped from the right end of the Compass. It replaces modal progress dialogs and toasts. The consumer provides `entries`: `status` (`run`, `ok`, `warn` or `fail`), `verb`, `target`, `meta` (repo, duration, count), `time`, and optionally `command` and `output`.

Each entry is a node on a timeline: a ringed mark in its status colour with an icon (check, triangle, cross, spinner), so the state never relies on colour alone. Expanding a row shows the exact `git` command and its output in `code`. Repeated background fetches collapse into one line with a count. Warnings and failures stay until you dismiss them, and a failure also puts a `danger` dot on the Compass.

Specimen: [`../specimens/components/Logbook.html`](../specimens/components/Logbook.html). Reference implementation: `GitLama.Logbook` in `reference/bundle.js`, props in `reference/index.d.ts`.
