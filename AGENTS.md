# GitLama agent instructions

## Orientation

GitLama is a desktop Git client: Flutter presentation over a Rust core that runs
the installed Git through `devmil-git`. Read [the architecture](docs/ARCHITECTURE.md),
the [decision records](docs/adr/) and [the design system](docs/design-system/README.md)
before changing product behaviour. Remote workspaces have their own
[architecture and protocol](docs/remote-workspaces/README.md).

## Remote helper compatibility

Hosts keep the remote helper they have installed until GitLama needs a new
helper version. A client connects only to a helper with its own ID, the
`version` in `rust-core/remote-helper/COMPATIBILITY`. Getting the version
right is part of every change:

- **Raise the version** for any change to what the helper accepts, returns or
  does: protocol frames, wire types or codecs, the remote surface, capability
  rules, write validation, receipts or reconciliation, the session policy, and
  any change in `gitlama_application` or `gitlama_contract` (the crates the
  helper runs) that alters a result or effect the helper produces for a
  remote call (Git arguments, parsing, status, history, diff,
  staging, commit, refs, stash, transfer, discard). A new client that needs a
  helper behaviour also needs a new version.
- **Keep the version** for changes the helper does not run or that cannot
  change its answers: Dart-only work, desktop-only Rust (`gitlama_core` in
  `rust-core/src`, the application's `image-codecs` engine), tests, docs and
  refactors with identical output.
- When unsure, raise it. A needless raise costs one installation per host; a
  missed raise connects clients to helpers that behave differently.
- `scripts/check_helper_compatibility.py` (part of `verify.sh`) fingerprints
  the helper sources, the application and contract crates and the remote
  surface. When they change it fails until the version is raised; then run
  `python3 scripts/check_helper_compatibility.py --record`. A fingerprinted
  change that cannot alter the helper (tests, identical-output refactors)
  keeps the version with `--record --keep-version`: that judgment is yours, as
  is a devmil-git pin move (`--keep-shared-git`).
- Say in the changelog entry when a change raises the helper version, so users
  know hosts will receive a new helper.

## Architecture

- Widgets and screens depend on service contracts.
- Services own workflows and observable state.
- Each repository owns one persistence, plugin, network, or native boundary and
  has one owning service.
- Register production implementations only in `lib/di/app_components.dart`.
- Expose initialized, typed services through `AppRuntime`; widgets must not use
  the component registry as a service locator.
- A failed bootstrap disposes partial work. Retry always creates a fresh
  composition root.

## Shared Git library

When a GitLama feature needs reusable Git behavior, prefer implementing the
generic capability in `devmil-git` and consuming its committed API here. Check
its current API and tests, land the change there first, then move the pinned
`rev` of `devmil-git` in `rust-core/Cargo.toml`, update `rust-core/Cargo.lock`
and verify both sides. While developing both together, point Cargo at a local
checkout with a `[patch]` entry for the devmil-git URL in your user-level
`~/.cargo/config.toml` (see `scripts/shared_git_pin.py`); never commit a path
dependency or patch. Keep GitLama
navigation, presentation and workflow policy in this repository.

## Shared code placement

Generic Git behaviour belongs in `devmil-git`; generic controls, tokens and UI
behaviour belong in `meridian_ui`. This applies to existing code as well as new
work. When a change touches or reveals such code living in GitLama (a Git
argument builder, parser or process helper; a reusable widget, layout rule or
token), move it to the shared library, publish it there and consume it here
instead of extending the local copy. Only GitLama-specific policy,
git-domain presentation and workflow orchestration stay in this repository.

## Design system

Build UI from the shared `meridian_ui` package (pinned by Git commit) and read
[the design system](docs/design-system/README.md) for what stays in
GitLama. When a feature needs a generic control, token or behaviour
Meridian lacks, add it to `meridian_ui` with a guideline, gallery entry and
test, land it there, and move the pin; keep git-domain components
here. `scripts/check_meridian_usage.py` rejects Material controls, local
copies of Meridian components and unnamed sizes.

## Dialogs

Use `MeridianDialog` (or `MeridianDialogSurface` for a custom layout) with
`showMeridianDialog` for every application dialog. Shadow, surface, spacing and
scrim come from meridian_ui; a dialog opened from another keeps one scrim.

## Desktop menus

- Render every context menu and action/overflow menu with the operating system's
  native menu UI through [the shared presenter](lib/widgets/native_menu.dart).
  Meridian menus (`MeridianSelect`, `MeridianMenuAnchor`, split toolbar
  buttons) and text field menus reach it through the `MeridianMenuPresenter`
  installed at both app roots.
  This applies to right-click menus, sidebar actions and toolbar menus on every
  supported desktop platform. Use `nativeTextContextMenuBuilder` for text
  editing and selectable-text menus.
- Do not use Flutter `PopupMenuButton`, `showMenu`, `MenuAnchor`, or a custom
  painted overlay for these menus. A dependency's Flutter fallback does not
  satisfy the native-menu requirement. Searchable form pickers are separate
  controls, not action menus.
- Preserve enabled/checked states, localized labels, keyboard invocation,
  dismissal and invoking focus. Test menu models and the platform boundary;
  claim native appearance only on platforms actually checked.

## Safety

- Never log user content, credentials, private paths, URLs, or raw external
  exceptions. Use stable event and failure codes.
- Put every visible string in the English and German ARB catalogs.
- Keep durable product data out of preferences.
- Do not claim native, physical-device, signing, accessibility, or live-service
  acceptance unless that check actually ran.

## Required verification

Run `./scripts/verify.sh` before finishing. Add focused tests for lifecycle,
persistence, native boundaries, and non-trivial behavior. Never remove or skip
tests merely to make verification pass.

## Release entries

For each user-visible feature or fix, add an entry to both `CHANGELOG.md` and
`RELEASE_NOTES.md` in the appropriate pending section before finishing the
change. Use `Unreleased Beta` for current beta fixes. Keep the changelog
specific and the release notes readable for users. Internal-only and docs-only
changes need no product release entry. Release preparation promotes the
selected pending section; its changelog fallback is recovery, not the normal
way to write release notes. See [release preparation](docs/RELEASE.md).

## User-controlled diagnostics

Use the shared `devmil_logging` library and its diagnostic contract.
Keep safe recent history bounded and private, detailed capture explicitly
session-limited, and export behind preview and an explicit Save/Share action.
Never include credentials or arbitrary private product content in any mode.
Use reviewed static event codes and numeric fields for new diagnostic sites.
See [diagnostic adoption](docs/diagnostics.md). Earlier logging restrictions
continue to exclude private content; they do not prohibit safe diagnostic
history or user-controlled export.
