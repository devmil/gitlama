# Packaging and delivery

## Required target matrix

`packaging/targets.json` is the machine-readable target matrix.

| Native host | Required artifact | Minimum |
| --- | --- | --- |
| macOS ARM64 | DMG containing GitLama.app | macOS 13.0, Git 2.39 |
| Windows x64 | MSI | Windows 10 1809, Git 2.39 |
| Linux x64 | AppImage, DEB, RPM, portable tar.gz | glibc 2.35, Git 2.39 |

macOS x64 is a build-hook development target, not an added release promise. Linux ARM64 and Windows ARM64 are not in the published set. Flutter may impose additional GPU, GTK, SDK or system requirements; validate them before publishing minimum-system claims.

## Package tooling

`python3 scripts/package.py FORMAT` builds one candidate on its native host. `FORMAT` is exactly one of `dmg`, `msi`, `AppImage`, `deb`, `rpm` or `tar.gz`; the host and architecture must match `packaging/targets.json`. Every format uses the two-line `VERSION` file and the closed filename contract in `scripts/lib/package_contract.py`. `--skip-build` reuses a release tree, `--output-dir` selects the candidate directory, and an existing exact filename stops the build unless the operator supplies `--replace`.

The macOS builder copies the release app into a private staging directory, thins every Mach-O payload to ARM64, rejects a payload without an ARM64 slice, and verifies the resulting code signature. An unsigned local candidate receives one coherent ad-hoc signature without hardened runtime. `--sign` applies the configured Developer ID identity to the app and DMG. `--sign --notarize` also submits, staples and validates the DMG. Signing configuration comes from protected environment variables or the ignored `.env.signing`. The release workflow reads the Developer ID certificate and the Apple notary API key from repository secrets (see [release preparation](RELEASE.md#credentials)). It imports the certificate into a disposable keychain, prefers the decoded API key over a stale local profile name, and deletes the keychain and decoded files on every exit path. No credential value is stored in Git.

`scripts/qualify-macos-package.py` mounts the DMG read-only outside the build tree. It checks identity, version, minimum OS, legal assets, the Applications link, ARM64-only Mach-O payloads, dynamic dependencies, code signature and optional notarization. It loads the extracted Rust bridge, cold-starts the real executable twice with a repository whose path contains spaces and Unicode, and proves that the app stays open when Git is absent. Use `--require-signature --require-notarization` for a publication candidate.

Target launch harnesses isolate GitLama state with absolute `GITLAMA_PROFILE_ROOT` and owner-only `GITLAMA_RUNTIME_DIR` directories. They leave the process home and shared XDG directories unchanged. Relative product-profile or runtime overrides fail closed.

Windows has a GitLama-specific UpgradeCode and component GUIDs. Its MSI ProductVersion is `major.minor.globalBuild`, which gives every stable or prerelease build a unique Windows Installer ordering. The full SemVer marketing version and build remain separate MSI properties and executable resources. Same-version replacement and downgrade are rejected. `scripts/validate-windows-installer.ps1` validates WiX metadata, installs under a path with spaces, loads the packaged native bridge, checks PE resources/icon/Flutter assets, performs two cold starts and missing-Git startup, tests upgrade and downgrade when a previous MSI is supplied, then uninstalls while retaining user configuration.

Linux native packages install the full Flutter/Rust bundle under `/usr/lib/gitlama`, a launcher under `/usr/bin`, desktop entry, hicolor icon and legal inventory. AppImage carries the same system layout and a relative `AppRun`. The portable tarball has a top-level `gitlama` directory plus licenses and uses sorted entries, fixed ownership and `SOURCE_DATE_EPOCH` for reproducible bytes. Debian prereleases use `~`; RPM prereleases use a `0.` release prefix. `scripts/qualify-linux-packages.py` safely extracts all four artifacts, proves application/native payload hashes match, loads the packaged bridge, scans for build paths, resolves ELF dependencies, enforces the declared GLIBC 2.35 symbol ceiling and can launch each payload under Xvfb.

For a repeatable local x86_64 baseline run, start Docker or Podman and execute `scripts/qualify-linux-local.sh`. Set `GITLAMA_CONTAINER_ENGINE` to choose the engine explicitly. The harness stages the current GitLama tree (Cargo fetches the pinned devmil-git revision), reads Flutter from `.fvmrc`, builds in a pinned Ubuntu 22.04 image with that SDK plus Rust 1.97.1 and Git 2.39.5, creates all four formats, runs the full qualifier under x86_64 emulation and copies candidates to `dist` only after every gate passes. The run does not replace physical X11, Wayland, fractional-scale, GPU, input or assistive-technology checks.

## Build and runtime contract

Pin the native Rust target before building. Linux needs C/C++ toolchain, CMake, Ninja, pkg-config, GTK3 development libraries and Flutter desktop prerequisites. Windows needs Visual Studio C++ desktop tooling, Windows SDK, CMake, Git, Rust MSVC target and WiX. macOS needs Xcode/command-line tools and Rust Apple target. Packaging tools are additional prerequisites, not silently installed as system mutations.

After packaging, install or extract outside the source/build tree. Remove development library overrides. Launch through Finder, the Start menu, `AppRun` or the installed desktop entry, then run the native handshake against the extracted core. Cold-start twice so a loaded older library cannot mask a bad rebuild. Qualification records belong under ignored `dist/qualification/`; copy a bounded, sanitized result into the package evidence document.

Typical target commands are:

```text
python3 scripts/package.py dmg --sign --notarize
python3 scripts/qualify-macos-package.py dist/GitLama-*-macos-arm64.dmg --require-signature --require-notarization

./scripts/qualify-linux-local.sh

# Native Linux-host equivalent:
python3 scripts/package.py AppImage
python3 scripts/package.py deb --skip-build
python3 scripts/package.py rpm --skip-build
python3 scripts/package.py tar.gz --skip-build
python3 scripts/qualify-linux-packages.py dist --launch-seconds 4

python scripts/package.py msi
powershell -File scripts/validate-windows-installer.ps1 -MsiPath dist/GitLama-*-windows-x86_64.msi -OutputPath dist/qualification/windows-x86_64.json
```

## Release transaction

1. Validate clean candidate source, VERSION, Dart/Rust metadata and Unreleased notes.
2. Prepare one immutable version/build tag. Retry a failed target without changing it.
3. Build all six artifacts on target hosts with verified toolchains and scoped dependency access. Recover existing annotated tags from original retained bytes; never rebuild replacement bytes under an existing tag.
4. Apply mandatory macOS signing/notarization. Windows signing is optional when unconfigured; configured signing must succeed and verify without unsigned fallback. Keep credentials protected.
5. Run package launch/load, installation and integrity checks. Produce hashes, sizes and exact target metadata.
6. Publish the complete required artifact set as immutable GitHub release assets. Reject partial or mismatched sets.
7. Sign release metadata, retaining five stable and five beta releases. Verify client size and download bounds against actual artifacts.
8. Download every published asset again and compare it with the signed size and digest. Update website/channel pointers only afterward. Existing assets with different bytes stop publication.
9. Verify downloaded public bytes, signatures, links and release notes. Published bytes/tags are immutable; fixes require a new build.

The release workflow `.github/workflows/release.yml` implements this transaction; [release preparation](RELEASE.md) documents the two inputs and retry behavior. The public key is versioned configuration; private keys stay in the protected secret store. Website publication and update availability cannot be inferred from a local package build. In-app updates follow [ADR 0004](adr/0004-in-app-updates.md). Physical qualification remains separate from routine publication.

## External gates

Native Linux and Windows build/load/install; minimum-system compatibility; signed macOS Finder launch; accessibility/input/GPU checks on each desktop; code-signing and notarization identities; public domain and mirror ownership; upgrade/downgrade and beta-to-stable behavior. Record evidence separately for each. A package script existing is not proof its target passed.
