"""Canonical GitLama release version and document transaction."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date
from pathlib import Path
import re

from .package_contract import SEMVER, Version


CHANNELS = frozenset({"stable", "beta"})
BUMPS = frozenset({"none", "beta", "patch", "minor", "major"})
TAG = re.compile(r"^v(?P<version>[^/]+)-(?P<build>[1-9][0-9]*)$")


def validate_channel(version: Version, channel: str) -> None:
    if channel not in CHANNELS:
        raise ValueError("release channel must be stable or beta")
    prerelease = version.parts[3]
    if channel == "stable" and prerelease is not None:
        raise ValueError("stable releases cannot use a prerelease version")
    if channel == "beta" and not re.fullmatch(r"(?:beta|rc)\.[1-9][0-9]*", prerelease or ""):
        raise ValueError("beta releases require -beta.N or -rc.N")


def bumped(version: Version, kind: str, channel: str) -> Version:
    if kind not in BUMPS:
        raise ValueError("release bump must be none, beta, patch, minor, or major")
    if kind == "none":
        validate_channel(version, channel)
        return version
    major, minor, patch, prerelease = version.parts
    if kind == "beta":
        if channel != "beta":
            raise ValueError("beta bump requires the beta channel")
        match = re.fullmatch(r"beta\.([1-9][0-9]*)", prerelease or "")
        if prerelease is not None and match is None:
            raise ValueError("beta bump requires stable or -beta.N version")
        beta = int(match.group(1)) + 1 if match else 1
        marketing = f"{major}.{minor}.{patch}-beta.{beta}"
    else:
        if kind == "patch":
            patch += 1
        elif kind == "minor":
            minor, patch = minor + 1, 0
        else:
            major, minor, patch = major + 1, 0, 0
        marketing = f"{major}.{minor}.{patch}"
        if channel == "beta":
            marketing += "-beta.1"
    result = Version(marketing, version.build + 1)
    validate_channel(result, channel)
    return result


def tag_name(version: Version) -> str:
    return f"v{version.marketing}-{version.build}"


def parse_tag(value: str) -> Version:
    match = TAG.fullmatch(value)
    if match is None:
        raise ValueError("release tag does not follow vVERSION-BUILD")
    marketing = match["version"]
    if SEMVER.fullmatch(marketing) is None:
        raise ValueError("release tag contains an invalid marketing version")
    return Version(marketing, int(match["build"]))


def _replace_once(text: str, pattern: str, replacement: str, label: str) -> str:
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.MULTILINE)
    if count != 1:
        raise ValueError(f"cannot update {label}")
    return updated


def version_updates(root: Path, version: Version) -> dict[Path, str]:
    pubspec = root / "pubspec.yaml"
    cargo = root / "rust-core/Cargo.toml"
    lock = root / "rust-core/Cargo.lock"
    cargo_text = cargo.read_text(encoding="utf-8")
    package = re.compile(r'(?ms)(\[package\].*?^name = "gitlama_core".*?^version = ")[^"]+(".*?^edition = )')
    cargo_updated, cargo_count = package.subn(rf"\g<1>{version.marketing}\g<2>", cargo_text, count=1)
    if cargo_count != 1:
        raise ValueError("cannot update gitlama_core Cargo version")
    lock_text = lock.read_text(encoding="utf-8")
    lock_pattern = re.compile(r'(?m)(^name = "gitlama_core"\nversion = ")[^"]+(")')
    lock_updated, lock_count = lock_pattern.subn(rf"\g<1>{version.marketing}\g<2>", lock_text, count=1)
    if lock_count != 1:
        raise ValueError("cannot update gitlama_core lock version")
    return {
        root / "VERSION": f"{version.marketing}\n{version.build}\n",
        pubspec: _replace_once(
            pubspec.read_text(encoding="utf-8"),
            r"^version:\s+\S+$",
            f"version: {version.marketing}+{version.build}",
            "pubspec version",
        ),
        cargo: cargo_updated,
        lock: lock_updated,
    }


def write_atomic(updates: dict[Path, str]) -> None:
    temporary_files: list[tuple[Path, Path]] = []
    try:
        for path, text in updates.items():
            temporary = path.with_name(f".{path.name}.release-tmp")
            temporary.write_text(text, encoding="utf-8")
            temporary_files.append((temporary, path))
        for temporary, path in temporary_files:
            temporary.replace(path)
    finally:
        for temporary, _ in temporary_files:
            temporary.unlink(missing_ok=True)


@dataclass(frozen=True)
class Section:
    title: str
    body: str


def sections(text: str) -> tuple[str, list[Section]]:
    matches = list(re.finditer(r"(?m)^## (.+)\n", text))
    if not matches:
        raise ValueError("release document has no level-two sections")
    prefix = text[: matches[0].start()]
    result = []
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        result.append(Section(match.group(1).strip(), text[match.end() : end].strip()))
    return prefix, result


def bullet_items(body: str) -> list[str]:
    return [line.strip()[2:].strip() for line in body.splitlines() if line.strip().startswith("- ")]


def released_notes(text: str, version: Version) -> tuple[str, ...]:
    _, current = sections(text)
    matches = [
        item for item in current
        if item.title.startswith(f"[{version.marketing}] - ")
    ]
    if len(matches) != 1:
        raise ValueError("release document has no unique notes for this version")
    notes = tuple(bullet_items(matches[0].body))
    if not notes:
        raise ValueError("release document has no notes for this version")
    return notes


def render(prefix: str, items: list[Section]) -> str:
    blocks = [prefix.rstrip()]
    for section in items:
        blocks.append(f"## {section.title}\n\n{section.body}".rstrip())
    return "\n\n".join(blocks).rstrip() + "\n"


def promoted_document(
    text: str,
    version: Version,
    channel: str,
    released: date,
    *,
    fallback_items: list[str] | None = None,
) -> str:
    prefix, current = sections(text)
    pending_title = "Unreleased Stable" if channel == "stable" else "Unreleased Beta"
    pending = next((item for item in current if item.title == pending_title), None)
    if pending is None:
        raise ValueError(f"release document is missing {pending_title}")
    items = bullet_items(pending.body)
    if not items:
        items = list(fallback_items or [])
    if not items:
        raise ValueError(f"release document has no {channel} notes")
    released_title = f"[{version.marketing}] - {released.isoformat()}"
    if any(item.title == released_title for item in current):
        return text
    if any(item.title.startswith(f"[{version.marketing}]") for item in current):
        raise ValueError("release document already contains this version")
    empty = Section(pending_title, "")
    next_sections = []
    inserted = False
    for item in current:
        if item.title == pending_title:
            next_sections.append(empty)
            if channel == "beta":
                next_sections.append(Section(released_title, "\n".join(f"- {value}" for value in items)))
                inserted = True
        elif channel == "stable" and item.title == "Unreleased Beta":
            next_sections.append(Section(item.title, ""))
        else:
            next_sections.append(item)
    if channel == "stable":
        insert_at = 2 if len(next_sections) >= 2 else len(next_sections)
        next_sections.insert(insert_at, Section(released_title, "\n".join(f"- {value}" for value in items)))
        inserted = True
    if not inserted:
        raise ValueError("could not insert release document section")
    return render(prefix, next_sections)


def prepare_updates(root: Path, current: Version, updated: Version, channel: str, released: date) -> dict[Path, str]:
    validate_channel(updated, channel)
    updates = version_updates(root, updated) if updated != current else {}
    changelog_path = root / "CHANGELOG.md"
    notes_path = root / "RELEASE_NOTES.md"
    changelog = promoted_document(
        changelog_path.read_text(encoding="utf-8"), updated, channel, released
    )
    changelog_pending = sections(changelog_path.read_text(encoding="utf-8"))[1]
    title = "Unreleased Stable" if channel == "stable" else "Unreleased Beta"
    fallback = bullet_items(next(item.body for item in changelog_pending if item.title == title))
    notes = promoted_document(
        notes_path.read_text(encoding="utf-8"),
        updated,
        channel,
        released,
        fallback_items=fallback,
    )
    updates[changelog_path] = changelog
    updates[notes_path] = notes
    return updates
