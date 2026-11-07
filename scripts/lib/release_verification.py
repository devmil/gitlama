"""Bounded offline verification of signed release metadata and artifacts."""

from __future__ import annotations

import base64
import binascii
import hashlib
import json
import os
import re
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from urllib.parse import quote, urlsplit

from .package_contract import (
    REMOTE_HELPER_TARGETS, TARGETS, RemoteHelperTarget, Version, artifact_name,
)
from .release_manifest import (
    CHANNELS, MAX_RELEASES_PER_CHANNEL, MINIMUM_SYSTEM, TRUST, UPDATE_TARGETS,
)
from .release_signing import SPKI_PUBLIC_PREFIX, openssl_binary


MAX_MANIFEST_BYTES = 1024 * 1024
MAX_SIGNATURE_BYTES = 256
MAX_PUBLIC_KEY_BYTES = 256
DIGEST = re.compile(r"[0-9a-f]{64}")


@dataclass(frozen=True)
class VerifiedAsset:
    tag: str
    version: str
    build: int
    channel: str
    platform: str
    architecture: str
    format: str
    file: str
    url: str
    bytes: int
    sha256: str
    minimum_system: str
    # Base64 Ed25519 signature over the artifact; releases before the in-app
    # updater have none.
    update_signature: str | None = None


def _bounded(path: Path, maximum: int, subject: str) -> bytes:
    if path.is_symlink() or not path.is_file():
        raise ValueError(f"{subject} must be a regular file")
    if path.stat().st_size > maximum:
        raise ValueError(f"{subject} exceeds {maximum} bytes")
    return path.read_bytes()


def _base64(value: bytes, length: int, subject: str) -> bytes:
    try:
        decoded = base64.b64decode(value.strip(), validate=True)
    except (binascii.Error, ValueError) as error:
        raise ValueError(f"{subject} is not valid base64") from error
    if len(decoded) != length:
        raise ValueError(f"{subject} has an invalid length")
    return decoded


def _verify_detached(signed_file: Path, signed: bytes, public: bytes) -> bool:
    with tempfile.TemporaryDirectory(prefix="gitlama-release-verify-") as temporary:
        root = Path(temporary)
        (root / "public.der").write_bytes(SPKI_PUBLIC_PREFIX + public)
        (root / "signature.bin").write_bytes(signed)
        try:
            result = subprocess.run([
                openssl_binary(), "pkeyutl", "-verify", "-rawin", "-pubin",
                "-inkey", str(root / "public.der"), "-keyform", "DER",
                "-in", str(signed_file), "-sigfile", str(root / "signature.bin"),
            ], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
               env={"PATH": os.environ.get("PATH", "")}, check=False)
        except FileNotFoundError as error:
            raise ValueError("OpenSSL is required for release verification") from error
    return result.returncode == 0


def verify_signature(manifest: Path, signature: Path, public_key: Path) -> bytes:
    """Verify exact bytes before parsing any signed field."""
    raw = _bounded(manifest, MAX_MANIFEST_BYTES, "release manifest")
    signed = _base64(_bounded(signature, MAX_SIGNATURE_BYTES, "release signature"), 64,
                     "release signature")
    public = _base64(_bounded(public_key, MAX_PUBLIC_KEY_BYTES, "release public key"), 32,
                     "release public key")
    with tempfile.TemporaryDirectory(prefix="gitlama-release-verify-") as temporary:
        copy = Path(temporary) / "manifest.json"
        copy.write_bytes(raw)
        if not _verify_detached(copy, signed, public):
            raise ValueError("release manifest signature is invalid")
    return raw


def verify_update_signature(path: Path, asset: "VerifiedAsset", public_key: Path) -> None:
    """Check the signature the in-app updater verifies before installing."""
    if asset.update_signature is None:
        raise ValueError("release artifact has no update signature")
    signed = _base64(asset.update_signature.encode("ascii"), 64, "update signature")
    public = _base64(_bounded(public_key, MAX_PUBLIC_KEY_BYTES, "release public key"), 32,
                     "release public key")
    if path.is_symlink() or not path.is_file():
        raise ValueError("release artifact must be a regular file")
    if not _verify_detached(path, signed, public):
        raise ValueError("release artifact update signature is invalid")


def _unique(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    value: dict[str, Any] = {}
    for key, item in pairs:
        if key in value:
            raise ValueError(f"signed release manifest repeats {key!r}")
        value[key] = item
    return value


def _text(value: Any, subject: str, maximum: int = 512) -> str:
    if not isinstance(value, str) or not value or len(value) > maximum:
        raise ValueError(f"{subject} is invalid")
    return value


def _release(value: Any) -> tuple[dict[str, Any], list[VerifiedAsset]]:
    if not isinstance(value, dict):
        raise ValueError("release record must be an object")
    version_text = _text(value.get("version"), "release version", 128)
    build = value.get("build")
    channel = value.get("channel")
    if type(build) is not int or build < 1 or channel not in CHANNELS:
        raise ValueError("release build or channel is invalid")
    version = Version(version_text, build)
    # Parse the semantic version and enforce stable/beta consistency.
    prerelease = version.parts[3]
    if (channel == "stable" and prerelease is not None) or (channel == "beta" and prerelease is None):
        raise ValueError("release version does not match its channel")
    tag = _text(value.get("tag"), "release tag", 160)
    if tag != f"v{version_text}-{build}":
        raise ValueError("release tag does not match version and build")
    notes = value.get("notes", [])
    if not isinstance(notes, list) or len(notes) > 64:
        raise ValueError("release notes are invalid")
    for note in notes:
        _text(note, "release note", 4096)
    records = value.get("assets")
    if not isinstance(records, list) or len(records) != len(TARGETS):
        raise ValueError("release does not contain the exact target set")
    expected = set(TARGETS)
    assets: list[VerifiedAsset] = []
    seen: set[tuple[str, str, str]] = set()
    for record in records:
        if not isinstance(record, dict):
            raise ValueError("release asset must be an object")
        platform = _text(record.get("platform"), "asset platform", 32)
        architecture = _text(record.get("architecture"), "asset architecture", 32)
        format_ = _text(record.get("format"), "asset format", 32)
        target = (platform, architecture, format_)
        if target not in expected or target in seen:
            raise ValueError("release contains an unexpected or duplicate target")
        seen.add(target)
        filename = _text(record.get("file"), "asset filename", 255)
        if filename != artifact_name(version, *target) or Path(filename).name != filename:
            raise ValueError("release asset filename does not match its identity")
        size = record.get("bytes")
        digest = _text(record.get("sha256"), "asset SHA-256", 64)
        if type(size) is not int or size < 1 or DIGEST.fullmatch(digest) is None:
            raise ValueError("release asset size or digest is invalid")
        url = _text(record.get("url"), "asset URL", 2048)
        parsed = urlsplit(url)
        if (parsed.scheme != "https" or not parsed.hostname or parsed.username
                or parsed.password or parsed.query or parsed.fragment
                or parsed.path.rsplit("/", 1)[-1] != quote(filename)):
            raise ValueError("release artifact URL must be unauthenticated HTTPS and end in its filename")
        minimum = _text(record.get("minimum_system"), "minimum system", 256)
        if minimum != MINIMUM_SYSTEM[platform]:
            raise ValueError("release artifact minimum system is invalid")
        update_signature = record.get("update_signature")
        if update_signature is not None:
            if target not in UPDATE_TARGETS:
                raise ValueError("release asset must not carry an update signature")
            _base64(_text(update_signature, "update signature", 128).encode("ascii"), 64,
                    "update signature")
        assets.append(VerifiedAsset(tag, version_text, build, channel, platform,
                                    architecture, format_, filename, url, size, digest, minimum,
                                    update_signature))
    if seen != expected:
        raise ValueError("release target set is incomplete")
    _remote_helpers(value.get("remote_helpers"), version)
    return value, assets


def _remote_helpers(value: Any, version: Version) -> None:
    """Validates the optional signed remote helper records of a release: at most one per
    supported host platform."""
    if value is None:
        return
    if (not isinstance(value, list) or not 1 <= len(value) <= len(REMOTE_HELPER_TARGETS)
            or not all(isinstance(record, dict) for record in value)):
        raise ValueError("release remote helper record is invalid")
    seen: set[str] = set()
    for record in value:
        target = next((target for target in REMOTE_HELPER_TARGETS
                       if target.triple == record.get("target")), None)
        if target is None or target.name in seen:
            raise ValueError("release remote helper identity is invalid")
        seen.add(target.name)
        _remote_helper(record, version, target)


def _remote_helper(record: dict[str, Any], version: Version, target: RemoteHelperTarget) -> None:
    expected_keys = {
        "platform", "architecture", "target", "file", "url", "bytes", "sha256",
        "build_id", "protocol_major", "protocol_minor", "minimum_system",
    }
    if set(record) != expected_keys:
        raise ValueError("release remote helper record has unexpected fields")
    filename = _text(record["file"], "remote helper filename", 255)
    if (record["platform"] != target.platform or record["architecture"] != target.architecture
            or filename != f"gitlama-remote-helper-{version.marketing}-{version.build}-{target.name}.tar.gz"):
        raise ValueError("release remote helper identity is invalid")
    build_id = _text(record["build_id"], "remote helper build", 40)
    if len(build_id) != 40 or any(character not in "0123456789abcdef" for character in build_id):
        raise ValueError("release remote helper build is invalid")
    if (type(record["bytes"]) is not int or record["bytes"] < 1
            or DIGEST.fullmatch(_text(record["sha256"], "remote helper SHA-256", 64)) is None
            or record["protocol_major"] != 1 or type(record["protocol_minor"]) is not int):
        raise ValueError("release remote helper size, digest or protocol is invalid")
    parsed = urlsplit(_text(record["url"], "remote helper URL", 2048))
    if (parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password
            or parsed.query or parsed.fragment or parsed.path.rsplit("/", 1)[-1] != quote(filename)):
        raise ValueError("release remote helper URL must be unauthenticated HTTPS and end in its filename")
    _text(record["minimum_system"], "remote helper minimum system", 256)


def parse_manifest(raw: bytes) -> tuple[dict[str, Any], list[list[VerifiedAsset]]]:
    try:
        document = json.loads(raw, object_pairs_hook=_unique)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ValueError("signed release manifest is not valid UTF-8 JSON") from error
    if not isinstance(document, dict) or document.get("schema_version") != 1 \
            or document.get("product") != "GitLama" or document.get("trust") != TRUST:
        raise ValueError("release manifest schema, product, or trust policy is unsupported")
    releases = document.get("releases")
    if not isinstance(releases, list) or not 1 <= len(releases) <= 2 * MAX_RELEASES_PER_CHANNEL:
        raise ValueError("release history count is invalid")
    parsed: list[list[VerifiedAsset]] = []
    builds: list[int] = []
    tags: set[str] = set()
    per_channel = {channel: 0 for channel in CHANNELS}
    for raw_release in releases:
        release, assets = _release(raw_release)
        build, tag, channel = release["build"], release["tag"], release["channel"]
        if tag in tags or build in builds:
            raise ValueError("release history repeats a tag or build")
        tags.add(tag); builds.append(build); per_channel[channel] += 1
        parsed.append(assets)
    if builds != sorted(builds, reverse=True) or any(value > MAX_RELEASES_PER_CHANNEL for value in per_channel.values()):
        raise ValueError("release history is not monotonically retained")
    latest, _ = _release(document.get("latest"))
    if latest != releases[0]:
        raise ValueError("latest release is not the first retained release")
    return document, parsed


def verify_manifest(manifest: Path, signature: Path, public_key: Path) -> tuple[dict[str, Any], list[list[VerifiedAsset]]]:
    return parse_manifest(verify_signature(manifest, signature, public_key))


def select_asset(raw: bytes, *, platform: str, architecture: str, format_: str,
                 minimum_build: int = 0) -> VerifiedAsset:
    _, releases = parse_manifest(raw)
    latest = releases[0]
    if latest[0].build < minimum_build:
        raise ValueError("release manifest replays an older build")
    matches = [item for item in latest if (item.platform, item.architecture, item.format)
               == (platform, architecture, format_)]
    if len(matches) != 1:
        raise ValueError("release manifest has no exact target match")
    return matches[0]


def verify_artifact(path: Path, asset: VerifiedAsset) -> None:
    if path.is_symlink() or not path.is_file() or path.name != asset.file:
        raise ValueError("release artifact path does not match signed metadata")
    if path.stat().st_size != asset.bytes:
        raise ValueError("release artifact size differs from signed metadata")
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    if digest != asset.sha256:
        raise ValueError("release artifact digest differs from signed metadata")
