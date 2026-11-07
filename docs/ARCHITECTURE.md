# GitLama architecture

Status: accepted direction. "Current composition" describes the code as it is; "Target layering" records the intended direction and which parts are in place.

## Stack and boundary

Use Flutter for the desktop presentation with a Rust native core. Flutter owns painting, semantics, input routing, focus, and presentation localization. Rust owns Git semantics, repository sessions, graph topology and layout, authoritative selection identities, operation coordination, persistence, and background work. Dart code depends inward: widgets on services, services on repository interfaces.

```text
Flutter panes and controls
    -> Dart services: observable immutable projections and typed commands
        -> Dart repository interfaces
            -> native repository implementations / generated FRB
                -> Rust application use cases and consumer-owned ports
                    -> Rust domain values
                    -> adapters -> devmil-git Repository / hosting / integrations -> installed Git or provider
```

There is one production native bridge, flutter_rust_bridge. Do not add a parallel C ABI or platform-channel Git API. Widgets cannot import generated bindings. Third-party Rust types never become the public product contract. Generated Rust and Dart code is committed and recreated by `scripts/generate-rust-bridge.sh`.

The Rust code is one Cargo workspace (`rust-core/Cargo.toml`, one lockfile) of four crates:

- `gitlama_contract` (`rust-core/contract/`): the bridge types (`Native*`, `CoreInfo`), plain data with no public functions or methods. flutter_rust_bridge reads it as a third-party input (`rust_input: crate::api,gitlama_contract`) and generates their Dart classes under `lib/rust/third_party/gitlama_contract/`; a `Default` impl carries a `/// flutter_rust_bridge:ignore` marker so it does not become Dart API.
- `gitlama_application` (`rust-core/application/`): the domain (`domain/`), the application layer (`application/` and the family modules) and the generated JSON wire adapter (`wire/`). Each family module re-exports its bridge types from the contract beside the behaviour that produces them. Its `image-codecs` feature (default; the desktop library enables it) decodes image diffs; `build.rs` embeds the release identity and the remote helper ID.
- `gitlama_core` (`rust-core/`, the library Flutter loads): the FRB facade (`src/api.rs` and the generated `src/frb_generated.rs`) and the desktop-only services (hosting, CLI forwarding, child processes, avatars).
- `gitlama-remote-helper` (`rust-core/remote-helper/`): runs the application crate headless on another computer, without the image codecs; it never depends on the desktop library.

## Current composition

`main.dart` installs framework/platform diagnostics and launches `AppLauncher`. Bootstrap initializes safe logging and an isolated `AppComponents` registry (`lib/di/app_components.dart`), which registers every production repository and its owning service in dependency order and exposes initialized services through the typed `AppRuntime`. The startup screen localizes loading, failure and retry in English/German. Inspector windows run a second, smaller composition root: `bootstrapInspectorWindow()` builds an `InspectorWindowComponents` registry and returns an `InspectorWindowRuntime`, and `InspectionWindowApp` shows its loading, failure and retry like the main launcher.

`ComponentRegistry` shares concurrent initialization, records construction order, cleans partial failures, and disposes constructed instances in reverse order. A disposer failure does not prevent later cleanup. Failed bootstrap retries use a new registry. Late successful startup after widget disposal immediately shuts down its runtime.

FRB's library loader is process-owned and shared across bootstrap attempts. It loads only the executable's bundled library. Native repository sessions, the hosting runtime and background jobs have explicit initialization, cancellation and bounded shutdown in Rust.

Remote workspaces reuse the same Dart mapping layer: `NativeRepositorySessionRepository` talks to the in-process core through the generated `RepositorySessionCalls` seam, and to the helper through its wire implementation; `RepositoryBackendRouter` (`repositories/impl`, registered as the `CompleteSessionBackend`) routes each session to this computer or to its connection's surface, which the remote workspace service publishes in a `RemoteSessionDirectory`; the remote adapter marks remote paths with their authority. Contracts that cross the bridge are generated or held by shared fixtures: enum conversions (`native_enum_mappers.g.dart` from `tooling/remote_wire/enum_mappers.json`), wire codecs (`tooling/remote_wire/generate.py`), stored settings names (`test/fixtures/settings_storage_names.json`) and conflict markers (`test/fixtures/conflict_markers.json`). `scripts/check_architecture.py` rejects positional enum mapping, repository contracts with more than one owning service, native implementations importing each other and, in Rust, a crate dependency against the layer order (contract, application, desktop library; the helper on the application only), a public function, inherent impl or unmarked `Default` in the contract, a bridge type the facade names through the application crate (FRB would make it opaque), any dependency on `crate::api` outside the facade, an application module depending on the wire adapter, the domain depending on anything above it, and the broken `hosting`/`hosting_runtime` and session-policy cycles returning.

The Rust core today:

- `application/src/domain/`: the mutation outcome (`MutationOutcome { committed, state, failure }`, kept uncertain end to end), the product failure taxonomy (`ProductFailure { category, detail }`, which every family failure enum maps into), path identity, `SessionKey`, branch facts, hosting identity rules, the session policy, the history filter limit and the generated product limits.
- `application/src/application/`: the session registry (`session.rs`: per-feature sub-states, one lookup through `RepositorySessions::session` and `with_session`, one place that dismisses every family's previews on close), every session-scoped use case and projection (staging, commit, discard, patch, restore, refs, history, inspection, diff, renderers, index lock, the operation center) and the session entry points of the family modules.
- Family modules in `application/src/` (`stash.rs`, `transfer.rs`, `history_operation.rs`, `rebase_operation.rs`, `advanced_rebase.rs`, `named_snapshot.rs`, `extensions.rs`, `integrations.rs`, `power_tools.rs`, `conflict.rs`, `clone.rs` with `credentials.rs` and `ssh_trust.rs`): each owns its mechanics, its `PreviewStore`, its settings section where it has one, and, for operations that stop at conflicts, its `InterruptedOperation`.
- Use cases register an `OperationIntent` where they start a changing command; the operation center reads it instead of the recorded arguments.
- The contract's `dto.rs` holds the session bridge types and the family types; the failure taxonomy mappings of every family, including the desktop-only ones (`desktop_families.rs`), live in the application crate. `api.rs` is a delegating wrapper per bridge function; `wire/` dispatches to the same application functions.

## Target layering

```text
widgets/screens -> services (workflows, one owner per state) -> repositories -> FRB / remote wire
  -> Rust api.rs and wire (translation only) -> application (sessions, use cases, projections) -> domain -> devmil-git
```

- Workflows (ref edits, transfers, history rewrites, conflicts, staging, commit, clone, remote connection) belong in services that return typed outcomes; widgets show dialogs and render state.
- Commands are evaluated and dispatched in one place from service-published context, not from mounted widgets.
- `api.rs` translates only; use cases live in application modules and mutations report one domain `MutationOutcome` (in place). Result payloads are still the bridge types in `gitlama_contract`, so a bridge field remains a wire field.
- Separate contract, application and adapter crates, so the helper depends only on the application crate (in place). `scripts/check_helper_compatibility.py` fingerprints the application and contract crates with the helper.
- Generic Git mechanics live in devmil-git (`rust-core/Cargo.toml` pins it); generic controls in `meridian_ui`.

## Directory responsibilities

| Path | Owner and allowed contents |
| --- | --- |
| `lib/app/` | Bootstrap, theme, shell and screens, root lifecycle |
| `lib/di/` | Dependency factories and lifecycle metadata |
| `lib/models/` | Immutable application-owned Dart DTOs, no native SDK types |
| `lib/services/` | Owning service per repository; projection state, command delivery |
| `lib/repositories/` | Boundary contracts; `impl/` translates FRB types |
| `lib/rust/` | Generated bridge (`api.dart`; bridge types under `third_party/gitlama_contract/`), no handwritten product logic |
| `lib/l10n/` | EN/DE strings and generated localization |
| `rust-core/src/api.rs` | FRB facade (`gitlama_core`): a delegating wrapper per bridge function |
| `rust-core/src/` (other modules) | Desktop-only services: hosting, CLI forwarding, child processes, avatars |
| `rust-core/contract/` | Bridge types both adapters carry (`gitlama_contract`); data only |
| `rust-core/application/src/domain/` | Domain values and rules; depends on nothing above it |
| `rust-core/application/src/application/` | Session registry, use cases and projections; never depends on an adapter |
| `rust-core/application/src/wire/` | Generated JSON codecs and dispatch for the remote helper |
| `rust-core/remote-helper/` | Headless helper crate for remote workspaces; depends on the application crate |
| `hook/` | Build and bundle the matching native target |
| `docs/design-system/` | Meridian design system: tokens, components, specimens, assets, behaviour specs and oracles, Flutter adaptation |
| `webfront/` | Static public website, separate from application targets |
| `packaging/` | Exact release artifact matrix and platform metadata |

Expose initialized product services through typed `AppRuntime` fields. Consumers select small immutable projections instead of subscribing the whole root to a mutable global model.

## Shared Repository integration

The normal native entry point is `devmil_git::Repository`, not `RepositoryDiscovery`, `GraphLoader` or hand-built read commands. Construct with `RepositoryOptions`, subscribe before `load()`, and project `RepositorySnapshot`/`RepositoryEvent` through application-owned FRB DTOs. Construction performs no discovery. Use `from_discovered` only when identity is already resolved by an earlier shared operation.

The shared model owns worker/watcher lifetime, refresh coalescing, duplicate pending reads, cache accounting and recorded Git execution. Application state still owns layout, selection, graph lane geometry, typed effects, mutation sequencing, confirmation, credentials and persistence. Shared hosting and external-tool APIs are separate entry points; hosting refresh scheduling remains application-owned.

Map `Snapshot` and `Resynchronize` into coherent replacement publications; a slow subscriber must not replay lost deltas. Map `ReadCompleted` to pending typed `ReadTicket` state. Tickets return `Arc<T>` or typed errors, not a guaranteed product revision envelope, so retain session/request identity and validate snapshot/query freshness at the adapter. Ticket drop releases a response; it is not proof of per-read child cancellation. `close()` and Drop cancel and join the worker, so perform teardown off the Flutter UI thread and measure its deadline rather than assuming it is nonblocking.

Use supported history, metadata, tree, path/range history, blame, reflog and commit detail/files/diff methods on the same handle. Reuse shared lower-level mechanics only for an identified facade gap, especially mutations and working-tree diff scopes. The inspected facade does not expose a universal mutation API. Coordinate mutations and refresh completion explicitly to prevent stale cached reads after a successful command.

Activity/wakeup callbacks run on the repository worker and must return promptly. A wakeup schedules event draining, not a UI call or synchronous wait. Keep private unredacted parser buffers native. Map RepositoryErrorKind and activity identity to safe product errors rather than treating the shared error message as safe localized text.

`rust-core/Cargo.toml` pins devmil-git to an exact revision; `scripts/shared_git_pin.py` describes local development against a devmil-git checkout.

## History inspector

`HistoryService` owns the graph: topology, selection, queries, branch filters, search and reflog. It announces each selected commit or comparison on `selections` and never reads a commit's diff. `InspectorService` (`lib/services/inspector/`) owns what the Detail pane shows: one `InspectorLocation` (target, scope, focus path, lens, line range, history entry, anchor), a browser-like Back/Forward stack and the reads behind each lens. A native session keeps one committed diff and one blame projection, so one session serves one inspector, and every navigation reloads them. `HistoryInspectorLink` connects the two: graph selections navigate the inspector, and targets reached through Back, Forward or a link select the graph.

`RepositorySessionService` is a facade over the session subsystem (`lib/services/session/`): `WorkspaceService` owns tabs, groups, navigation, the active session, the session lifecycle and event draining; each command family (working copy, activity, references, transfers, stashes, history mutations, rebase, restack, conflicts, named snapshots, extensions, integrations, power tools, patches, diff renderers) is a service over its own capability contract, and the Composer owns commits. The families reach sessions only through the workspace's `SessionScope`.

`InspectorView` (`lib/app/inspector/`) renders an inspector for an `InspectorHost`: the Detail pane (`PaneInspectorHost`) or an inspector window (`InspectionWindowApp`, which opens its own read-only session through `InspectorWindowSession` and reaches the main window through `InspectorRevealService`). A window of a repository on a remote host reads through the main window's connection: its `RemoteInspectionSessionRepository` sends the inspector's reads over the window channel `gitlama/remote-inspection` to the main window's `RemoteInspectionHostService`, which serves them on a helper session of the window's own and refuses every other call. Every file list (commit files, All files, history entries, Changes, conflicts and pull-request review) is built from `GitFileList` and `GitLamaFileRow`, and every file menu comes from the single catalogue in `lib/app/file_actions/file_actions.dart`. The [inspector spec](design-system/specs/inspector.md) defines the behaviour.

## Planned native contracts

Use application-owned `RepositoryId`, `WorktreeId`, `CommitId`, `OperationId`, and `RequestId` types. An OID is a full identity, never a shortened display hash or row index. Paths retain native bytes in Rust; presentation uses a safe display string and an opaque handle for operations. Avoid lossy UTF-8 round trips for filenames. Bridge integers must fit the Dart representation or use an explicit lossless encoding.

Every repository publication carries session generation, query revision, and publication sequence. Requests that can be superseded, including diff selection, graph queries, navigation reveal, and hosting searches, carry request identity. Dart discards stale results before mutating service state. Row indexes are viewport positions only. Retain scroll as stable identity plus intra-row offset.

Separate immutable state from exactly-once effects. Durable selection, repository health, operation state, and settings are snapshots. Copy, open-external, focus restoration, and navigation reveals are typed effects with identity and acknowledgement. A repeated request to reveal the same commit must still cause a reveal. A data revision is not an effect signal.

Errors use a closed product enum with structured bounded fields: unavailable Git, unsupported version, unavailable repository, authentication required, permission denied, conflict, stale precondition, cancelled, timeout, output limit, and internal failure. Unknown external variants map to a safe explicit fallback. UI localizes at the presentation boundary; neither SDK Debug output nor English error parsing is protocol.

## Scheduling and mutation safety

One GitLama native session owns a shared devmil_git::Repository handle for each worktree context. Repository owns its worker, watcher, refresh coalescing, recorded reads, immutable snapshots, request queue and bounded caches. GitLama must not implement another repository refresh loop or read cache. Serialize application index/ref/worktree mutations where their lock domains overlap; use shared refresh/reload to reconcile afterward. Verify desired read priority against the shared API and extend it upstream if needed. Cancel obsolete reads, then reject late publications by identity even when cancellation races. Never run Git or decode a large diff on Flutter's UI isolate.

An operation includes intent, preconditions, cancellation handle, progress, activity identity, commit point, final outcome, and optional refresh degradation. Before a destructive command, resolve its exact identities and preview scope. Revalidate the index/worktree/ref state at execution. Pass command arguments as an array through devmil-git rather than interpolating a shell command. User-configured custom shell commands form a separate explicit capability with preview and consent.

Once Git confirms a mutation, later cancellation or failed refresh cannot turn it into “not applied.” Preserve success and report refresh degradation separately. An uncertain outcome requires reconciliation before retry. Network operations expose bounded progress and authentication through an owned adapter. Credentials stay native and out of ordinary activity, settings, and fixtures.

Activity captures actual command intent/output through bounded redaction. The visible log remains useful, but secrets and authenticated URLs are removed. User content such as paths is shown only where necessary in the deliberately user-visible activity view; safe operational diagnostics use fixed event codes and no raw paths or exceptions. Export requires a separate privacy review.

## Graph and diff design

Rust calculates lanes, topology, ancestry lighting, occupied graph ink, filtering, and stable row projections. Flutter uses virtualized fixed-extent rows and custom painters over bounded viewport data. Metadata measurement belongs in the Flutter presentation adapter, which provides measured widths for the shared geometry contract. The painter never infers parentage from neighboring widgets. Preserve G-LANE-01 and all graph layout fixtures.

Graph topology and summaries have separate bounded loading policies. Full topology can serve complete navigation/filter semantics without eagerly creating widgets or hydrating all commit messages. Anchor publications by OID; preserve offscreen continuation geometry. Metadata remains pinned and hit-tested separately from clipped graph ink. Never add the obsolete graph-column preferences.

Diff/staging operates on revision-scoped hunk/line identities with original bytes retained natively. Stage/unstage and discard are different commands with different safety rules. Validate patch preconditions, line endings, encoding, missing newline, renames, binary files, and externally changed index content. Highlighting and image decoding are bounded background jobs. Rendering can fall back to a clear large/binary-file state without fabricating text.

## Persistence and platform integration

Rust owns versioned settings and repository workspace persistence. Use atomic write-and-replace, explicit corruption reporting, safe migrations, and test interrupted writes. App-wide data includes theme/density/geometry/shortcuts; repository data includes filters, selected identities, scroll anchors, and drafts. Credentials belong in the OS secure store. Unreadable storage is distinct from absent data and never triggers automatic destructive reset.

Git is external, not libgit2. Discover and validate it with devmil-git. Finder's PATH differs from a terminal; resolve child-process PATH on a worker and cache it. Do not call a process-reexec environment helper after Flutter creates threads. Windows command quoting and cancellation must preserve process-tree ownership. Linux packages require GTK/Flutter dependencies rather than Qt deployment libraries.

The macOS Git client needs access to arbitrary selected repositories and installed tools. Use a non-App-Store, unsandboxed desktop distribution; hardened runtime, signing and notarization remain release requirements. App Store sandbox support is not assumed. Desktop launch, file-open integration, shortcuts, clipboard and external tools each need target tests before shipping.

## Build and supply chain

Pin Flutter with `.fvmrc`, Rust with `rust-toolchain.toml`, Dart packages with `pubspec.lock`, Rust packages with `Cargo.lock`, and the shared crate with an immutable Git revision. The native hook maps host target triples explicitly, uses Cargo `--locked`, and bundles platform-appropriate filenames. Register all Rust sources and manifests as hook inputs so edits invalidate the native build. Cross-compilation alone is not target acceptance.

CI verifies the same local command, then builds on native desktop hosts. Shared libraries are public and fetched anonymously at their pinned revisions. A populated cache can support offline builds.

## Validation and architectural risks

Keep pure Rust domain/parser tests separate from real-Git fixture tests, widget/controller tests, native bridge integration, and installed-package qualification. Generated-binding imports are guarded. Add race tests for session replacement, stale diff completion, mutation commit points, partial bootstrap, shutdown, and failed persistence as the corresponding subsystem lands.

Early technical proofs must measure a 100k-commit graph, heavy diff scrolling, 130% text scale, Linux fractional scaling, Windows key traversal, and cold restart. Flutter replacing Qt does not automatically meet QSpline's latency or accessibility guarantees. Reject a renderer architecture that requires unbounded bridge messages or per-commit widget retention.
