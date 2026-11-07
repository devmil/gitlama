# Linux rounded-window rendering — 2026-10-05

The Linux main window now uses GTK3 native rounded borders around a rectangular
accelerated Flutter surface, replacing the libhandy offscreen content mask.
The 8px smooth curve is kept outside Flutter by 2px horizontal/3px vertical
floating insets. Shadows, native resize edges and integrated app window controls
remain. Maximized, tiled, fullscreen and solid-CSD states remove those insets.

The existing caption channel sends the active Meridian ground as ARGB32 to a
window-owned GTK CSS provider. Updates are coalesced for unchanged colors and
stale deferred callbacks are discarded. The native method validates the ARGB32
payload. Other platforms retain their current window setup.

Build and distribution dependencies no longer require or bundle libhandy.
Rust build-profile selection was already correct and was left intact.

## Completed checks

- Native accelerated-content fixture compiled with warnings treated as errors.
- Adwaita light/dark at 1× and 2×: opaque rectangular GL content, smooth
  transparent outer corners, exact floating insets, native background updates,
  resize, maximize/restore, all tiled classes, solid CSD, fullscreen/restore.
- Caption regression: initial light color, no duplicate same-theme update,
  dark color update, and existing platform/window-control behavior.
- Full scripts/verify.sh passed: analysis, 661 Flutter tests, Rust tests, package tests and architecture/design/plan checks.

## Performance scope

ProcessLama's matched wrapper experiment averaged 32.43% with libhandy and
18.35% with the selected native border, using the same optimized Rust core.
Its final release app averaged 17.85% across two cold launches. This establishes
the mechanism on that workload; no equivalent CPU percentage is claimed for
Gitlama, whose rendering and application workloads differ.

The production Linux release build succeeded with the pinned Flutter 3.47.5 SDK.
The bundled Rust library matched the Cargo release output byte-for-byte; no
kernel_blob.bin or libhandy was bundled. A copied bundle cold-launched outside
the checkout with fresh profile/runtime/XDG roots. Every ELF dependency resolved;
/proc maps verified the engine, Dart AOT and optimized core loaded from that
bundle. The app stayed running until the probe terminated its process group.

Optimized core SHA-256: `436030715c5faea1474a3ab10f95939d6f91f37960cf1a786e44a370a630a4a5`.
