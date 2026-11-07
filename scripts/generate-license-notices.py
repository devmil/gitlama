#!/usr/bin/env python3
"""Generate checked-in production dependency notices from locked metadata."""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote, urlparse


ROOT = Path(__file__).resolve().parent.parent
LICENSES = ROOT / "assets" / "licenses"
RUST_OUTPUT = LICENSES / "RUST-DEPENDENCIES.md"
FLUTTER_OUTPUT = LICENSES / "FLUTTER-DEPENDENCIES.md"
PACKAGE_CONFIG = ROOT / ".dart_tool/package_config.json"
NOTICE_PREFIXES = ("LICENSE", "LICENCE", "COPYING", "NOTICE")
RUST_TARGETS = (
    "x86_64-unknown-linux-gnu",
    "aarch64-apple-darwin",
    "x86_64-pc-windows-msvc",
)


def executable(name: str) -> str:
    """Resolve command shims before passing them to subprocess."""
    return shutil.which(name) or name


def file_uri_path_text(uri: str, *, windows: bool) -> str:
    """Convert a package-config file URI to host-native path text."""
    parsed = urlparse(uri)
    if parsed.scheme not in ("", "file"):
        raise ValueError(f"unsupported package root URI scheme: {parsed.scheme}")
    path = unquote(parsed.path)
    if parsed.netloc:
        path = f"//{parsed.netloc}{path}"
    if windows:
        if re.match(r"^/[A-Za-z]:/", path):
            path = path[1:]
        path = path.replace("/", "\\")
    return path


def package_root(uri: str) -> Path:
    parsed = urlparse(uri)
    path = Path(file_uri_path_text(uri, windows=os.name == "nt"))
    if parsed.scheme == "" and not path.is_absolute():
        return (PACKAGE_CONFIG.parent / path).resolve()
    return path


def is_notice(path: Path) -> bool:
    name = path.name.upper()
    return any(
        name == prefix
        or name.startswith(prefix + ".")
        or name.startswith(prefix + "-")
        for prefix in NOTICE_PREFIXES
    )


def notice_files(directory: Path) -> list[Path]:
    return sorted(
        (path for path in directory.iterdir() if path.is_file() and is_notice(path)),
        key=lambda path: path.name.casefold(),
    )


def flutter_notice_files(
    package: dict, directory: Path, *, sdk_license: Path
) -> list[Path]:
    # Cached engine artifacts are platform-specific. In particular,
    # bin/cache/pkg/sky_engine/LICENSE is generated while the SDK is prepared
    # and is not part of the pinned Flutter source revision. Flutter bundles
    # those target-specific notices in its runtime license registry, so the
    # checked-in cross-platform source inventory must use the canonical SDK
    # license for every SDK package instead of whichever host cache ran this
    # generator.
    if package["source"] == "sdk":
        return [sdk_license] if sdk_license.is_file() else []
    notices = notice_files(directory)
    return notices


def rust_packages() -> list[dict]:
    selected: dict[str, dict] = {}
    workspace: set[str] = set()
    # Metadata reads every locked package, including ones a single-target
    # build never downloads. Fetch them all from the lockfile first; a
    # complete cache makes this a no-op.
    subprocess.run(
        [
            executable("cargo"),
            "fetch",
            "--manifest-path",
            str(ROOT / "rust-core/Cargo.toml"),
            "--locked",
        ],
        cwd=ROOT,
        check=True,
        stdout=subprocess.DEVNULL,
    )
    for target in RUST_TARGETS:
        result = subprocess.run(
            [
                executable("cargo"),
                "metadata",
                "--manifest-path",
                str(ROOT / "rust-core/Cargo.toml"),
                "--locked",
                "--offline",
                "--format-version",
                "1",
                "--all-features",
                "--filter-platform",
                target,
            ],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        data = json.loads(result.stdout)
        workspace.update(data["workspace_members"])
        packages = {package["id"]: package for package in data["packages"]}
        root_id = next(
            package_id
            for package_id, package in packages.items()
            if package["name"] == "gitlama_core"
        )
        nodes = {node["id"]: node for node in data["resolve"]["nodes"]}
        pending = [root_id]
        reachable: set[str] = set()
        while pending:
            package_id = pending.pop()
            if package_id in reachable:
                continue
            reachable.add(package_id)
            for dependency in nodes[package_id]["deps"]:
                if any(
                    kind["kind"] in (None, "build")
                    for kind in dependency["dep_kinds"]
                ):
                    pending.append(dependency["pkg"])
        selected.update(
            (package_id, packages[package_id])
            for package_id in reachable
            if package_id not in workspace
        )
    return sorted(
        selected.values(), key=lambda package: (package["name"].casefold(), package["version"])
    )


def flutter_packages() -> tuple[list[tuple[dict, Path]], Path]:
    result = subprocess.run(
        [executable("dart"), "pub", "deps", "--json"],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    dependency_data = json.loads(result.stdout)
    packages = {package["name"]: package for package in dependency_data["packages"]}
    root = packages["gitlama"]
    pending = list(root["directDependencies"])
    reachable: set[str] = set()
    while pending:
        name = pending.pop()
        if name in reachable:
            continue
        reachable.add(name)
        pending.extend(packages[name]["dependencies"])
    config = json.loads(PACKAGE_CONFIG.read_text(encoding="utf-8"))
    roots = {
        package["name"]: package_root(package["rootUri"])
        for package in config["packages"]
    }
    flutter_root = roots["flutter"].parent.parent
    return (
        sorted(
            ((packages[name], roots[name]) for name in reachable),
            key=lambda value: (value[0]["name"].casefold(), value[0]["version"]),
        ),
        flutter_root / "LICENSE",
    )


def render_rust() -> str:
    lines = [
        "# Rust production dependency notices",
        "",
        "Generated from the locked normal/build dependency graphs for GitLama's Linux, macOS and Windows targets.",
        "Do not edit this file by hand; run `scripts/generate-license-notices.py`.",
        "",
    ]
    for package in rust_packages():
        lines.extend(
            [
                f"## {package['name']} {package['version']}",
                "",
                f"Declared license: `{package.get('license') or 'NOT DECLARED'}`  ",
                f"Source: `{package.get('source') or 'reviewed local dependency'}`",
                "",
            ]
        )
        notices = notice_files(Path(package["manifest_path"]).parent)
        if not notices:
            lines.extend(
                ["No top-level license file was present in the resolved source.", ""]
            )
        for notice in notices:
            lines.extend(
                [
                    f"### {notice.name}",
                    "",
                    "```text",
                    notice.read_text(encoding="utf-8", errors="replace").rstrip(),
                    "```",
                    "",
                ]
            )
    return "\n".join(lines)


def render_flutter() -> str:
    lines = [
        "# Flutter production dependency notices",
        "",
        "Generated from the resolved non-development Dart/Flutter graph and hosted package license files.",
        "Flutter SDK packages use the canonical framework license here; Flutter's bundled runtime license registry owns target-specific engine notices.",
        "Do not edit this file by hand; run `scripts/generate-license-notices.py`.",
        "",
    ]
    packages, sdk_license = flutter_packages()
    for package, directory in packages:
        lines.extend([f"## {package['name']} {package['version']}", ""])
        notices = flutter_notice_files(
            package, directory, sdk_license=sdk_license
        )
        if not notices:
            lines.extend(
                ["No top-level license file was present in the resolved source.", ""]
            )
        for notice in notices:
            lines.extend(
                [
                    f"### {notice.name}",
                    "",
                    "```text",
                    notice.read_text(encoding="utf-8", errors="replace").rstrip(),
                    "```",
                    "",
                ]
            )
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    rendered = {
        RUST_OUTPUT: render_rust(),
        FLUTTER_OUTPUT: render_flutter(),
    }
    if args.check:
        stale = [
            path.relative_to(ROOT)
            for path, content in rendered.items()
            if not path.exists() or path.read_text(encoding="utf-8") != content
        ]
        if stale:
            print(
                "stale dependency notices: " + ", ".join(map(str, stale)),
                file=sys.stderr,
            )
            return 1
        return 0
    LICENSES.mkdir(parents=True, exist_ok=True)
    for path, content in rendered.items():
        path.write_text(content, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
