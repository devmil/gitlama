# ADR 0006: GitLama is a Rust application with a Qt Quick interface

- Status: accepted
- Date: 2026-11-23
- Supersedes: [ADR 0001](0001-flutter-rust-port.md)

## Context

GitLama shipped as a Flutter interface over a Rust core joined by flutter_rust_bridge. Every
Git semantic, session, projection, the remote helper and persistence were already Rust; Dart
held the services and workflows, a second copy of every data type and the bridge mappings.
The sibling applications (ProcessLama and MailLama) moved to Rust with Qt Quick, and the
Meridian design system gained a QML implementation with the same tokens, controls and motion.

## Decision

GitLama becomes one Rust workspace with a Qt Quick (QML) interface and no Flutter, Dart or
generated bridge:

- The Dart services and workflows are ported to `rust-core/desktop/workbench`, a Qt-independent
  crate of single-threaded services on the GUI thread with a blocking pool for native work.
- `rust-core/desktop/qt` exposes them to QML through qtbridge objects and item models; QML
  views use Meridian's QML controls and keep git-domain components in `qml/GitLama`.
- The core facade (`rust-core/src/api.rs`) stays as plain Rust functions; the remote wire
  codecs are generated from the Rust sources alone.
- The application identity (`de.devmil.gitlama`, the executable `gitlama`) and every persisted
  location stay as earlier releases used them, so an installed GitLama updates in place.
- The remote helper and its protocol are unchanged by the move; the helper version follows
  the usual compatibility rules in `AGENTS.md`.

## Consequences

- One language owns state, workflows and Git semantics: no DTO mapping layer, no second copy of
  each type, and no bridge regeneration step.
- The history graph rows and text formatting are native Qt Quick items in C++; lists stay
  fixed-extent and virtualized ([ADR 0002](0002-fixed-extent-history-graph.md),
  [ADR 0003](0003-fixed-extent-bounded-diff.md)).
- Packages carry or depend on the Qt 6 runtime (LGPL, linked dynamically); Arch Linux gains a
  native package.
- Qt Quick has no platform spell-check service, so commit messages are not spell-checked, as
  with the Flutter desktop embedders before.
- Native appearance, signing, accessibility and performance acceptance is checked per platform
  on target hosts; host tests do not stand in for it.
