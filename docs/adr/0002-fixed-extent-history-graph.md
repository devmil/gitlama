# ADR 0002: use bounded native pages and fixed-extent painted history rows

Accepted for local implementation 2026-09-19. Cross-platform and physical rendering qualification remains pending.

## Context

GitLama must navigate and render histories of at least 100,000 commits without transferring the whole graph or creating one view item per commit. The adopted QSpline contract also requires deterministic G-LANE-01 topology, stable commit identity, per-row occupied graph geometry, clipped graph input before pinned metadata, and accessible row selection.

The shared `devmil-git` repository already owns frozen-tip traversal, prefix reads, complete topology reads, metadata batching and cache accounting. GitLama must not replace that loader or add another repository worker/cache.

## Decision

Rust owns G-LANE-01 lane assignment, segment kinds, node shapes and row geometry. Repository sessions retain one newest accepted application projection. They load through `Repository::history_prefix` for the 512-row preview and `Repository::history` for complete topology, then expose only bounded bridge pages of at most 512 rows. A replacement request invalidates the old request identity. Metadata remains independently hydratable; topology identity does not depend on commit messages.

The interface uses a fixed-extent, virtualized list (since [ADR 0006](0006-rust-qt-quick-application.md) a QML `ListView` over `HistoryModel`). Each visible row paints its graph primitives with the native `GraphRow` item (`rust-core/desktop/app/src/native/graph_row.cpp`) and shows subject and pinned author/hash/date as ordinary text items. Rust-supplied clip and content geometry controls paint placement. The view does not derive lanes from neighboring visible rows. Selection dispatch uses the full stable object ID, including clicks in empty text or pinned metadata space.

The proof on this macOS arm64 host loaded a real 100,000-commit repository in release mode with a 354 ms prefix, 551 ms complete topology, 93 ms warm cached request, a 131,072-byte 512-row bridge page and 178,896,896-byte maximum resident set for the standalone test process. The Flutter 100k model of the time instantiated fewer than 100 fixed-extent rows before and after a direct mid-history jump. These are local measurements, not portable release claims.

## Rejected alternatives

An item for every commit is rejected because item and accessibility counts scale with repository size. A single monolithic canvas is rejected because it would recreate row semantics, text selection, focus, hit testing and incremental repaint behavior manually. A table/data-grid is rejected because the accepted integrated graph/ref/message geometry has per-row content starts and no global graph column. Computing lanes in the interface is rejected because it would duplicate the topology oracle and make viewport contents affect graph identity.

A custom list item layout remains a possible later optimization, but the proof does not justify its lifecycle and accessibility cost: the fixed-extent builder already bounds live rows and selection dispatch. Revisit only if production profile traces show the row/painter composition misses the accepted frame budget.

## Consequences

The bridge needs request identity, completion state, total topology size, bounded rows/segments and explicit payload accounting. Full topology and lane reservations consume session memory, while row metadata and detail remain paged. P04 must add same-generation preview/completion publication, visible-target metadata priority, cancellation and immutable lane reuse without turning the proof API into a second history loader.

The renderer is now constrained by fixture tests rather than screenshots. Profile frame captures, both themes, density/text-scale matrices, Linux/Windows execution and assistive-technology checks remain qualification gates.
