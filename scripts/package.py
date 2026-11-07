#!/usr/bin/env python3
"""Build one unsigned native package from a complete Flutter release bundle."""

from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import re
import os
from pathlib import Path
import platform
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile

try:
    from .lib.package_contract import (
        TARGETS,
        Version,
        artifact_name,
        fpm_source_date_epoch,
        REMOTE_HELPER_TARGETS,
        RemoteHelperTarget,
        remote_helper_archive_name,
        remote_helper_id,
        remote_helper_metadata_name,
        source_date_epoch,
    )
except ImportError:
    from lib.package_contract import (
        TARGETS,
        Version,
        artifact_name,
        fpm_source_date_epoch,
        REMOTE_HELPER_TARGETS,
        RemoteHelperTarget,
        remote_helper_archive_name,
        remote_helper_id,
        remote_helper_metadata_name,
        source_date_epoch,
    )


ROOT = Path(__file__).resolve().parent.parent
PLATFORM_BY_SYSTEM = {"Darwin": "macos", "Linux": "linux", "Windows": "windows"}
ARCHITECTURE_BY_MACHINE = {
    "aarch64": "arm64",
    "arm64": "arm64",
    "AMD64": "x86_64",
    "x86_64": "x86_64",
}


def run(*arguments: object, cwd: Path = ROOT, environment: dict[str, str] | None = None) -> None:
    subprocess.run(
        [str(argument) for argument in arguments],
        cwd=cwd,
        env=environment,
        check=True,
    )


def output(*arguments: object, cwd: Path = ROOT) -> str:
    return subprocess.check_output(
        [str(argument) for argument in arguments],
        cwd=cwd,
        text=True,
    ).strip()


def require_file(path: Path, label: str) -> None:
    if not path.is_file():
        raise RuntimeError(f"{label} is missing")


def require_release_bundle(platform_name: str) -> Path:
    if platform_name == "macos":
        bundle = ROOT / "build/macos/Build/Products/Release/GitLama.app"
        require_file(bundle / "Contents/MacOS/GitLama", "macOS executable")
        require_file(
            bundle / "Contents/Frameworks/gitlama_core.framework/gitlama_core",
            "bundled Rust framework",
        )
        require_file(
            bundle
            / "Contents/Frameworks/App.framework/Resources/flutter_assets/NOTICES.Z",
            "Flutter runtime license registry",
        )
        return bundle
    if platform_name == "windows":
        bundle = ROOT / "build/windows/x64/runner/Release"
        require_file(bundle / "gitlama.exe", "Windows executable")
        require_file(bundle / "gitlama_core.dll", "bundled Rust library")
        require_file(bundle / "data/flutter_assets/AssetManifest.bin", "Flutter asset manifest")
        require_file(bundle / "data/flutter_assets/NOTICES.Z", "Flutter runtime license registry")
        return bundle
    bundle = ROOT / "build/linux/x64/release/bundle"
    require_file(bundle / "gitlama", "Linux executable")
    require_file(bundle / "lib/libgitlama_core.so", "bundled Rust library")
    require_file(bundle / "data/flutter_assets/AssetManifest.bin", "Flutter asset manifest")
    require_file(bundle / "data/flutter_assets/NOTICES.Z", "Flutter runtime license registry")
    return bundle


REMOTE_HELPER = "gitlama-remote-helper"
REMOTE_HELPER_LIMIT = 64 * 1024 * 1024


def remote_helper_destination(bundle: Path, platform_name: str,
                              target: str = "linux-x86_64") -> Path:
    """Where the application looks for the helper it installs on hosts of ``target``."""
    if platform_name == "macos":
        return bundle / "Contents/Resources/remote-helper" / target
    if platform_name == "windows":
        return bundle / "remote-helper" / target
    return bundle / "lib/remote-helper" / target


def expected_source_commit(environment: dict[str, str]) -> str | None:
    commit = environment.get("GITLAMA_SOURCE_COMMIT")
    if not commit and (ROOT / ".git").exists():
        commit = output("git", "-C", ROOT, "rev-parse", "HEAD")
    return commit if commit and re.fullmatch(r"[0-9a-f]{40}", commit) else None


def bundle_remote_helper(bundle: Path, platform_name: str, environment: dict[str, str],
                         *, developer_id: bool = False) -> bool:
    """Places the verified remote helpers of this exact source commit and helper compatibility
    version into the bundle, one per
    host platform.

    The inputs are the archives and metadata written by scripts/package_remote_helper.py in
    ``GITLAMA_REMOTE_HELPER_DIR``. Releases set ``GITLAMA_REQUIRE_REMOTE_HELPER=1`` and then
    need every platform; local candidates may omit helpers, and the application then offers
    manual setup for those hosts. With ``developer_id`` a macOS package signs its macOS helpers
    with the Developer ID before recording their digests: notarization inspects every Mach-O
    file of the app.
    """
    directory = environment.get("GITLAMA_REMOTE_HELPER_DIR")
    required = environment.get("GITLAMA_REQUIRE_REMOTE_HELPER") == "1"
    if not directory:
        if required:
            raise RuntimeError("this release requires the remote helpers in GITLAMA_REMOTE_HELPER_DIR")
        return False
    version = Version.read(ROOT / "VERSION")
    bundled = False
    for target in REMOTE_HELPER_TARGETS:
        archive = Path(directory) / remote_helper_archive_name(version, target.name)
        if not archive.exists() and not required:
            continue
        _bundle_remote_helper(bundle, platform_name, environment, version, target,
                              developer_id=developer_id and target.platform == "macos")
        bundled = True
    return bundled


def _bundle_remote_helper(bundle: Path, platform_name: str, environment: dict[str, str],
                          version: Version, target: RemoteHelperTarget, *,
                          developer_id: bool = False) -> None:
    directory = Path(environment["GITLAMA_REMOTE_HELPER_DIR"])
    archive = directory / remote_helper_archive_name(version, target.name)
    metadata_file = directory / remote_helper_metadata_name(version, target.name)
    require_file(archive, f"remote helper archive for {target.name}")
    require_file(metadata_file, f"remote helper metadata for {target.name}")
    metadata = json.loads(metadata_file.read_text(encoding="utf-8"))
    archive_bytes = archive.read_bytes()
    commit = expected_source_commit(environment)
    if (
        metadata.get("schema_version") != 1
        or metadata.get("kind") != "gitlama-remote-helper"
        or metadata.get("version") != version.marketing
        or metadata.get("build") != version.build
        or metadata.get("target") != target.triple
        or metadata.get("file") != archive.name
        or metadata.get("bytes") != len(archive_bytes)
        or metadata.get("sha256") != hashlib.sha256(archive_bytes).hexdigest()
    ):
        raise RuntimeError("remote helper metadata does not describe this release archive")
    if commit is None or metadata.get("source_commit") != commit:
        raise RuntimeError("remote helper was built from a different source commit")
    build_id = remote_helper_id(ROOT)
    if metadata.get("build_id") != build_id:
        raise RuntimeError("remote helper has another compatibility version")
    with tarfile.open(archive, "r:gz") as stream:
        members = stream.getmembers()
        if len(members) != 1 or members[0].name != REMOTE_HELPER or not members[0].isreg():
            raise RuntimeError("remote helper archive must hold exactly the helper executable")
        if members[0].size > REMOTE_HELPER_LIMIT:
            raise RuntimeError("remote helper exceeds its size limit")
        extracted = stream.extractfile(members[0])
        binary = extracted.read() if extracted is not None else b""
    digest = hashlib.sha256(binary).hexdigest()
    if metadata.get("binary_sha256") != digest:
        raise RuntimeError("remote helper executable does not match its metadata")
    destination = remote_helper_destination(bundle, platform_name, target.name)
    if destination.exists():
        shutil.rmtree(destination)
    destination.mkdir(parents=True)
    executable = destination / REMOTE_HELPER
    executable.write_bytes(binary)
    executable.chmod(0o755)
    if developer_id:
        run(ROOT / "scripts/sign-macos-candidate.sh", "helper", executable)
        binary = executable.read_bytes()
        digest = hashlib.sha256(binary).hexdigest()
    descriptor = {
        "schema": 1,
        "build_id": build_id,
        "target": target.triple,
        "sha256": digest,
        "bytes": len(binary),
    }
    (destination / f"{REMOTE_HELPER}.json").write_text(
        json.dumps(descriptor, sort_keys=True) + "\n", encoding="utf-8"
    )


def prepare_destination(path: Path, replace: bool) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists():
        return
    if not replace:
        raise RuntimeError(f"candidate already exists: {path.name}; pass --replace explicitly")
    path.unlink()


def copy_legal_inventory(destination: Path) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    for source in (
        ROOT / "LICENSE",
        ROOT / "THIRD_PARTY_NOTICES.md",
        ROOT / "assets/licenses/RUST-DEPENDENCIES.md",
        ROOT / "assets/licenses/FLUTTER-DEPENDENCIES.md",
        ROOT / "assets/licenses/SYNTAX-GRAMMARS.md",
    ):
        require_file(source, source.name)
        shutil.copy2(source, destination / source.name)


def thin_macos_arm64(app: Path) -> None:
    # Remote helpers run on other computers: each keeps its own architecture and the Developer
    # ID signature it received before its digest was recorded.
    helpers = app / "Contents/Resources/remote-helper"
    for file in sorted(path for path in app.rglob("*") if path.is_file() and not path.is_symlink()):
        if file.is_relative_to(helpers):
            continue
        description = output("file", "-b", file)
        if "Mach-O" not in description:
            continue
        architectures = output("lipo", "-archs", file).split()
        if "arm64" not in architectures:
            raise RuntimeError(f"macOS payload has no arm64 slice: {file.relative_to(app)}")
        if architectures == ["arm64"]:
            continue
        temporary = file.with_name(f".{file.name}.arm64")
        run("lipo", file, "-thin", "arm64", "-output", temporary)
        temporary.chmod(stat.S_IMODE(file.stat().st_mode))
        temporary.replace(file)

    # Local candidates are deliberately ad-hoc signed. Hardened runtime belongs
    # to the later Developer ID signing transaction; enabling it on only the
    # outer ad-hoc signature makes macOS reject Flutter's nested framework.
    run("codesign", "--force", "--deep", "--sign", "-", app)
    run("codesign", "--verify", "--deep", "--strict", app)


def package_macos(
    source: Path,
    destination: Path,
    version: Version,
    *,
    sign: bool,
    notarize: bool,
) -> None:
    with tempfile.TemporaryDirectory(prefix="gitlama-macos-") as temporary_directory:
        temporary = Path(temporary_directory)
        image_root = temporary / "image"
        image_root.mkdir()
        app = image_root / "GitLama.app"
        run("ditto", source, app)
        thin_macos_arm64(app)
        if sign:
            run(ROOT / "scripts/sign-macos-candidate.sh", "app", app)
        (image_root / "Applications").symlink_to("/Applications")
        candidate = temporary / destination.name
        run(
            "hdiutil",
            "create",
            "-volname",
            f"GitLama {version.marketing}",
            "-srcfolder",
            image_root,
            "-ov",
            "-format",
            "UDZO",
            candidate,
        )
        if sign:
            run(ROOT / "scripts/sign-macos-candidate.sh", "dmg", candidate)
        if notarize:
            run(ROOT / "scripts/sign-macos-candidate.sh", "notarize", candidate)
        run("hdiutil", "verify", candidate)
        shutil.move(candidate, destination)


def stage_linux_system(source: Path, stage: Path) -> None:
    application = stage / "usr/lib/gitlama"
    shutil.copytree(source, application)

    binary_directory = stage / "usr/bin"
    binary_directory.mkdir(parents=True)
    launcher = binary_directory / "gitlama"
    launcher.write_text('#!/bin/sh\nexec /usr/lib/gitlama/gitlama "$@"\n', encoding="utf-8")
    launcher.chmod(0o755)

    desktop_directory = stage / "usr/share/applications"
    desktop_directory.mkdir(parents=True)
    desktop_source = ROOT / "packaging/linux/de.devmil.gitlama.desktop"
    shutil.copy2(desktop_source, desktop_directory / desktop_source.name)

    icon_directory = stage / "usr/share/icons/hicolor/256x256/apps"
    icon_directory.mkdir(parents=True)
    shutil.copy2(
        ROOT / "assets/brand/desktop-icon-256.png",
        icon_directory / "de.devmil.gitlama.png",
    )
    copy_legal_inventory(stage / "usr/share/doc/gitlama")


def add_reproducible_tree(archive: tarfile.TarFile, source: Path, name: str, epoch: int) -> None:
    def filter_metadata(info: tarfile.TarInfo) -> tarfile.TarInfo:
        info.uid = 0
        info.gid = 0
        info.uname = "root"
        info.gname = "root"
        info.mtime = epoch
        if info.name == f"{name}/gitlama":
            info.mode = 0o755
        return info

    archive.add(source, arcname=name, recursive=False, filter=filter_metadata)
    for child in sorted(source.rglob("*"), key=lambda path: path.as_posix()):
        relative = child.relative_to(source).as_posix()
        archive.add(child, arcname=f"{name}/{relative}", recursive=False, filter=filter_metadata)


def package_linux_tar(source: Path, destination: Path, epoch: int) -> None:
    with tempfile.TemporaryDirectory(prefix="gitlama-portable-") as temporary_directory:
        root = Path(temporary_directory) / "gitlama"
        shutil.copytree(source, root)
        copy_legal_inventory(root / "licenses")
        # Ship the launcher entry and icon so users can install them under ~/.local/share.
        shutil.copy2(ROOT / "packaging/linux/de.devmil.gitlama.desktop", root)
        shutil.copy2(ROOT / "assets/brand/desktop-icon-256.png", root / "de.devmil.gitlama.png")
        with destination.open("wb") as raw_stream:
            with gzip.GzipFile(filename="", mode="wb", fileobj=raw_stream, mtime=epoch) as gzip_stream:
                with tarfile.open(fileobj=gzip_stream, mode="w", format=tarfile.PAX_FORMAT) as archive:
                    add_reproducible_tree(archive, root, "gitlama", epoch)


def package_linux_appimage(stage: Path, destination: Path, epoch: int) -> None:
    launcher = stage / "AppRun"
    launcher.write_text(
        '#!/bin/sh\nHERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)\n'
        'exec "$HERE/usr/lib/gitlama/gitlama" "$@"\n',
        encoding="utf-8",
    )
    launcher.chmod(0o755)
    shutil.copy2(ROOT / "packaging/linux/de.devmil.gitlama.desktop", stage)
    shutil.copy2(ROOT / "assets/brand/desktop-icon-256.png", stage / "de.devmil.gitlama.png")
    # The bundled remote helpers include other architectures (Linux arm64); the AppImage itself
    # is x86_64, which appimagetool would otherwise refuse to guess.
    environment = dict(os.environ, SOURCE_DATE_EPOCH=str(epoch), ARCH="x86_64")
    run("appimagetool", "--no-appstream", stage, destination, environment=environment)


def package_linux_native(
    stage: Path,
    destination: Path,
    version: Version,
    format_: str,
    epoch: int,
) -> None:
    if format_ == "deb":
        package_version = version.debian_upstream()
        iteration = str(version.build)
        architecture = "amd64"
        dependencies = ("libgtk-3-0", "libstdc++6", "libc6 (>= 2.35)", "git (>= 2.39)")
    else:
        package_version, iteration = version.rpm_fields()
        architecture = "x86_64"
        dependencies = ("gtk3", "libstdc++", "glibc >= 2.35", "git >= 2.39")
    dependency_arguments = [item for dependency in dependencies for item in ("--depends", dependency)]
    environment = dict(os.environ, SOURCE_DATE_EPOCH=str(fpm_source_date_epoch(epoch)))
    run(
        "fpm",
        "-s",
        "dir",
        "-t",
        format_,
        "-n",
        "gitlama",
        "-v",
        package_version,
        "--iteration",
        iteration,
        "--architecture",
        architecture,
        "--license",
        "MIT",
        "--description",
        "GitLama desktop Git client",
        "--maintainer",
        "GitLama contributors",
        *dependency_arguments,
        "-C",
        stage,
        "-p",
        destination,
        "usr",
        environment=environment,
    )


def package_linux(source: Path, destination: Path, version: Version, format_: str, epoch: int) -> None:
    if format_ == "tar.gz":
        package_linux_tar(source, destination, epoch)
        return
    with tempfile.TemporaryDirectory(prefix="gitlama-linux-") as temporary_directory:
        stage = Path(temporary_directory)
        stage_linux_system(source, stage)
        if format_ == "AppImage":
            package_linux_appimage(stage, destination, epoch)
        else:
            package_linux_native(stage, destination, version, format_, epoch)


def package_windows(source: Path, destination: Path, version: Version) -> None:
    run(
        "wix",
        "build",
        ROOT / "packaging/windows/gitlama.wxs",
        "-arch",
        "x64",
        "-d",
        f"ProductVersion={version.windows_msi()}",
        "-d",
        f"MarketingVersion={version.marketing}",
        "-d",
        f"BuildNumber={version.build}",
        "-d",
        f"StageDir={source}",
        "-o",
        destination,
    )
    run("wix", "msi", "validate", destination)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("format", choices=sorted(target[2] for target in TARGETS))
    parser.add_argument("--skip-build", action="store_true", help="use an existing release build")
    parser.add_argument("--replace", action="store_true", help="replace this exact candidate")
    parser.add_argument("--sign", action="store_true", help="use the configured native signing identity")
    parser.add_argument("--notarize", action="store_true", help="submit and staple a signed macOS candidate")
    parser.add_argument("--output-dir", type=Path, default=ROOT / "dist")
    return parser.parse_args()


def main() -> None:
    arguments = parse_arguments()
    try:
        platform_name = PLATFORM_BY_SYSTEM[platform.system()]
        architecture = ARCHITECTURE_BY_MACHINE[platform.machine()]
    except KeyError as error:
        raise RuntimeError("unsupported native packaging host") from error
    target = (platform_name, architecture, arguments.format)
    if target not in TARGETS:
        raise RuntimeError(f"package format is not supported on this native host: {target}")
    if arguments.notarize and (platform_name != "macos" or not arguments.sign):
        raise RuntimeError("--notarize requires macOS packaging with --sign")
    if arguments.sign and platform_name != "macos":
        raise RuntimeError("native signing is handled by the target-specific release job")

    version = Version.read(ROOT / "VERSION")
    destination = arguments.output_dir.resolve() / artifact_name(version, *target)
    prepare_destination(destination, arguments.replace)
    if not arguments.skip_build:
        # Release packages carry the helper of the release baseline, not a
        # development build of it.
        os.environ["GITLAMA_DEV_REMOTE_HELPER"] = "0"
        # Plugin crates (for example super_native_extensions) have their own
        # manifests and do not inherit rust-core's release profile.
        os.environ["CARGO_PROFILE_RELEASE_DEBUG"] = "1"
        os.environ["CARGO_PROFILE_RELEASE_STRIP"] = "none"
        native_build_options = []
        if platform_name == "macos":
            # Never mutate the shared Pub cache. Preserve this audited overlay
            # through the build by disabling Flutter's automatic pub get.
            run("flutter", "pub", "get", "--enforce-lockfile")
            run(sys.executable, ROOT / "scripts/prepare-macos-native-symbols.py")
            native_build_options = ["--no-pub"]
        run("flutter", "build", platform_name, "--release", *native_build_options,
            f"--split-debug-info={ROOT / 'build/symbols/dart' / platform_name}")
    source = require_release_bundle(platform_name)
    # Build-tree originals remain available for symbol collection. Do not
    # ship native DWARF in installers or change signed helper payload bytes.
    if platform_name == "linux":
        for native in source.rglob("*"):
            if not native.is_file() or native.is_symlink() or "remote-helper" in native.relative_to(source).parts:
                continue
            with native.open("rb") as stream:
                elf = stream.read(4) == b"\x7fELF"
            if elf:
                run("strip", "--strip-unneeded", native)
    epoch = source_date_epoch(dict(os.environ))
    bundle_remote_helper(source, platform_name, dict(os.environ),
                         developer_id=platform_name == "macos" and arguments.sign)

    if platform_name == "macos":
        package_macos(
            source,
            destination,
            version,
            sign=arguments.sign,
            notarize=arguments.notarize,
        )
    elif platform_name == "windows":
        package_windows(source, destination, version)
    else:
        package_linux(source, destination, version, arguments.format, epoch)
    require_file(destination, "package candidate")
    print(destination)


if __name__ == "__main__":
    main()
