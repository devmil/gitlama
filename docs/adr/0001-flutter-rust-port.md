# ADR 0001: preserve QSpline behavior through a Flutter/Rust boundary

Accepted 2026-09-19.

GitLama takes over the user experience, design and features of QSpline, an earlier Rust and Qt Quick Git client by the same author. Use Flutter for presentation and lifecycle, retain Rust ownership of Git semantics and authoritative repository state, and use one generated FRB bridge. Dart services project state and expose commands; repositories own the bridge. Use installed Git through devmil-git, not a new libgit2 implementation.

A Qt embedding would preserve code but fail the requested stack. Rebuilding Git semantics in Dart would duplicate the existing tested Rust behavior. Copying all QSpline crates immediately would import Qt dependencies and mature-product assumptions into an empty foundation. Start with a tested handshake, then port cohesive use cases against the parity ledger. Extract generic adapters into the shared crate when both consumers can use them.

The cost is explicit DTO mapping and Flutter renderer qualification. The benefit is retaining one source of Git behavior while allowing native Flutter presentation. Revisit crate splitting when concrete feature boundaries justify it; never use that as permission to weaken dependency direction.
