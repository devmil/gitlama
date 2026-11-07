#!/usr/bin/env python3
"""Choose the CI lane for a pushed range.

`desktop` builds and tests the application on every platform. `source` runs
only the checks that need neither Flutter nor Rust, for a range that cannot
change the application: website, documentation and signed release metadata,
and a release preparation that only moves the version. The release workflow
builds and qualifies that prepared commit itself.

Anything unknown selects `desktop`.
"""
from __future__ import annotations

import argparse
import fnmatch
import re
import subprocess
import sys
from pathlib import Path
from typing import Callable

ROOT = Path(__file__).resolve().parent.parent
ZERO = "0" * 40

# Paths no application build, bundle or application test reads.
LIGHT_PATTERNS = (
    "webfront/*",
    "release/metadata.json",
    "release/metadata.json.sig",
    "docs/*",
    ".github/workflows/gitlama-pages.yml",
    "README.md",
    "CHANGELOG.md",
    "RELEASE_NOTES.md",
    "AGENTS.md",
    "CONTRIBUTING.md",
    "SECURITY.md",
)
# The design contract check compares these with the Flutter sources.
APPLICATION_PATTERNS = ("docs/design-system/*",)

PLACEHOLDER = "<version>"


def _pubspec(text: str) -> str:
    lines = text.split("\n")
    for index, line in enumerate(lines):
        if re.fullmatch(r"version: \S+", line):
            lines[index] = f"version: {PLACEHOLDER}"
            break
    return "\n".join(lines)


def _after_line(text: str, anchor: str, section_end: str | None) -> str:
    """Takes the version out of the first `version = "…"` line that follows
    the line `anchor`, stopping at a line starting with `section_end`."""
    lines = text.split("\n")
    try:
        start = lines.index(anchor) + 1
    except ValueError:
        return text
    for index in range(start, len(lines)):
        if section_end is not None and lines[index].startswith(section_end):
            break
        if re.fullmatch(r'version = "[^"]+"', lines[index]):
            lines[index] = f'version = "{PLACEHOLDER}"'
            break
    return "\n".join(lines)


def _cargo_manifest(text: str) -> str:
    return _after_line(text, "[package]", "[")


def _cargo_lock(text: str) -> str:
    return _after_line(text, 'name = "gitlama_core"', "[[")


# Files release preparation rewrites, each with the version taken out. A
# change is a version move only when both sides are otherwise identical.
VERSION_FILES: dict[str, Callable[[str], str]] = {
    "VERSION": lambda text: PLACEHOLDER,
    "pubspec.yaml": _pubspec,
    "rust-core/Cargo.toml": _cargo_manifest,
    "rust-core/Cargo.lock": _cargo_lock,
}


def is_light(path: str) -> bool:
    if any(fnmatch.fnmatchcase(path, pattern) for pattern in APPLICATION_PATTERNS):
        return False
    return any(fnmatch.fnmatchcase(path, pattern) for pattern in LIGHT_PATTERNS)


def classify(paths: list[str], read: Callable[[str, str], str | None]) -> tuple[str, str]:
    """Returns the lane and the reason. `read(side, path)` gives the text of
    `path` on the `before` or `after` side, or None when it does not exist."""
    if not paths:
        return "source", "no file changed"
    for path in paths:
        if is_light(path):
            continue
        normalize = VERSION_FILES.get(path)
        if normalize is None:
            return "desktop", f"{path} can change the application"
        before, after = read("before", path), read("after", path)
        if before is None or after is None:
            return "desktop", f"{path} was added or removed"
        if normalize(before) != normalize(after):
            return "desktop", f"{path} changed beyond its version"
    return "source", "only website, documentation, release metadata or the version changed"


def _git(*arguments: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", *arguments], cwd=ROOT, text=True, capture_output=True, check=False
    )


def scope(event: str, before: str, after: str) -> tuple[str, str]:
    if event not in {"push", "pull_request"}:
        return "desktop", f"{event} always builds"
    if not re.fullmatch(r"[0-9a-f]{40}", before) or before == ZERO:
        return "desktop", "the range has no known start"
    if not re.fullmatch(r"[0-9a-f]{40}", after):
        return "desktop", "the range has no known end"
    for revision in (before, after):
        if _git("cat-file", "-e", f"{revision}^{{commit}}").returncode != 0:
            return "desktop", "a commit of the range is unavailable"
    changed = _git("diff", "--name-only", "--no-renames", "-z", before, after)
    if changed.returncode != 0:
        return "desktop", "the changed paths could not be listed"
    paths = [path for path in changed.stdout.split("\0") if path]

    def read(side: str, path: str) -> str | None:
        revision = before if side == "before" else after
        shown = _git("show", f"{revision}:{path}")
        return shown.stdout if shown.returncode == 0 else None

    return classify(paths, read)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--event", required=True)
    parser.add_argument("--before", default="")
    parser.add_argument("--after", default="")
    arguments = parser.parse_args()
    lane, reason = scope(arguments.event, arguments.before, arguments.after)
    print(f"{lane}: {reason}", file=sys.stderr)
    print(f"lane={lane}")


if __name__ == "__main__":
    main()
