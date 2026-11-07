# ADR 0004: In-app updates

- Status: accepted
- Date: 2026-09-28

## Context

GitLama first shipped without update checking, downloading or installation. It publishes frequent beta releases to a signed public index, and users had no way to learn about a new release from inside the application.

## Decision

macOS uses Sparkle 2, pinned to one resolved Swift package revision. The runner starts the updater when Dart configures it with the feed and the release channel. Sparkle checks once a day after the user agrees, shows its own windows, verifies the package and installs it.

Linux and Windows have no installer integration. When the user checks, the application reads the public release index over HTTPS, compares build numbers and offers the downloads page. It downloads and opens nothing from the index: the page address is fixed in the application. The request follows no redirect and accepts at most 1 MiB.

The release channel is a setting. Without a choice it follows the installed build, so a prerelease build follows beta. Beta subscribers also receive stable releases.

One Ed25519 key signs both the release index and the macOS update package. The public key in `release/northspline-release-ed25519.pub` is the value of `SUPublicEDKey`. The release workflow signs the DMG with OpenSSL 3 and stores the signature in the signed index as `update_signature`. The website step renders `webfront/appcast.xml` from the verified index, so the feed never holds a package the index does not.

The installed version and build come from the canonical `VERSION` file, compiled into the native core.

## Consequences

- A release is offered to macOS users only after the GitHub release and the signed index agree.
- Releases published before this decision have no update signature and never enter the appcast.
- A debug run and a launch with `GITLAMA_PROFILE_ROOT` have no updater, so tests and package qualification leave Sparkle's user defaults alone.
- The Linux and Windows check trusts HTTPS and the fixed downloads page rather than the index signature. Verifying the signature in the application becomes necessary before it downloads or installs anything there.
- Rotating the release key also rotates the update key and needs a release signed with the old key that carries the new one.

## Rejected alternatives

- A separate Sparkle key: a second secret to provision and rotate, with no separation benefit while both keys live in the same vault item and sign the same release.
- Sparkle's `sign_update` tool: it ties signing to the macOS build tree. OpenSSL produces the identical signature on the runner that already signs the index.
- Background checks on Linux and Windows: they add unrequested network traffic for a result the user must act on manually.
