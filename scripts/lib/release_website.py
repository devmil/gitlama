"""Guard the signed website index and update feed."""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import tempfile
from pathlib import Path
from typing import Any

from .release_appcast import build_appcast
from .release_verification import verify_manifest


APPCAST_FILE = "appcast.xml"
MAX_RECEIPT_BYTES = 4096


def _hash(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _atomic(path: Path, value: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary = Path(name)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(value); stream.flush(); os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def write_receipt(output: Path, manifest: Path, tag: str) -> None:
    value = {"schema": 1, "tag": tag, "manifest_sha256": _hash(manifest),
             "github_release": "verified-published"}
    _atomic(output, (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode())


def _receipt(path: Path, manifest: Path, tag: str) -> None:
    if path.stat().st_size > MAX_RECEIPT_BYTES:
        raise ValueError("publication receipt is oversized")
    try:
        value = json.loads(path.read_bytes())
    except (UnicodeError, ValueError) as error:
        raise ValueError("publication receipt is malformed") from error
    expected = {"schema": 1, "tag": tag, "manifest_sha256": _hash(manifest),
                "github_release": "verified-published"}
    if value != expected:
        raise ValueError("publication receipt does not match the verified GitHub release")


def sync_index(webfront: Path, manifest: Path, signature: Path, public_key: Path,
               receipt: Path, tag: str) -> None:
    document, _ = verify_manifest(manifest, signature, public_key)
    if document["latest"]["tag"] != tag:
        raise ValueError("website candidate identifies another release")
    _receipt(receipt, manifest, tag)
    channels: dict[str, dict[str, Any]] = {}
    for release in document["releases"]:
        channels.setdefault(release["channel"], {
            "tag": release["tag"], "version": release["version"], "build": release["build"]})
    appcast = build_appcast(document)
    data = webfront / "_data"
    # All validation above completes before any mutable pointer changes.
    _atomic(data / "releases.json.sig", signature.read_bytes())
    # The macOS updater reads this feed; every item is a signed package from
    # the verified manifest.
    _atomic(webfront / APPCAST_FILE, appcast)
    _atomic(data / "channels.json", (json.dumps({"schema": 1, "channels": channels},
                                                sort_keys=True, separators=(",", ":")) + "\n").encode())
    # The page reads this pointer. Replace it last so a prior sidecar write
    # failure cannot advertise an index that was not fully staged.
    _atomic(data / "releases.json", manifest.read_bytes())
