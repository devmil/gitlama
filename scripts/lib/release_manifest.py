"""Build the bounded, retained GitLama release manifest."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any, Callable, Iterable
from urllib.parse import quote, urlsplit

from .package_contract import (
    TARGETS,
    Version,
    artifact_name,
    REMOTE_HELPER_TARGETS,
    RemoteHelperTarget,
    remote_helper_archive_name,
    remote_helper_metadata_name,
)


CHANNELS = frozenset({"stable", "beta"})
MAX_RELEASES_PER_CHANNEL = 5
MINIMUM_SYSTEM = {
    "macos": "macOS 13.0 and Git 2.39",
    "linux": "glibc 2.35 and Git 2.39",
    "windows": "Windows 10 version 1809 and Git 2.39",
}
TRUST = {
    "checksum": "sha256",
    "manifest_signature": "Ed25519 detached signature over exact JSON bytes",
    "signature_encoding": "base64",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _https_base(value: str) -> str:
    parsed = urlsplit(value)
    if (parsed.scheme != "https" or not parsed.hostname or parsed.username
            or parsed.password or parsed.query or parsed.fragment):
        raise ValueError("release base URL must be unauthenticated HTTPS")
    return value.rstrip("/")


def artifact_paths(directory: Path, version: Version) -> list[Path]:
    expected = {artifact_name(version, *target) for target in TARGETS}
    actual = {path.name for path in directory.iterdir() if path.is_file()}
    missing = expected - actual
    helper: set[str] = set()
    for target in REMOTE_HELPER_TARGETS:
        pair = {remote_helper_archive_name(version, target.name),
                remote_helper_metadata_name(version, target.name)}
        # Remote helpers are optional, but an archive never travels without its metadata.
        if actual & pair and not pair <= actual:
            missing |= pair - actual
        helper |= pair
    unexpected = actual - expected - helper - {"release-state.json"}
    if missing or unexpected:
        detail = []
        if missing:
            detail.append("missing " + ", ".join(sorted(missing)))
        if unexpected:
            detail.append("unexpected " + ", ".join(sorted(unexpected)))
        raise ValueError("candidate directory is not the exact release set: " + "; ".join(detail))
    paths = [directory / name for name in sorted(expected)]
    if any(path.is_symlink() or not path.is_file() or path.stat().st_size < 1 for path in paths):
        raise ValueError("release artifacts must be nonempty regular files")
    return paths


def remote_helper_record(directory: Path, version: Version, base: str,
                         target: RemoteHelperTarget = REMOTE_HELPER_TARGETS[0]) -> dict[str, Any] | None:
    """The signed-manifest record of the release's remote helper for ``target``, if it was built.

    The metadata written by scripts/package_remote_helper.py must describe the exact archive
    bytes; the manifest signature then authenticates the helper's digest and build identity.
    """
    archive = directory / remote_helper_archive_name(version, target.name)
    metadata_path = directory / remote_helper_metadata_name(version, target.name)
    if not archive.exists() and not metadata_path.exists():
        return None
    if archive.is_symlink() or metadata_path.is_symlink() or not archive.is_file() or not metadata_path.is_file():
        raise ValueError("remote helper files must be regular files")
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    build_id = metadata.get("build_id")
    if (metadata.get("schema_version") != 1 or metadata.get("kind") != "gitlama-remote-helper"
            or metadata.get("version") != version.marketing or metadata.get("build") != version.build
            or metadata.get("file") != archive.name
            or metadata.get("target") != target.triple
            or metadata.get("protocol_major") != 1 or type(metadata.get("protocol_minor")) is not int
            or not isinstance(build_id, str) or len(build_id) != 40
            or any(character not in "0123456789abcdef" for character in build_id)
            or metadata.get("minimum_system") != target.minimum_system):
        raise ValueError("remote helper metadata does not describe this release")
    size = archive.stat().st_size
    digest = sha256(archive)
    if metadata.get("bytes") != size or metadata.get("sha256") != digest or size < 1:
        raise ValueError("remote helper metadata does not match the archive")
    return {
        "platform": target.platform, "architecture": target.architecture,
        "target": metadata["target"],
        "file": archive.name, "url": f"{base}/{quote(archive.name)}",
        "bytes": size, "sha256": digest, "build_id": build_id,
        "protocol_major": 1, "protocol_minor": metadata["protocol_minor"],
        "minimum_system": target.minimum_system,
    }


# Targets the in-app updater installs; each carries a signature over its bytes.
UPDATE_TARGETS = frozenset({("macos", "arm64", "dmg")})


def build_manifest(directory: Path, version: Version, base_url: str, channel: str,
                   *, notes: Iterable[str] = (),
                   sign_update: Callable[[Path], str] | None = None) -> dict[str, Any]:
    if channel not in CHANNELS:
        raise ValueError("release channel must be stable or beta")
    prerelease = version.parts[3]
    if (channel == "stable" and prerelease is not None) or (channel == "beta" and prerelease is None):
        raise ValueError("release version does not match its channel")
    base = _https_base(base_url)
    target_by_name = {artifact_name(version, *target): target for target in TARGETS}
    assets = []
    for path in artifact_paths(directory, version):
        platform, architecture, format_ = target_by_name[path.name]
        asset = {
            "platform": platform, "architecture": architecture, "format": format_,
            "file": path.name, "url": f"{base}/{quote(path.name)}",
            "bytes": path.stat().st_size, "sha256": sha256(path),
            "minimum_system": MINIMUM_SYSTEM[platform],
        }
        if sign_update is not None and (platform, architecture, format_) in UPDATE_TARGETS:
            asset["update_signature"] = sign_update(path)
        assets.append(asset)
    note_items = list(notes)
    if len(note_items) > 64 or any(not isinstance(item, str) or not item or len(item) > 4096 for item in note_items):
        raise ValueError("release notes are invalid")
    release: dict[str, Any] = {
        "version": version.marketing, "build": version.build,
        "tag": f"v{version.marketing}-{version.build}", "channel": channel,
        "assets": assets,
    }
    if note_items:
        release["notes"] = note_items
    helpers = [
        record for target in REMOTE_HELPER_TARGETS
        if (record := remote_helper_record(directory, version, base, target)) is not None
    ]
    if helpers:
        release["remote_helpers"] = helpers
    return {"schema_version": 1, "product": "GitLama", "trust": TRUST,
            "latest": release, "releases": [release]}


def retain(manifest: dict[str, Any]) -> dict[str, Any]:
    if manifest.get("schema_version") != 1 or manifest.get("product") != "GitLama":
        raise ValueError("release manifest schema is unsupported")
    releases = manifest.get("releases")
    if not isinstance(releases, list):
        raise ValueError("release manifest has no release history")
    channels: dict[str, list[dict[str, Any]]] = {key: [] for key in CHANNELS}
    tags: set[str] = set()
    builds: set[int] = set()
    for release in releases:
        if not isinstance(release, dict) or release.get("channel") not in CHANNELS:
            raise ValueError("release history contains an invalid record")
        tag, build = release.get("tag"), release.get("build")
        if not isinstance(tag, str) or type(build) is not int or build < 1:
            raise ValueError("release history contains an invalid identity")
        if tag in tags or build in builds:
            raise ValueError("release history repeats a tag or build")
        tags.add(tag); builds.add(build)
        channels[release["channel"]].append(release)
    retained = []
    for values in channels.values():
        retained.extend(sorted(values, key=lambda item: item["build"], reverse=True)[:MAX_RELEASES_PER_CHANNEL])
    retained.sort(key=lambda item: item["build"], reverse=True)
    if not retained:
        raise ValueError("release history is empty")
    return {"schema_version": 1, "product": "GitLama", "trust": TRUST,
            "latest": retained[0], "releases": retained}


def merge(existing: dict[str, Any], current: dict[str, Any]) -> dict[str, Any]:
    existing = retain(existing)
    current = retain(current)
    new = current["latest"]
    maximum = max(release["build"] for release in existing["releases"])
    if new["build"] <= maximum:
        raise ValueError("release build replays or precedes retained history")
    return retain({**current, "releases": [new, *existing["releases"]]})


def encode(manifest: dict[str, Any]) -> bytes:
    return (json.dumps(manifest, ensure_ascii=False, sort_keys=True,
                       separators=(",", ":")) + "\n").encode("utf-8")
