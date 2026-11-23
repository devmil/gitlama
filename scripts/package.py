#!/usr/bin/env python3
"""Build one unsigned native package from the Rust/QML release build."""

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


SPARKLE_VERSION = "2.10.0"
SPARKLE_SHA256 = "c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c"
MACOS_MINIMUM_SYSTEM = "13.0"


def bundle_path(platform_name: str) -> Path:
    if platform_name == "macos":
        return ROOT / "build/macos/GitLama.app"
    if platform_name == "windows":
        return ROOT / "build/windows/bundle"
    return ROOT / "build/linux/bundle"


def require_release_bundle(platform_name: str) -> Path:
    bundle = bundle_path(platform_name)
    if platform_name == "macos":
        require_file(bundle / "Contents/MacOS/GitLama", "macOS executable")
        require_file(bundle / "Contents/Info.plist", "macOS bundle information")
        require_file(bundle / "Contents/Frameworks/QtQuick.framework/QtQuick", "bundled Qt Quick")
        require_file(bundle / "Contents/Frameworks/Sparkle.framework/Sparkle", "Sparkle framework")
        return bundle
    if platform_name == "windows":
        require_file(bundle / "gitlama.exe", "Windows executable")
        require_file(bundle / "Qt6Quick.dll", "bundled Qt Quick")
        if not (bundle / "qml").is_dir():
            raise RuntimeError("bundled QML modules are missing")
        return bundle
    require_file(bundle / "gitlama", "Linux executable")
    require_file(bundle / "qt.conf", "bundled Qt configuration")
    if not any((bundle / "lib").glob("libQt6Quick.so*")):
        raise RuntimeError("bundled Qt Quick is missing")
    return bundle


def cargo_build(target: str | None = None) -> Path:
    arguments = ["cargo", "build", "--release", "--locked",
                 "--manifest-path", ROOT / "rust-core/Cargo.toml", "-p", "gitlama"]
    if target:
        arguments += ["--target", target]
    run(*arguments)
    directory = ROOT / "rust-core/target" / (target or "") / "release"
    return directory / ("gitlama.exe" if platform.system() == "Windows" else "gitlama")


def qt_tool(name: str) -> str:
    qmake = os.environ.get("QMAKE") or shutil.which("qmake6") or shutil.which("qmake")
    if qmake:
        candidate = Path(output(qmake, "-query", "QT_INSTALL_BINS")) / name
        for path in (candidate, candidate.with_suffix(".exe")):
            if path.is_file():
                return str(path)
    found = shutil.which(name)
    if not found:
        raise RuntimeError(f"{name} not found")
    return found


def build_linux() -> Path:
    binary = cargo_build()
    bundle = bundle_path("linux")
    run(sys.executable, ROOT / "scripts/stage_linux_bundle.py", "--binary", binary, "--output", bundle)
    return bundle


def sparkle_framework() -> Path:
    """The pinned Sparkle release, downloaded and verified once into build/sparkle."""
    directory = ROOT / "build/sparkle" / SPARKLE_VERSION
    framework = directory / "Sparkle.framework"
    if framework.is_dir():
        return framework
    directory.mkdir(parents=True, exist_ok=True)
    archive = directory / f"Sparkle-{SPARKLE_VERSION}.tar.xz"
    run("curl", "--fail", "--location", "--proto", "=https", "--tlsv1.2", "--silent",
        "--show-error", "--output", archive,
        "https://github.com/sparkle-project/Sparkle/releases/download/"
        f"{SPARKLE_VERSION}/Sparkle-{SPARKLE_VERSION}.tar.xz")
    if hashlib.sha256(archive.read_bytes()).hexdigest() != SPARKLE_SHA256:
        archive.unlink()
        raise RuntimeError("Sparkle archive checksum mismatch")
    run("tar", "-xJf", archive, "-C", directory, "./Sparkle.framework", "./bin")
    archive.unlink()
    return framework


def build_macos(version: Version) -> Path:
    os.environ["MACOSX_DEPLOYMENT_TARGET"] = MACOS_MINIMUM_SYSTEM
    binary = cargo_build("aarch64-apple-darwin")
    app = bundle_path("macos")
    if app.exists():
        shutil.rmtree(app)
    (app / "Contents/MacOS").mkdir(parents=True)
    (app / "Contents/Resources").mkdir()
    shutil.copy2(binary, app / "Contents/MacOS/GitLama")
    template = (ROOT / "packaging/macos/Info.plist.in").read_text(encoding="utf-8")
    (app / "Contents/Info.plist").write_text(
        template.replace("@VERSION@", version.apple_bundle_short_version())
        .replace("@BUILD@", str(version.build))
        .replace("@MINIMUM_SYSTEM@", MACOS_MINIMUM_SYSTEM),
        encoding="utf-8",
    )
    (app / "Contents/PkgInfo").write_text("APPL????", encoding="ascii")
    with tempfile.TemporaryDirectory(prefix="gitlama-icon-") as temporary_directory:
        iconset = Path(temporary_directory) / "AppIcon.iconset"
        iconset.mkdir()
        icons = ROOT / "packaging/macos/AppIcon.appiconset"
        for size in (16, 32, 128, 256, 512):
            shutil.copy2(icons / f"app_icon_{size}.png", iconset / f"icon_{size}x{size}.png")
            shutil.copy2(icons / f"app_icon_{size * 2}.png", iconset / f"icon_{size}x{size}@2x.png")
        run("iconutil", "-c", "icns", "-o", app / "Contents/Resources/AppIcon.icns", iconset)
    run(qt_tool("macdeployqt"), app, f"-qmldir={ROOT / 'qml/GitLama'}",
        f"-qmlimport={ROOT / 'qml'}", "-always-overwrite")
    # macdeployqt copies every SQL driver; GitLama uses no Qt SQL.
    shutil.rmtree(app / "Contents/PlugIns/sqldrivers", ignore_errors=True)
    # Development builds also look in Qt's own lib folder; the bundle must not.
    executable = app / "Contents/MacOS/GitLama"
    qmake = os.environ.get("QMAKE") or shutil.which("qmake6") or shutil.which("qmake")
    if qmake:
        subprocess.run(["install_name_tool", "-delete_rpath", output(qmake, "-query", "QT_INSTALL_LIBS"),
                        str(executable)], check=False, stderr=subprocess.DEVNULL)
    if "@executable_path/../Frameworks" not in output("otool", "-l", executable):
        raise RuntimeError("the macOS executable lacks the Frameworks rpath")
    run("ditto", sparkle_framework(), app / "Contents/Frameworks/Sparkle.framework")
    copy_legal_inventory(app / "Contents/Resources/licenses")
    return app


def build_windows() -> Path:
    binary = cargo_build()
    bundle = bundle_path("windows")
    if bundle.exists():
        shutil.rmtree(bundle)
    bundle.mkdir(parents=True)
    shutil.copy2(binary, bundle / "gitlama.exe")
    run(qt_tool("windeployqt"), "--release", "--qmldir", ROOT / "qml/GitLama",
        "--qmlimport", ROOT / "qml", "--no-translations", "--no-system-d3d-compiler",
        bundle / "gitlama.exe")
    # The offscreen platform lets the package smoke test and qualification
    # render the first window on a runner without a desktop session.
    offscreen = Path(output(os.environ.get("QMAKE") or qt_tool("qmake"), "-query", "QT_INSTALL_PLUGINS"))
    shutil.copy2(offscreen / "platforms/qoffscreen.dll", bundle / "platforms/qoffscreen.dll")
    copy_legal_inventory(bundle / "licenses")
    return bundle


def build_release_bundle(platform_name: str, version: Version) -> Path:
    if platform_name == "macos":
        return build_macos(version)
    if platform_name == "windows":
        return build_windows()
    return build_linux()


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
        ROOT / "assets/licenses/QT-RUNTIME.md",
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
    # outer ad-hoc signature makes macOS reject the nested Qt frameworks.
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


def add_reproducible_tree(archive: tarfile.TarFile, source: Path, name: str, epoch: int,
                          executables: set[str] | None = None) -> None:
    executables = {f"{name}/gitlama"} if executables is None else executables

    def filter_metadata(info: tarfile.TarInfo) -> tarfile.TarInfo:
        info.uid = 0
        info.gid = 0
        info.uname = "root"
        info.gname = "root"
        info.mtime = epoch
        if info.name in executables:
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


# Host runtimes the private Qt needs; everything Qt-specific is bundled.
DEB_DEPENDENCIES = (
    "libc6 (>= 2.35)", "libstdc++6", "libgl1", "libegl1", "libfontconfig1", "libfreetype6",
    "libglib2.0-0", "libdbus-1-3", "libwayland-client0", "libwayland-cursor0", "libwayland-egl1",
    "libxkbcommon0", "libxkbcommon-x11-0", "libx11-6", "libx11-xcb1", "libxcb1", "libxcb-cursor0",
    "libxcb-icccm4", "libxcb-image0", "libxcb-keysyms1", "libxcb-randr0", "libxcb-render-util0",
    "libxcb-shape0", "libxcb-xfixes0", "libxcb-xkb1", "libpng16-16", "zlib1g", "libzstd1",
    "libharfbuzz0b", "git (>= 2.39)",
)
RPM_DEPENDENCIES = (
    "glibc >= 2.35", "libstdc++", "libglvnd-opengl", "libglvnd-egl", "fontconfig", "freetype",
    "glib2", "dbus-libs", "libwayland-client", "libwayland-cursor", "libwayland-egl",
    "libxkbcommon", "libxkbcommon-x11", "libX11", "libX11-xcb", "libxcb", "xcb-util-cursor",
    "xcb-util-wm", "xcb-util-image", "xcb-util-keysyms", "xcb-util-renderutil", "libpng",
    "zlib", "libzstd", "harfbuzz", "git >= 2.39",
)
ARCH_DEPENDENCIES = (
    "glibc", "gcc-libs", "libglvnd", "fontconfig", "freetype2", "glib2", "dbus", "wayland",
    "libxkbcommon", "libxkbcommon-x11", "libx11", "libxcb", "xcb-util-cursor", "xcb-util-wm",
    "xcb-util-image", "xcb-util-keysyms", "xcb-util-renderutil", "libpng", "zlib", "zstd",
    "harfbuzz", "git",
)


def package_linux_arch(stage: Path, destination: Path, version: Version, epoch: int) -> None:
    """An Arch Linux (pacman) package, built by makepkg on an Arch host or in an Arch container."""
    with tempfile.TemporaryDirectory(prefix="gitlama-arch-") as temporary_directory:
        work = Path(temporary_directory)
        depends = " ".join(f"'{dependency}'" for dependency in ARCH_DEPENDENCIES)
        (work / "PKGBUILD").write_text(
            "pkgname=gitlama\n"
            f"pkgver={version.arch_pkgver()}\n"
            f"pkgrel={version.build}\n"
            "pkgdesc='GitLama desktop Git client'\n"
            "arch=('x86_64')\n"
            "url='https://devmil.de/gitlama/'\n"
            "license=('MIT')\n"
            f"depends=({depends})\n"
            "options=('!debug' '!lto' '!purge' '!strip')\n"
            "source=('root.tar')\n"
            "sha256sums=('SKIP')\n\n"
            "package() {\n  cp -a \"$srcdir/root/.\" \"$pkgdir/\"\n}\n",
            encoding="utf-8",
        )
        with tarfile.open(work / "root.tar", "w", format=tarfile.PAX_FORMAT) as archive:
            add_reproducible_tree(archive, stage, "root", epoch, executables={"root/usr/lib/gitlama/gitlama", "root/usr/bin/gitlama"})
        for path in work.rglob("*"):
            os.utime(path, (epoch, epoch), follow_symlinks=False)
        environment = dict(os.environ, SOURCE_DATE_EPOCH=str(fpm_source_date_epoch(epoch)))
        if shutil.which("makepkg") and Path("/etc/arch-release").exists():
            run("makepkg", "--nodeps", "--force", "--noconfirm", cwd=work,
                environment=dict(environment, PKGDEST=str(work)))
        else:
            engine = os.environ.get("GITLAMA_CONTAINER_ENGINE") or shutil.which("podman") or shutil.which("docker")
            if not engine:
                raise RuntimeError("makepkg on Arch Linux, podman or docker is required")
            work.chmod(0o777)
            run(engine, "run", "--rm", "--security-opt", "label=disable",
                "--mount", f"type=bind,src={work},dst=/build",
                "--env", f"SOURCE_DATE_EPOCH={environment['SOURCE_DATE_EPOCH']}",
                os.environ.get("GITLAMA_ARCH_BUILD_IMAGE", "archlinux:base-devel"),
                "bash", "-euo", "pipefail", "-c",
                "useradd --create-home builder; cp -a /build /home/builder/pkg; "
                "chown -R builder:builder /home/builder/pkg; "
                "su builder -c 'cd /home/builder/pkg && makepkg --nodeps --force --noconfirm'; "
                "cp /home/builder/pkg/*.pkg.tar.zst /build/")
        built = sorted(work.glob("gitlama-*.pkg.tar.zst"))
        if len(built) != 1:
            raise RuntimeError("makepkg produced no single package")
        shutil.move(built[0], destination)


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
        dependencies = DEB_DEPENDENCIES
    else:
        package_version, iteration = version.rpm_fields()
        architecture = "x86_64"
        dependencies = RPM_DEPENDENCIES
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
        elif format_ == "pkg.tar.zst":
            package_linux_arch(stage, destination, version, epoch)
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
    parser.add_argument("--build-only", action="store_true",
                        help="build and stage the release bundle, then stop (to sign it first)")
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
    if not arguments.build_only:
        prepare_destination(destination, arguments.replace)
    if arguments.build_only and arguments.skip_build:
        raise RuntimeError("--build-only and --skip-build exclude each other")
    if not arguments.skip_build:
        # Release packages carry the helper of the release baseline, not a
        # development build of it.
        os.environ["GITLAMA_DEV_REMOTE_HELPER"] = "0"
        # Keep DWARF in the build tree for symbol collection; installers ship
        # stripped copies.
        os.environ["CARGO_PROFILE_RELEASE_DEBUG"] = "1"
        os.environ["CARGO_PROFILE_RELEASE_STRIP"] = "none"
        build_release_bundle(platform_name, version)
    if arguments.build_only:
        print(require_release_bundle(platform_name))
        return
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
