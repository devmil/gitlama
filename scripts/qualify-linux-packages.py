#!/usr/bin/env python3
"""Inspect and smoke-test all four GitLama Linux package formats."""

from __future__ import annotations

import argparse
import configparser
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import signal
import shutil
import subprocess
import tarfile
import tempfile
import time

from lib.package_contract import (
    Version,
    artifact_name,
    leaked_build_path,
    without_allowed_flutter_build_metadata,
)


ROOT = Path(__file__).resolve().parent.parent
SYSTEM_APPLICATION = Path("usr/lib/gitlama")
SYSTEM_BINARY = SYSTEM_APPLICATION / "gitlama"
SYSTEM_NATIVE = SYSTEM_APPLICATION / "lib/libgitlama_core.so"
SYSTEM_LAUNCHER = Path("usr/bin/gitlama")
DESKTOP = Path("usr/share/applications/de.devmil.gitlama.desktop")
ICON = Path("usr/share/icons/hicolor/256x256/apps/de.devmil.gitlama.png")
DOCS = Path("usr/share/doc/gitlama")
BASELINE_GLIBC = (2, 35)


class QualificationError(RuntimeError):
    pass


def run(command: list[str], *, cwd: Path | None = None, input_bytes: bytes | None = None) -> bytes:
    try:
        result = subprocess.run(
            command,
            cwd=cwd or ROOT,
            input=input_bytes,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True,
        )
    except FileNotFoundError as error:
        raise QualificationError(f"required tool is missing: {command[0]}") from error
    except subprocess.CalledProcessError as error:
        detail = b"\n".join((error.stdout or b"", error.stderr or b"")).decode(
            "utf-8", errors="replace"
        ).strip()
        raise QualificationError(f"command failed: {command[0]}: {detail}") from error
    return result.stdout


def require(condition: bool, message: str) -> None:
    if not condition:
        raise QualificationError(message)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def safe_tar_extract(archive_path: Path, destination: Path) -> Path:
    destination.mkdir()
    with tarfile.open(archive_path, "r:gz") as archive:
        for member in archive.getmembers():
            name = PurePosixPath(member.name)
            require(not name.is_absolute() and ".." not in name.parts, "archive contains an unsafe path")
            if member.issym() or member.islnk():
                target = PurePosixPath(member.linkname)
                require(not target.is_absolute() and ".." not in target.parts, "archive contains an unsafe link")
        archive.extractall(destination)
    root = destination / "gitlama"
    require(root.is_dir(), "portable archive has no gitlama root")
    return root


def extract_appimage(artifact: Path, destination: Path) -> Path:
    destination.mkdir()
    run([str(artifact), "--appimage-extract"], cwd=destination)
    root = destination / "squashfs-root"
    require(root.is_dir(), "AppImage extraction produced no squashfs-root")
    return root


def extract_deb(artifact: Path, destination: Path) -> tuple[Path, str]:
    root = destination / "root"
    root.mkdir(parents=True)
    run(["dpkg-deb", "-x", str(artifact), str(root)])
    metadata = run(["dpkg-deb", "-f", str(artifact), "Package", "Version", "Architecture", "Depends"]).decode()
    return root, metadata


def extract_rpm(artifact: Path, destination: Path) -> tuple[Path, str]:
    destination.mkdir()
    payload = run(["rpm2cpio", str(artifact)])
    run(["cpio", "--quiet", "-idmu", "--no-absolute-filenames"], cwd=destination, input_bytes=payload)
    metadata = run(["rpm", "-qp", "--qf", "%{NAME}\n%{VERSION}-%{RELEASE}\n%{ARCH}\n[%{REQUIRENAME}\n]", str(artifact)]).decode()
    return destination, metadata


def elf_files(root: Path) -> list[Path]:
    result = []
    for path in sorted(candidate for candidate in root.rglob("*") if candidate.is_file() and not candidate.is_symlink()):
        with path.open("rb") as stream:
            if stream.read(4) == b"\x7fELF":
                result.append(path)
    return result


def glibc_versions(path: Path) -> set[tuple[int, ...]]:
    text = run(["readelf", "--version-info", "-W", str(path)]).decode("utf-8", errors="replace")
    versions = set()
    for match in re.findall(r"\bGLIBC_(\d+(?:\.\d+)+)\b", text):
        versions.add(tuple(int(part) for part in match.split(".")))
    return versions


def elf_machine(path: Path) -> str:
    header = run(["readelf", "-hW", str(path)]).decode("utf-8", errors="replace")
    match = re.search(r"^\s*Machine:\s*(.+?)\s*$", header, re.MULTILINE)
    return match.group(1) if match else ""


def is_remote_helper(root: Path, path: Path) -> bool:
    """A remote helper the package carries for installation on other computers."""
    return "remote-helper" in path.relative_to(root).parts


def inspect_elf(root: Path, binary: Path, native: Path) -> dict[str, object]:
    files = elf_files(root)
    require(root / binary in files, "application executable is not ELF")
    require(root / native in files, "Rust native library is not ELF")
    dependencies = set()
    max_glibc: tuple[int, ...] = (0,)
    for path in files:
        dynamic = run(["readelf", "-dW", str(path)]).decode("utf-8", errors="replace")
        search_paths = re.findall(r"\((?:RPATH|RUNPATH)\).*?\[(.*?)\]", dynamic)
        absolute_search_paths = [
            part
            for value in search_paths
            for part in value.split(":")
            if part.startswith("/")
        ]
        require(
            not absolute_search_paths,
            "ELF payload contains an absolute runtime search path: "
            f"{path.relative_to(root)}: {', '.join(absolute_search_paths)}",
        )
        if "X86-64" not in elf_machine(path):
            # Only remote helpers built for other hosts (Linux arm64) may have another
            # architecture; ldd cannot load them here, but their glibc floor is still checked.
            require(
                is_remote_helper(root, path),
                f"ELF payload has a foreign architecture: {path.relative_to(root)}",
            )
        else:
            ldd = run(["ldd", str(path)]).decode("utf-8", errors="replace")
            require("not found" not in ldd, "ELF payload has an unresolved dynamic dependency")
            dependencies.update(re.findall(r"^\s*([^\s=>]+)", ldd, re.MULTILINE))
        versions = glibc_versions(path)
        if versions:
            max_glibc = max(max_glibc, max(versions))
    require(max_glibc <= BASELINE_GLIBC, f"ELF payload exceeds GLIBC_{'.'.join(map(str, BASELINE_GLIBC))}")
    return {
        "elfFiles": len(files),
        "glibcMaximum": ".".join(map(str, max_glibc)),
        "resolvedDependencies": sorted(dependencies),
    }


def inspect_assets(root: Path, portable: bool) -> None:
    if portable:
        required = (
            Path("gitlama"),
            Path("lib/libgitlama_core.so"),
            Path("data/flutter_assets/AssetManifest.bin"),
            Path("data/flutter_assets/NOTICES.Z"),
            Path("licenses/LICENSE"),
            Path("licenses/THIRD_PARTY_NOTICES.md"),
        )
    else:
        required = (
            SYSTEM_BINARY,
            SYSTEM_NATIVE,
            SYSTEM_LAUNCHER,
            DESKTOP,
            ICON,
            DOCS / "LICENSE",
            DOCS / "THIRD_PARTY_NOTICES.md",
            SYSTEM_APPLICATION / "data/flutter_assets/AssetManifest.bin",
            SYSTEM_APPLICATION / "data/flutter_assets/NOTICES.Z",
        )
    for relative in required:
        require((root / relative).is_file(), f"payload is missing /{relative}")
    if portable:
        return
    launcher = (root / SYSTEM_LAUNCHER).read_text(encoding="utf-8")
    require(launcher == '#!/bin/sh\nexec /usr/lib/gitlama/gitlama "$@"\n', "system launcher changed")
    desktop = configparser.ConfigParser(interpolation=None)
    desktop.optionxform = str
    desktop.read(root / DESKTOP, encoding="utf-8")
    entry = desktop["Desktop Entry"]
    expected = {
        "Type": "Application",
        "Name": "GitLama",
        "Exec": "gitlama",
        "Icon": "de.devmil.gitlama",
        "Terminal": "false",
    }
    for key, value in expected.items():
        require(entry.get(key) == value, f"desktop identity changed: {key}")


def scan_build_paths(root: Path) -> int:
    count = 0
    for path in sorted(candidate for candidate in root.rglob("*") if candidate.is_file() and not candidate.is_symlink()):
        data = path.read_bytes()
        data = without_allowed_flutter_build_metadata(data, path.name, ROOT)
        leaked = leaked_build_path(data, ROOT)
        if leaked:
            raise QualificationError(
                "payload contains a source or CI build path: "
                f"{path.relative_to(root)}: {leaked}"
            )
        count += 1
    return count


def launch(root: Path, executable: Path, seconds: float) -> str:
    if seconds <= 0:
        return "not-run"
    xvfb = shutil.which("xvfb-run")
    require(xvfb is not None, "xvfb-run is required for Linux launch qualification")
    with tempfile.TemporaryDirectory(prefix="gitlama-linux-launch-") as directory:
        temporary = Path(directory)
        profile_root = temporary / "profile"
        runtime = temporary / "runtime"
        profile_root.mkdir()
        runtime.mkdir(mode=0o700)
        environment = dict(os.environ)
        environment["GITLAMA_PROFILE_ROOT"] = str(profile_root)
        environment["GITLAMA_RUNTIME_DIR"] = str(runtime)
        environment.pop("GITLAMA_NATIVE_LIBRARY", None)
        process = subprocess.Popen(
            [xvfb, "-a", str(root / executable)],
            cwd=temporary,
            env=environment,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        try:
            time.sleep(seconds)
            require(process.poll() is None, "packaged Linux application exited during launch smoke")
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait(timeout=5)
    return "passed"


def inspect_payload(name: str, root: Path, portable: bool, launch_seconds: float) -> dict[str, object]:
    inspect_assets(root, portable)
    application = Path() if portable else SYSTEM_APPLICATION
    binary = application / "gitlama"
    native = application / "lib/libgitlama_core.so"
    return {
        "format": name,
        "binarySha256": sha256(root / binary),
        "nativeSha256": sha256(root / native),
        "elf": inspect_elf(root, binary, native),
        "scannedFiles": scan_build_paths(root),
        "launch": launch(root, Path("AppRun") if name == "AppImage" else binary, launch_seconds),
    }


def qualify(directory: Path, report: Path, launch_seconds: float) -> None:
    version = Version.read(ROOT / "VERSION")
    artifacts = {
        format_: directory / artifact_name(version, "linux", "x86_64", format_)
        for format_ in ("AppImage", "deb", "rpm", "tar.gz")
    }
    for artifact in artifacts.values():
        require(artifact.is_file(), f"artifact is missing: {artifact.name}")

    records = []
    metadata = {}
    with tempfile.TemporaryDirectory(prefix="gitlama-linux-packages-") as temporary_directory:
        temporary = Path(temporary_directory)
        appimage_root = extract_appimage(artifacts["AppImage"], temporary / "appimage")
        records.append(inspect_payload("AppImage", appimage_root, False, launch_seconds))
        deb_root, metadata["deb"] = extract_deb(artifacts["deb"], temporary / "deb")
        records.append(inspect_payload("deb", deb_root, False, launch_seconds))
        rpm_root, metadata["rpm"] = extract_rpm(artifacts["rpm"], temporary / "rpm")
        records.append(inspect_payload("rpm", rpm_root, False, launch_seconds))
        tar_root = safe_tar_extract(artifacts["tar.gz"], temporary / "tar")
        records.append(inspect_payload("tar.gz", tar_root, True, launch_seconds))

        expected_binary = {record["binarySha256"] for record in records}
        expected_native = {record["nativeSha256"] for record in records}
        require(len(expected_binary) == 1, "Linux formats contain different application executables")
        require(len(expected_native) == 1, "Linux formats contain different Rust native libraries")
        run(["python3", str(ROOT / "scripts/native-smoke.py"), str(tar_root)])

    requirements = {
        "deb": ("libgtk-3-0", "libstdc++6", "libc6", "git"),
        "rpm": ("gtk3", "libstdc++", "glibc", "git"),
    }
    for format_, text in metadata.items():
        require(
            all(requirement in text for requirement in requirements[format_]),
            f"{format_} metadata lacks runtime dependencies",
        )
    result = {
        "schema": 1,
        "platform": "linux",
        "architecture": "x86_64",
        "minimumGlibc": "2.35",
        "nativeBridge": "passed",
        "payloadsMatch": True,
        "artifacts": [
            {
                "name": artifact.name,
                "bytes": artifact.stat().st_size,
                "sha256": sha256(artifact),
            }
            for artifact in artifacts.values()
        ],
        "payloads": records,
    }
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(report)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--report", type=Path, default=ROOT / "dist/qualification/linux-x86_64.json")
    parser.add_argument("--launch-seconds", type=float, default=0)
    arguments = parser.parse_args()
    qualify(arguments.directory.resolve(), arguments.report.resolve(), arguments.launch_seconds)


if __name__ == "__main__":
    main()
