# GitLama

GitLama is a desktop Git client for macOS, Linux and Windows, built with
Flutter and Rust. It works with the Git you already have installed: your
configuration, hooks, filters, credential helpers and Git LFS keep working as
they do on the command line.

It opens several repositories side by side and keeps their history, status and
references live. Commands are previewed before they run, and long operations
show progress where you started them. Remote workspaces let you operate a
repository on another computer over SSH.

Downloads, release notes and screenshots are on the
[website](https://devmil.de/gitlama/). Signed packages are attached to every
[GitHub release](https://github.com/devmil/gitlama/releases).

## Open from a terminal

On macOS, open a repository in GitLama with:

```sh
open -a "GitLama.app" "/path/to/repository"
```

GitLama opens the repository after startup, or in the running instance. Multiple folder paths open in source order. Invalid repositories use the normal repository-open error state.

The application executable also accepts a single path or `--open <path>` on desktop platforms and forwards it to the running instance.

## Build from source

You need the Flutter version pinned in `.fvmrc` ([FVM](https://fvm.app) picks it
up automatically), Rust 1.97.1 (`rust-toolchain.toml`) and the desktop toolchain
of your platform (Xcode, Visual Studio with C++ desktop tools, or a Linux C/C++
toolchain with GTK 3 development files). Then run:

```sh
flutter pub get --enforce-lockfile
./scripts/verify.sh
flutter run -d macos
```

Use `-d linux` or `-d windows` on those hosts. The native-assets hook builds the
Rust core automatically. After a Rust change, fully stop and restart the app.

Bridge regeneration requires `flutter_rust_bridge_codegen` 2.13.0-beta.5:

```sh
./scripts/generate-rust-bridge.sh
```

GitLama builds on three libraries from the same author, each pinned to an exact
commit: [devmil-git](https://github.com/devmil/devmil-rust-git) (Git
execution and repository models), [meridian_ui](https://github.com/devmil/meridian_ui)
(the design system) and [devmil-logging](https://github.com/devmil/devmil-logging)
(private, user-controlled diagnostics).

## Documentation

- [Architecture](docs/ARCHITECTURE.md) and [decision records](docs/adr/)
- [Design system](docs/design-system/README.md)
- [Remote workspaces](docs/remote-workspaces/README.md)
- [Diagnostics](docs/diagnostics.md) and [crash symbolication](docs/CRASH_SYMBOLICATION.md)
- [Packaging](docs/PACKAGING.md) and [releases](docs/RELEASE.md)
- [Contributing](CONTRIBUTING.md) and [security](SECURITY.md)

Preview the website with `python3 -m http.server 4173 --directory webfront`.

## License

GitLama is released under the [MIT License](LICENSE). Third-party components
keep their own licenses; see [third-party notices](THIRD_PARTY_NOTICES.md).
