#!/usr/bin/env python3
"""Stages GitLama's Linux bundle with an application-private Qt runtime.

The bundle holds the executable, the Qt and ICU libraries it and its plugins
need, the Qt plugins a desktop session selects (Wayland, XCB, SVG, input
methods, the portal theme) and the QML modules the embedded QML imports,
closed over their qmldir dependencies. Graphics, fonts, glibc and the other
host runtimes stay on the system. RUNPATHs point into the bundle, and
qt.conf makes Qt look only there.

  stage_linux_bundle.py --binary rust-core/target/release/gitlama --output build/linux/bundle

Needs qmake6 (or QMAKE), qmlimportscanner and patchelf (or PATCHELF).
"""
from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# Libraries bundled with the application; everything else is a host runtime.
BUNDLED_LIBRARIES = re.compile(r"^lib(Qt6\w*|icu\w+|double-conversion|md4c|b2)\.so")

# Plugin directories and the plugins taken from each (None takes all).
PLUGINS: dict[str, list[str] | None] = {
    "platforms": ["libqwayland.so", "libqwayland-generic.so", "libqwayland-egl.so", "libqxcb.so",
                  "libqoffscreen.so", "libqminimal.so"],
    "wayland-shell-integration": None,
    "wayland-decoration-client": None,
    "wayland-graphics-integration-client": None,
    "xcbglintegrations": None,
    # Qt's own input contexts only; third-party ones (fcitx5) link the host Qt.
    "platforminputcontexts": ["libcomposeplatforminputcontextplugin.so", "libibusplatforminputcontextplugin.so"],
    "platformthemes": ["libqxdgdesktopportal.so"],
    "imageformats": ["libqsvg.so", "libqico.so", "libqjpeg.so", "libqgif.so"],
    "iconengines": ["libqsvgicon.so"],
}

# Modules QML loads without a static import: Dialogs picks its implementation
# at run time.
EXTRA_MODULES = ["QtQuick.Dialogs.quickimpl", "QtQuick.Controls.Basic", "QtQuick.Controls.impl"]


def qt_query(name: str) -> Path:
    qmake = os.environ.get("QMAKE") or shutil.which("qmake6") or shutil.which("qmake")
    if not qmake:
        sys.exit("stage_linux_bundle: qmake6 not found (set QMAKE)")
    return Path(subprocess.check_output([qmake, "-query", name], text=True).strip())


def run(command: list[str]) -> str:
    return subprocess.check_output(command, text=True)


def module_dir(qml_root: Path, uri: str) -> Path | None:
    path = qml_root.joinpath(*uri.split("."))
    return path if (path / "qmldir").is_file() else None


def qmldir_dependencies(qmldir: Path) -> list[str]:
    """Required imports and dependencies. `optional import` lines (the
    Controls styles a QtQuick.Controls import may pick) stay out: GitLama
    uses Templates and the Basic style explicitly."""
    modules = []
    for line in qmldir.read_text(encoding="utf-8").splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[0] in ("import", "depends"):
            modules.append(parts[1])
    return modules


def scan_imports(qml_sources: Path, qt_qml: Path) -> set[str]:
    """The Qt modules the application's own QML imports (qmlimportscanner
    would also follow Qt's style-specific dialog files)."""
    uris = set()
    pattern = re.compile(r"^\s*import\s+([A-Za-z][\w.]*)", re.MULTILINE)
    for source in qml_sources.rglob("*.qml"):
        for uri in pattern.findall(source.read_text(encoding="utf-8")):
            if module_dir(qt_qml, uri):
                uris.add(uri)
    return uris


def copy_module(source: Path, destination: Path) -> None:
    """A module's own files and non-module subfolders; child modules stay out."""
    destination.mkdir(parents=True, exist_ok=True)
    for item in source.iterdir():
        if item.is_dir():
            if not (item / "qmldir").exists():
                shutil.copytree(item, destination / item.name, dirs_exist_ok=True, symlinks=False)
        else:
            shutil.copy2(item, destination / item.name)


def needed(elf: Path) -> list[Path]:
    paths = []
    for line in run(["ldd", str(elf)]).splitlines():
        match = re.search(r"=>\s+(/\S+)", line)
        if match:
            paths.append(Path(match.group(1)))
        elif "not found" in line:
            sys.exit(f"stage_linux_bundle: {elf.name}: {line.strip()}")
    return paths


def is_elf(path: Path) -> bool:
    try:
        with path.open("rb") as handle:
            return handle.read(4) == b"\x7fELF"
    except OSError:
        return False


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--qml", type=Path, default=ROOT / "qml")
    arguments = parser.parse_args()

    patchelf = os.environ.get("PATCHELF") or shutil.which("patchelf")
    if not patchelf:
        sys.exit("stage_linux_bundle: patchelf not found (set PATCHELF)")
    qt_libs = qt_query("QT_INSTALL_LIBS")
    qt_plugins = qt_query("QT_INSTALL_PLUGINS")
    qt_qml = qt_query("QT_INSTALL_QML")

    out = arguments.output
    if out.exists():
        shutil.rmtree(out)
    (out / "lib").mkdir(parents=True)
    executable = out / "gitlama"
    shutil.copy2(arguments.binary, executable)

    # QML modules: the scanned imports, closed over qmldir dependencies.
    pending = sorted(scan_imports(arguments.qml, qt_qml) | set(EXTRA_MODULES))
    modules: dict[str, Path] = {}
    while pending:
        uri = pending.pop()
        if uri in modules:
            continue
        path = module_dir(qt_qml, uri)
        if path is None:
            continue
        modules[uri] = path
        pending.extend(qmldir_dependencies(path / "qmldir"))
        # A module's parent URI may hold its plugin (QtQuick for QtQuick.Window).
        parent = uri.rsplit(".", 1)[0]
        if parent != uri and module_dir(qt_qml, parent):
            pending.append(parent)
    for uri, path in sorted(modules.items()):
        copy_module(path, out / "qml" / path.relative_to(qt_qml))

    for directory, names in PLUGINS.items():
        source = qt_plugins / directory
        if not source.is_dir():
            continue
        for plugin in sorted(source.iterdir()):
            if plugin.suffix == ".so" and (names is None or plugin.name in names):
                (out / "plugins" / directory).mkdir(parents=True, exist_ok=True)
                shutil.copy2(plugin, out / "plugins" / directory / plugin.name)

    # The library closure of every ELF in the bundle.
    elves = [path for path in out.rglob("*") if path.is_file() and is_elf(path)]
    bundled: dict[str, Path] = {}
    queue = list(elves)
    while queue:
        elf = queue.pop()
        for dependency in needed(elf):
            if BUNDLED_LIBRARIES.match(dependency.name) and dependency.name not in bundled:
                bundled[dependency.name] = dependency
                target = out / "lib" / dependency.name
                shutil.copy2(dependency.resolve(), target)
                queue.append(target)

    # RUNPATHs into the bundle.
    for path in out.rglob("*"):
        if not path.is_file() or not is_elf(path):
            continue
        relative = os.path.relpath(out / "lib", path.parent)
        rpath = "$ORIGIN" if relative == "." else f"$ORIGIN/{relative}"
        subprocess.check_call([patchelf, "--set-rpath", rpath, str(path)])

    (out / "qt.conf").write_text(
        "[Paths]\nPrefix=.\nLibraries=lib\nPlugins=plugins\nQmlImports=qml\n", encoding="utf-8"
    )
    size = sum(path.stat().st_size for path in out.rglob("*") if path.is_file())
    print(f"stage_linux_bundle: {len(modules)} QML modules, {len(bundled)} libraries, {size / 1048576:.1f} MiB in {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
