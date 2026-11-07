"""Git-side release preparation, tag validation and retry planning."""

from __future__ import annotations

from dataclasses import dataclass
import json
from pathlib import Path
import subprocess

from .package_contract import Version
from .release_prepare import bumped, tag_name, validate_channel


@dataclass(frozen=True)
class ReleasePlan:
    mode: str
    channel: str
    bump: str
    version: Version
    tag: str
    revision: str

    def as_json(self) -> str:
        return json.dumps(
            {
                "mode": self.mode,
                "channel": self.channel,
                "bump": self.bump,
                "version": self.version.marketing,
                "build": self.version.build,
                "tag": self.tag,
                "revision": self.revision,
            },
            sort_keys=True,
        )


def git(root: Path, *arguments: str, check: bool = True) -> str:
    result = subprocess.run(
        ["git", *arguments],
        cwd=root,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if check and result.returncode != 0:
        raise ValueError(f"Git command failed: {' '.join(arguments[:2])}")
    return result.stdout.strip()


def require_clean(root: Path) -> None:
    status = git(root, "status", "--porcelain=v1", "--untracked-files=all")
    if status:
        raise ValueError("release preparation requires a clean working tree")


def tag_exists(root: Path, tag: str) -> bool:
    return bool(git(root, "show-ref", "--verify", f"refs/tags/{tag}", check=False))


def require_annotated_tag(root: Path, tag: str) -> str:
    if not tag_exists(root, tag):
        raise ValueError("release tag does not exist")
    if git(root, "cat-file", "-t", f"refs/tags/{tag}") != "tag":
        raise ValueError("release tag must be annotated")
    return git(root, "rev-list", "-n", "1", tag)


def metadata_prepared(root: Path, version: Version, channel: str) -> bool:
    validate_channel(version, channel)
    expected = f"[{version.marketing}] - "
    for name in ("CHANGELOG.md", "RELEASE_NOTES.md"):
        text = (root / name).read_text(encoding="utf-8")
        if f"## {expected}" not in text:
            return False
    return True


def require_version_sync(root: Path, version: Version) -> None:
    pubspec = (root / "pubspec.yaml").read_text(encoding="utf-8")
    cargo = (root / "rust-core/Cargo.toml").read_text(encoding="utf-8")
    lock = (root / "rust-core/Cargo.lock").read_text(encoding="utf-8")
    if f"version: {version.marketing}+{version.build}" not in pubspec:
        raise ValueError("pubspec version differs from VERSION")
    package_block = f'name = "gitlama_core"\nversion = "{version.marketing}"'
    if f'version = "{version.marketing}"' not in cargo or package_block not in lock:
        raise ValueError("Rust package version differs from VERSION")


def plan(root: Path, bump: str, channel: str) -> ReleasePlan:
    current = Version.read(root / "VERSION")
    revision = git(root, "rev-parse", "HEAD")
    if bump == "none":
        validate_channel(current, channel)
        tag = tag_name(current)
        if tag_exists(root, tag):
            tagged_revision = require_annotated_tag(root, tag)
            tagged_version = git(root, "show", f"{tag}:VERSION")
            if tagged_version != f"{current.marketing}\n{current.build}":
                raise ValueError("release tag VERSION differs from the checkout")
            return ReleasePlan("recover", channel, bump, current, tag, tagged_revision)
        if not metadata_prepared(root, current, channel):
            raise ValueError("bump none requires an existing tag or already prepared metadata")
        require_version_sync(root, current)
        return ReleasePlan("resume-prepared", channel, bump, current, tag, revision)

    candidate = bumped(current, bump, channel)
    tag = tag_name(candidate)
    if tag_exists(root, tag):
        raise ValueError("requested bump resolves to an existing immutable tag")
    return ReleasePlan("prepare", channel, bump, candidate, tag, revision)


def create_annotated_tag(root: Path, version: Version, channel: str) -> str:
    require_clean(root)
    validate_channel(version, channel)
    require_version_sync(root, version)
    if not metadata_prepared(root, version, channel):
        raise ValueError("release documents are not prepared")
    tag = tag_name(version)
    if tag_exists(root, tag):
        require_annotated_tag(root, tag)
        if git(root, "rev-list", "-n", "1", tag) != git(root, "rev-parse", "HEAD"):
            raise ValueError("existing release tag points to another commit")
        return tag
    git(
        root,
        "tag",
        "-a",
        tag,
        "-m",
        f"GitLama {version.marketing} ({version.build}) {channel} release",
    )
    return tag
