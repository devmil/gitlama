# Linux Flutter resize SDK

Linux products use `scripts/flutter.sh`, which selects the locked framework and the matching local engine/host for each build mode. macOS and Windows keep the normal pinned upstream SDK. The project opts in to the GTK resize-vsync policy only on native Wayland. The painted-buffer fix also avoids presenting an unpainted buffer to Wayland while replacing a resized EGL drawable. Frame constraints and GPU fences remain enabled.

The native view has a transparent backing so the GTK window, already updated from the active Meridian ground color, fills temporary gaps. This applies to the main window and adopted inspector windows. It is not Dart scene transparency or a new theme palette. Secondary plugin engines receive the painted-buffer fix but retain their plugin-selected pacing policy.

## GitHub Actions reuse

The Linux setup action caches the **built portable SDK and symbols**, keyed by the locked Flutter/DEPS/depot revisions, patch hashes, builder recipe, preparation/packaging scripts and runtime mode. App commits do not enter the key. An exact cache hit skips compilation; every restored archive is checksum- and manifest-verified in a fresh directory. A successful new SDK is cached immediately, before app tests, so an unrelated app failure does not discard the expensive build. Eviction or changed engine inputs requires a cold build. Debug and release use distinct keys. Desktop CI qualifies both SDK modes; release publication consumes the same locked release identity.

The SDK producer is pinned to Ubuntu 22.04 to retain GitLama's glibc 2.35 release baseline. The release container mounts only the verified overlay read-only. Packaging checks the bundled engine's byte identity and exports, repairs absolute build-time loader paths, and audits the release ELF requirements before archiving.

For a local product build use `scripts/flutter.sh build linux --release`. SDK preparation builds from source on a cache miss. Set `GITLAMA_LINUX_SDK_DIR` to an already installed, verified overlay and `GITLAMA_FLUTTER_FRAMEWORK_SDK` to its matching pinned framework to consume an existing SDK. Never replace FVM's stock engine files.

## Scope

The ProcessLama diagnostic separate-UI, geometry-coalescing and viewport-stretch preload hooks are not shipped by this SDK. This change contains the tested painted-buffer, opt-in GTK pacing and optional accessibility bridge patches, plus theme-matched fallback ownership. Those experimental scheduling changes require their own source/lifecycle/input qualification before deployment.
