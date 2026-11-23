# GitLama architecture

Status: accepted. This describes the code as it is.

## Stack and boundary

GitLama is a Rust application with a Qt Quick (QML) interface. QML owns painting, input
routing, focus, accessibility roles and presentation localization. Rust owns everything
else: Git semantics through the installed Git (via `devmil-git`), repository sessions,
graph topology and layout, authoritative selection identities, workflows, operation
coordination, persistence, remote workspaces and background work. Dependencies point
inward:

```text
qml/GitLama (views, Meridian controls)
    -> desktop/qt: qtbridge QObjects and item models (projection and commands only)
        -> desktop/workbench: services, workflows, observable state (no Qt)
            -> gitlama_core api (rust-core/src): the core facade and desktop-only services
                -> gitlama_application: sessions, use cases, projections, wire adapter
                    -> domain values -> devmil-git Repository / hosting -> installed Git
```

The Rust code is one Cargo workspace (`rust-core/Cargo.toml`, one lockfile):

- `gitlama_contract` (`rust-core/contract/`): the plain data types (`Native*`) every layer
  and the remote wire carry. Types only, with no public functions or inherent impls.
- `gitlama_application` (`rust-core/application/`): the domain (`domain/`), the session
  registry and use cases (`application/` and the family modules) and the generated JSON
  wire adapter (`wire/`). Its `image-codecs` feature (on for the desktop) decodes image
  diffs; `build.rs` embeds the release identity and the remote helper ID.
- `gitlama_core` (`rust-core/src/`): the facade (`api.rs`, a delegating function per call)
  and desktop-only services such as hosting, CLI forwarding and avatars.
- `gitlama-remote-helper` (`rust-core/remote-helper/`): runs the application crate headless
  on another computer, without the image codecs. It never depends on the desktop crates.
- `gitlama-workbench` (`rust-core/desktop/workbench/`): the desktop's services and
  workflows, independent of Qt: workspace and tabs, repository sessions, history, changes,
  commit, inspector, conflicts, rebases, hosting and review, remote workspaces, updates,
  settings, diagnostics and the view and link caches.
- `gitlama-qt` (`rust-core/desktop/qt/`): the qtbridge objects QML binds to and the item
  models of the history graph, file lists, diffs and blame.
- `gitlama` (`rust-core/desktop/app/`): the composition root and executable, the embedded
  QML resource, native Qt Quick items in C++ (the graph row and text formatting), the
  platform hooks (macOS window chrome and Sparkle, the Linux desktop entry, Windows console
  attachment) and the development screenshot hook.

`scripts/check_architecture.py` enforces the directions: the contract depends on no
GitLama crate and declares no behaviour; the application depends only on the contract and
never on its wire adapter from the application layer; the helper depends only on the
application; the core never reaches the Qt layers; the workbench never reaches Qt; the Qt
crate reaches the core only through the workbench and never starts a process. In QML it
rejects imports beyond Qt, Meridian and GitLama, code loaded at run time, Qt Quick Controls
menus outside `CommandMenu`, and credential fields reaching the bridge.

## Composition and lifecycle

`main.rs` starts the Qt application, creates the window's QObjects and passes them to
`Main.qml` as initial properties (`app`, `workspace`, `history`, `changes`, `remote` and
the others, reached in QML through the `Store` singleton). `gitlama_workbench::app::App`
owns startup: it composes `Services` (`app.rs`) in dependency order, publishes the startup
phase (loading, failed, ready) and, on Retry, builds a fresh composition; a failed start
disposes what it built. On exit the host awaits `App::shutdown`, which disposes the
services in reverse order: pending prompts, CLI forwarding, hosting (flushing the link
cache), auto-fetch, the operation center, the workspace's sessions, the view cache, remote
connections, history and finally settings, flushed atomically.

Inspector windows are further QML windows of the same process with their own read-only
sessions (`inspection_windows.rs`); a window of a repository on a remote host reads
through the main connection.

## The Qt bridge

The workbench runs on a single-threaded async runtime (`workbench/src/rt.rs`) on the GUI
thread. Blocking native work (Git, files, network) runs on a bounded blocking pool and
wakes its task when it completes. `gitlama-qt`'s `Driver` is the pump: QML slots post
commands, the pump runs them and the ready tasks, then projects what changed onto the
QObjects, one borrow at a time. Services publish change topics through
`notify::Notifier`; the driver re-projects only what a topic names, and compares a
projection with the last one before setting it, so an unchanged value never notifies QML.

Rules:

- A QML slot never re-enters a borrowed object synchronously. Commands are posted and
  results arrive as property changes or signals.
- Strings shown to people are translated in QML (`L10n`, generated from `l10n/app_en.arb`
  and `l10n/app_de.arb` by `tooling/l10n/generate.py`). The core sends message keys and
  arguments, never English text.
- Large collections are item models (`HistoryModel`, `RowModel`, `DiffModel`,
  `BlameModel`), not JSON properties; rows are fixed extent and virtualized.
- Paths travel to QML as byte arrays and are shown through `Labels`; they are never parsed
  from display text.

## Services and state

Each service owns one workflow family and its observable state; a boundary (persistence,
a native call, the network) has one owning service. `WorkspaceService` owns tabs, groups,
navigation, the active session, the session lifecycle and event draining. Command
families (working copy, references, transfers, stashes, history mutations, rebase and
restack, conflicts, named snapshots, extensions, integrations, power tools, patches,
archives, diff renderers) are services over the sessions the workspace hands them.
Commands are evaluated and dispatched in one place (`commands.rs` with the QML `Commands`
and `CommandMenus` catalogues), from service-published context, never from mounted views.

`HistoryService` owns the graph: topology, selection, queries, branch filters, search and
reflog. It announces each selected commit or comparison and never reads a commit's diff.
`InspectorService` owns what the Detail pane shows: one location (target, scope, focus
path, lens, line range, history entry, anchor), a Back and Forward stack and the reads
behind each lens. The [inspector spec](design-system/specs/inspector.md) defines the
behaviour.

Remote workspaces reuse the same session calls: `backend::RoutedCalls` routes each session
to this computer or to its host's connection (`remote::service::Router`), and remote paths
carry their authority. See [remote workspaces](remote-workspaces/README.md).

## Shared Repository integration

The normal native entry point is `devmil_git::Repository`, not `RepositoryDiscovery`,
`GraphLoader` or hand-built read commands. Construct with `RepositoryOptions`, subscribe
before `load()`, and project `RepositorySnapshot` and `RepositoryEvent` into the contract's
types. Construction performs no discovery; use `from_discovered` only when an earlier
shared operation resolved the identity.

The shared model owns worker and watcher lifetime, refresh coalescing, duplicate pending
reads, cache accounting and recorded Git execution. GitLama owns layout, selection, graph
lane geometry, typed effects, mutation sequencing, confirmation, credentials and
persistence. Hosting and external tools are separate entry points; hosting refresh
scheduling stays in GitLama.

Map `Snapshot` and `Resynchronize` into coherent replacement publications; a slow
subscriber must not replay lost deltas. Tickets return `Arc<T>` or typed errors, not a
product revision envelope, so keep session and request identity and validate freshness at
the adapter. `close()` and Drop cancel and join the worker, so teardown runs on the
blocking pool, never on the GUI thread.

Activity and wakeup callbacks run on the repository worker and must return promptly: a
wakeup schedules event draining, not a UI call or a synchronous wait. Keep private
unredacted parser buffers native. Map `RepositoryErrorKind` and activity identity to safe
product failures rather than showing the shared error message.

`rust-core/Cargo.toml` pins devmil-git to an exact revision; `scripts/shared_git_pin.py`
describes local development against a devmil-git checkout.

## Native contracts

An object ID is a full identity, never a shortened display hash or a row index. Paths keep
their native bytes; presentation uses a display string and the bytes for operations.
Avoid lossy UTF-8 round trips for file names.

Every repository publication carries the session generation, the query revision and the
publication sequence. Requests that can be superseded (diff selection, graph queries,
reveals, hosting searches) carry a request identity, and stale results are discarded
before they change service state. Row indexes are viewport positions only; scroll is kept
as a stable identity plus an offset.

Durable selection, repository health, operation state and settings are snapshots. Copy,
open-external, focus restoration and reveals are typed effects with identity; a repeated
request to reveal the same commit still reveals it.

Errors use a closed product taxonomy with bounded fields: unavailable Git, unsupported
version, unavailable repository, authentication required, permission denied, conflict,
stale precondition, canceled, timeout, output limit and internal failure. Unknown external
variants map to a safe fallback. Neither Debug output nor English error text is protocol.

## Scheduling and mutation safety

One native session owns a shared `devmil_git::Repository` handle per worktree. GitLama
implements no second refresh loop or read cache. Application index, ref and worktree
mutations are serialized where their lock domains overlap; shared refresh reconciles
afterward. Obsolete reads are canceled and late publications rejected by identity even
when cancellation races. Git never runs, and a large diff is never decoded, on the GUI
thread.

An operation has an intent, preconditions, a cancellation handle, progress, activity
identity, a commit point, a final outcome and an optional refresh degradation. Before a
destructive command, its exact identities and preview scope are resolved, and execution
revalidates the index, worktree and ref state. Arguments go to Git as an array through
devmil-git, never through a shell. User-configured shell commands are a separate explicit
capability with preview and consent.

Once Git confirms a mutation, later cancellation or a failed refresh cannot make it "not
applied": success is kept and refresh degradation reported separately. An uncertain outcome
needs reconciliation before retry. Credentials stay native and out of activity, settings
and fixtures.

Activity records command intent and output through bounded redaction: secrets and
authenticated URLs are removed. Safe diagnostics use reviewed event codes and no raw
paths or exceptions; see [diagnostics](diagnostics.md).

## Graph and diff design

Rust calculates lanes, topology, ancestry lighting, occupied graph ink, filtering and
stable row projections. QML shows them in virtualized fixed-extent list views; each graph
row is painted by the native `GraphRow` item (`desktop/app/src/native/graph_row.cpp`) from
the row's segments, never by inferring parentage from neighbouring rows. Metadata is
pinned and hit-tested separately from clipped graph ink. Preserve G-LANE-01 and all graph
layout fixtures. See [ADR 0002](adr/0002-fixed-extent-history-graph.md).

Topology and summaries load under separate bounds: complete topology serves navigation and
filters without hydrating every commit message. Publications are anchored by object ID;
offscreen continuation geometry is kept.

Diffs and staging use revision-scoped hunk and line identities with the original bytes kept
natively. Stage, unstage and discard are different commands with different safety rules.
Patch preconditions, line endings, encodings, missing newlines, renames, binary files and an
externally changed index are validated. Highlighting and image decoding are bounded
background jobs; a large or binary file falls back to a clear state without fabricated text.
See [ADR 0003](adr/0003-fixed-extent-bounded-diff.md).

## Persistence and platform integration

Rust owns versioned settings and workspace persistence at the locations earlier releases
used, so an update keeps everything: the settings document (`storage::settings_default_path`),
the pending remote operations, the SSH trust store and the OS keyring entries of hosting.
Writes are atomic replace with explicit corruption reporting; unreadable storage is distinct
from absent data and never triggers a destructive reset. The view cache and the hosting
link cache are disposable private entries beside the settings (`cache/views`,
`cache/hosting-links`); an entry of another schema is removed and rebuilt.

Git is external, not libgit2; devmil-git discovers and validates it. Finder's PATH differs
from a terminal, so the child-process PATH is resolved on a worker and cached. Windows
command quoting and cancellation preserve process-tree ownership. Linux packages depend on
the Qt 6 runtime or bundle it, per [packaging](PACKAGING.md).

The macOS client needs access to arbitrary repositories and installed tools: GitLama ships
outside the App Store, unsandboxed, with hardened runtime, signing and notarization as release
requirements. Desktop launch, file-open integration, shortcuts, clipboard and external tools
each need target checks before shipping.

## Directory responsibilities

| Path | Owner and allowed contents |
| --- | --- |
| `qml/GitLama/` | The interface: windows, panes, dialogs and git-domain components |
| `qml/Meridian/` | The vendored Meridian design system (`scripts/sync-meridian.sh`); never edited here |
| `l10n/` | The English and German catalogs; English is the template |
| `rust-core/desktop/app/` | Composition root, executable, native items and platform hooks |
| `rust-core/desktop/qt/` | qtbridge objects and item models: projection and commands only |
| `rust-core/desktop/workbench/` | Services and workflows, independent of Qt |
| `rust-core/src/` | The core facade (`api.rs`) and desktop-only services |
| `rust-core/contract/` | Data types every layer and the wire carry; data only |
| `rust-core/application/src/domain/` | Domain values and rules; depends on nothing above it |
| `rust-core/application/src/application/` | Session registry, use cases and projections |
| `rust-core/application/src/wire/` | Generated JSON codecs and dispatch for the remote helper |
| `rust-core/remote-helper/` | The headless helper for remote workspaces |
| `tooling/` | Generators: localization, remote wire codecs and call routing, Meridian theme |
| `docs/design-system/` | Meridian adoption: tokens, components, specimens, behaviour specs and oracles |
| `packaging/` | Release artifact matrix and platform metadata |
| `webfront/` | The static public website |

## Build and supply chain

Rust is pinned by `rust-toolchain.toml`, crates by `Cargo.lock` (`--locked` everywhere),
devmil-git and Meridian by immutable Git revisions, and Qt by the version the CI and release
workflows, `scripts/install-qt-windows.py` and `tooling/linux-release/Dockerfile` install. CI runs `./scripts/verify.sh` on Linux and the platform lane on macOS and Windows,
then builds and qualifies the packages on native hosts. Cross-compilation alone is not
target acceptance.

## Validation

Pure Rust domain and parser tests stay separate from real-Git fixture tests, workbench
service tests, the remote client tests against the real helper (and over OpenSSH in
`scripts/verify_remote_workspaces.py`), QML lint and installed-package qualification. Race
tests cover session replacement, stale diff completion, mutation commit points, partial
bootstrap, shutdown and failed persistence.
