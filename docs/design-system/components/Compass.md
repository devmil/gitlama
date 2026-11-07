# Compass

The centre of the title bar and GitLama's signature control. It answers "where am I, and what is running". The consumer provides `repo`, `branch`, `detached`, `ahead`, `behind`, `dirty` (changed file count), `conflicts`, and during an operation, `operation` (a present-tense verb such as "Fetching origin…") with optional `progress` from 0 to 1 (omit it for indeterminate).

- Click it to grow it into the repository details overlay: location (this computer or the host), path, type, branch and upstream, changes, a paused Git operation, the running operation and the Git version, with Copy path and Open in the file manager. The overlay starts at the Compass and shrinks back into it when it closes; with Reduce Motion it fades.
- The Palette has its own Commands button beside the Compass (and ⌘P / Ctrl P). An equal space on the Compass's other side keeps the Compass centred. The Logbook opens from its right end.
- The branch is `polar-ink`. Sync uses SyncBadge (↑ in `polar-ink`, ↓ in `modified`). A clean, synced branch shows a check mark.
- While running, the readout is replaced by the verb and a 2px `polar` rule runs along the bottom. Background fetches only show the rule, never the verb.
- Never put buttons inside the Compass. It's one target.

Specimen: [`../specimens/components/Compass.html`](../specimens/components/Compass.html). Reference implementation: `GitLama.Compass` in `reference/bundle.js`, props in `reference/index.d.ts`.
