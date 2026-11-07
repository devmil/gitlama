"""Immutable release artifact inventory and recovery."""

from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import shutil
import tempfile
from typing import Callable

from .package_contract import SEMVER, TARGETS, Version, artifact_name


STATE_NAME = "release-state.json"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


@dataclass(frozen=True)
class RetainedArtifact:
    name: str
    bytes: int
    sha256: str


@dataclass(frozen=True)
class ReleaseState:
    tag: str
    version: Version
    artifacts: tuple[RetainedArtifact, ...]


def build_state(directory: Path, version: Version) -> dict[str, object]:
    names = sorted(artifact_name(version, *target) for target in TARGETS)
    actual_files = sorted(path.name for path in directory.iterdir() if path.is_file() and path.name != STATE_NAME)
    if actual_files != names:
        missing = sorted(set(names) - set(actual_files))
        unexpected = sorted(set(actual_files) - set(names))
        raise ValueError(f"release artifact set differs: missing={missing}; unexpected={unexpected}")
    return {
        "schema": 1,
        "tag": f"v{version.marketing}-{version.build}",
        "version": version.marketing,
        "build": version.build,
        "artifacts": [
            {
                "name": name,
                "bytes": (directory / name).stat().st_size,
                "sha256": sha256(directory / name),
            }
            for name in names
        ],
    }


def parse_state(data: bytes, expected_tag: str) -> ReleaseState:
    if len(data) > 128 * 1024:
        raise ValueError("release state exceeds 128 KiB")
    try:
        value = json.loads(data)
    except json.JSONDecodeError as error:
        raise ValueError("release state is not valid JSON") from error
    if not isinstance(value, dict) or value.get("schema") != 1 or value.get("tag") != expected_tag:
        raise ValueError("release state identity is invalid")
    marketing = value.get("version")
    build = value.get("build")
    if not isinstance(marketing, str) or SEMVER.fullmatch(marketing) is None:
        raise ValueError("release state version is invalid")
    if not isinstance(build, int) or build <= 0:
        raise ValueError("release state build is invalid")
    version = Version(marketing, build)
    expected_names = {artifact_name(version, *target) for target in TARGETS}
    entries = value.get("artifacts")
    if not isinstance(entries, list) or len(entries) != len(expected_names):
        raise ValueError("release state does not contain six artifacts")
    parsed = []
    for entry in entries:
        if not isinstance(entry, dict):
            raise ValueError("release artifact entry is invalid")
        name = entry.get("name")
        size = entry.get("bytes")
        digest = entry.get("sha256")
        if (
            not isinstance(name, str)
            or name not in expected_names
            or not isinstance(size, int)
            or size <= 0
            or not isinstance(digest, str)
            or len(digest) != 64
            or any(character not in "0123456789abcdef" for character in digest)
        ):
            raise ValueError("release artifact entry failed validation")
        parsed.append(RetainedArtifact(name, size, digest))
    if {item.name for item in parsed} != expected_names:
        raise ValueError("release state has duplicate or missing artifact identities")
    return ReleaseState(expected_tag, version, tuple(sorted(parsed, key=lambda item: item.name)))


def recover(
    state: ReleaseState,
    output: Path,
    retained: Path | None,
    fetch: Callable[[str, Path], bool],
) -> None:
    if output.exists():
        raise ValueError("recovery output must not already exist")
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=f".{output.name}-", dir=output.parent))
    try:
        for artifact in state.artifacts:
            destination = temporary / artifact.name
            retained_file = retained / artifact.name if retained is not None else None
            if retained_file is not None and retained_file.is_file():
                shutil.copyfile(retained_file, destination)
            elif not fetch(artifact.name, destination):
                raise ValueError(f"original artifact is unavailable: {artifact.name}")
            if destination.stat().st_size != artifact.bytes or sha256(destination) != artifact.sha256:
                raise ValueError(f"recovered artifact bytes differ: {artifact.name}")
        (temporary / STATE_NAME).write_text(
            json.dumps(
                {
                    "schema": 1,
                    "tag": state.tag,
                    "version": state.version.marketing,
                    "build": state.version.build,
                    "artifacts": [artifact.__dict__ for artifact in state.artifacts],
                },
                indent=2,
                sort_keys=True,
            )
            + "\n",
            encoding="utf-8",
        )
        temporary.replace(output)
    except BaseException:
        shutil.rmtree(temporary, ignore_errors=True)
        raise
