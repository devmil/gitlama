# GitLama

GitLama is a desktop Git client for macOS, Linux and Windows, built with
Rust and Qt Quick. It works with the Git you already have installed: your
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

You need Rust 1.97.1 (`rust-toolchain.toml`), Qt 6.11 with Qt Quick (`qmake6` on
the `PATH`, or `QMAKE` pointing at it) and the C/C++ toolchain of your platform
(Xcode, Visual Studio with C++ desktop tools, or a Linux toolchain with
pkg-config and OpenGL headers). Then run:

```sh
./scripts/verify.sh
./scripts/run-dev.sh
```

`run-dev.sh` builds the application and loads the QML from the checkout, so a
QML change needs only a restart; `--release` builds an optimized binary. Set
`GITLAMA_PROFILE_ROOT` to run with a separate profile beside an installed
GitLama. [Packaging](docs/PACKAGING.md) builds the release artifacts.

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
