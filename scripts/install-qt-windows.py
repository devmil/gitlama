#!/usr/bin/env python3
"""Installs the prebuilt Qt for Windows MSVC that GitLama builds against.

Qt 6.11+ publishes each Windows architecture in its own repository folder
(`qt6_6112/qt6_6112_msvc2022_64/`), which aqtinstall 3.3 cannot read. This
reads that folder's Updates.xml, downloads the qtbase, qtdeclarative, qtsvg
and runtime archives, checks their SHA-1 and extracts them with 7-Zip.

  install-qt-windows.py --version 6.11.2 --output C:/Qt

Prints the installation prefix and, under GitHub Actions, adds its bin
directory to PATH and sets QT_ROOT_DIR and QMAKE.
"""
from __future__ import annotations

import argparse
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

BASE = "https://download.qt.io/online/qtsdkrepository/windows_x86/desktop"
ARCH = "msvc2022_64"
WANTED = ("qtbase-", "qtdeclarative-", "qtsvg-", "d3dcompiler_47-", "opengl32sw-")


def fetch(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": "gitlama-ci"})
    with urllib.request.urlopen(request, timeout=300) as response:
        return response.read()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", required=True)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()

    compact = arguments.version.replace(".", "")
    folder = f"{BASE}/qt6_{compact}/qt6_{compact}_{ARCH}"
    package_name = f"qt.qt6.{compact}.win64_{ARCH}"
    updates = ET.fromstring(fetch(f"{folder}/Updates.xml"))
    package = next(
        (entry for entry in updates.findall("PackageUpdate") if entry.findtext("Name") == package_name), None
    )
    if package is None:
        sys.exit(f"install-qt-windows: {package_name} is not in {folder}/Updates.xml")
    version = package.findtext("Version")
    archives = [name.strip() for name in (package.findtext("DownloadableArchives") or "").split(",")]
    archives = [name for name in archives if name.startswith(WANTED)]
    if not any(name.startswith("qtbase-") for name in archives):
        sys.exit("install-qt-windows: no qtbase archive listed")

    prefix = arguments.output / arguments.version / ARCH
    prefix.mkdir(parents=True, exist_ok=True)
    seven_zip = shutil.which("7z") or r"C:\Program Files\7-Zip\7z.exe"
    with tempfile.TemporaryDirectory() as scratch:
        for name in archives:
            url = f"{folder}/{package_name}/{version}{name}"
            data = fetch(url)
            expected = fetch(url + ".sha1").decode("ascii").split()[0].strip()
            if hashlib.sha1(data).hexdigest() != expected:
                sys.exit(f"install-qt-windows: checksum mismatch for {name}")
            path = Path(scratch) / name
            path.write_bytes(data)
            subprocess.run([seven_zip, "x", "-y", f"-o{prefix}", str(path)], check=True, stdout=subprocess.DEVNULL)
            print(f"install-qt-windows: {name}", file=sys.stderr)

    qmake = prefix / "bin" / "qmake.exe"
    if not qmake.is_file():
        sys.exit(f"install-qt-windows: {qmake} missing after extraction")
    if os.environ.get("GITHUB_PATH"):
        with open(os.environ["GITHUB_PATH"], "a", encoding="utf-8") as path_file:
            path_file.write(f"{prefix / 'bin'}\n")
        with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as env_file:
            env_file.write(f"QT_ROOT_DIR={prefix}\nQMAKE={qmake}\n")
    print(prefix)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
