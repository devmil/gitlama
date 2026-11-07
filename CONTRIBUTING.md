# Contributing to GitLama

Thank you for helping. Bug reports, focused fixes and well-scoped features are
welcome. For a larger change, open an issue first so we can agree on the
direction before you invest time.

## Before you start

- Read [the architecture](docs/ARCHITECTURE.md) and the [decision records](docs/adr/).
  [AGENTS.md](AGENTS.md) holds the working rules for every change, for humans and
  coding agents alike.
- Generic Git behaviour belongs in [devmil-git](https://github.com/devmil/devmil-rust-git),
  generic controls and tokens in [meridian_ui](https://github.com/devmil/meridian_ui).
  Change them there first, then move GitLama's pinned revision.
- Every visible string goes into both the English and the German ARB catalog.
- Never log user content, credentials, private paths, URLs or raw external errors.

## Making a change

1. Build from source as described in the [README](README.md).
2. Add focused tests for the behaviour you change.
3. Run `./scripts/verify.sh`; it runs the same gate as CI.
4. For a user-visible change, add an entry to both `CHANGELOG.md` and
   `RELEASE_NOTES.md` under the pending section.
5. If your change can alter what the remote helper accepts, returns or does,
   raise its compatibility version as described in
   [AGENTS.md](AGENTS.md#remote-helper-compatibility).

Keep pull requests small and explain the reason for the change. By contributing,
you agree that your contribution is licensed under the [MIT License](LICENSE).
