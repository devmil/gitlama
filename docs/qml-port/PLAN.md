# GitLama Rust + Qt Quick port: plan and status

Goal: GitLama becomes a Rust + Qt Quick (QML) application with no Flutter left,
100% feature parity, as-close-as-possible visual/UX/motion parity, at least the
Flutter build's performance, the same release targets plus an Arch package,
and the same application identity and persisted data so users simply update.

Donor: the Flutter implementation at `origin/main` 7b78369e (v0.1.0-beta.68,
build 69). Templates: ProcessLama's port (`devmil/processlama` main, crates under
`rust-core/desktop`), MailLama's port, and Meridian for Qt Quick
(`meridian_ui` 2.1.0, `qml/Meridian`).

## Invariants (must hold at every merge)

- Application identity: `de.devmil.gitlama` (Linux desktop id / Wayland app id,
  macOS bundle id, Windows product), executable `gitlama`, product "GitLama".
- Persistence stays where Rust already keeps it: `storage::settings_default_path`,
  `view_cache_default_directory`, `recovery_default_directory`,
  `remote_pending_default_directory`, OS keyring entries of `hosting.rs`, the
  SSH trust store. The port calls the same functions; no new locations.
- `gitlama_application`, `gitlama_contract` and the remote helper are unchanged
  in behaviour, so the helper version in `rust-core/remote-helper/COMPATIBILITY`
  stays (desktop-only change). A needed change raises it per AGENTS.md.
- Generic Git behaviour lands in `devmil-git`, generic UI in `meridian_ui`
  (QML), never as local copies.

## Target layout

```text
rust-core/
  contract/ application/ remote-helper/   unchanged shared crates
  src/ (gitlama_core)                     desktop services; FRB facade becomes the
                                          plain Rust facade `api` (no FRB)
  desktop/workbench                       Qt-independent port of the Dart services
                                          and models (workspace, sessions, history,
                                          changes, inspector, hosting, updates ...)
  desktop/remote                          SSH transport + wire client (port of
                                          lib/repositories/impl/remote)
  desktop/qt                              qtbridge QObjects and item models
  desktop/app                             composition root, `gitlama` executable,
                                          platform hooks (C++/ObjC: toolbar, Sparkle)
qml/GitLama                               the UI
qml/Meridian                              vendored Meridian (scripts/sync-meridian.sh)
l10n/                                     app_en.arb, app_de.arb (moved from lib/l10n)
```

## Phases

1. Foundation: workspace, qtbridge toolchain, resource embedding, l10n
   generator, Meridian vendoring, boot to the startup/welcome screen with real
   settings. Remove Flutter runtime pieces (kept in Git history).
2. Workbench core: settings, workspace/tabs, repository session lifecycle and
   event drain, operation center, history pages, working copy/changes, diff.
3. Main UI: window chrome, toolbar + Compass, repo tabs, sidebar, history graph,
   changes pane, diff view, commit editor, inspector, status bar, palette.
4. Workflows: transfers, refs, stash, rebase/advanced rebase, conflicts,
   named snapshots, patch, archive, blame, power tools, integrations,
   extensions, hosting/review, clone, remote workspaces, inspection windows,
   CLI forwarding, updates, diagnostics, settings pages, shortcuts.
5. Platforms: native menus, drag and drop, macOS toolbar/Sparkle, Windows,
   Linux CSD; packaging (dmg, msi, AppImage, deb, rpm, tar.gz, Arch pkg), CI,
   release scripts, website.
6. Cut-over: parity audit, performance comparison, move the checkout from
   `Dev/Flutter/gitlama` to `Dev/Rust/gitlama`.

Status is tracked in `docs/qml-port/STATUS.md`; the parity inventory in
`docs/qml-port/parity-inventory.md`.
