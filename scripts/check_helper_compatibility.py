#!/usr/bin/env python3
"""Keeps the remote helper's compatibility version honest.

GitLama connects only to a helper whose ID equals its own. The ID derives from the
compatibility version in rust-core/remote-helper/COMPATIBILITY, not from the source commit,
so a release that leaves the helper alone keeps working with the helper hosts already run.

The file also records a fingerprint of everything the helper is built from in this repository:
its own sources, the application crate it runs (domain, use cases, feature modules, the wire
adapter and its generated codecs, the session policy), the bridge types it carries and the
remote surface. When any of them changes, the version must rise; this check fails until it
does. The desktop library (rust-core/src: the FRB facade and desktop-only services) is outside
the fingerprint, since the helper never builds it. A change inside the fingerprint that cannot
change what the helper does (tests, documentation, a refactor with identical output) keeps the
version only by an explicit decision: record it with --keep-version.

The helper also runs devmil-git's Git behaviour, so the file records the devmil-git revision
(pinned in rust-core/Cargo.toml) it was recorded for. Moving that pin needs an explicit decision:
raise the version and record, or record with --keep-shared-git when the move cannot change
what the helper does.

  check_helper_compatibility.py                      fail when the record is stale
  check_helper_compatibility.py --record             record the fingerprint; refused when
                                                     the contract or the devmil-git pin
                                                     changed and the version did not
  check_helper_compatibility.py --record --keep-shared-git
                                                     also accept a moved devmil-git pin
                                                     at the same version
  check_helper_compatibility.py --record --keep-version
                                                     accept a changed fingerprint at the
                                                     same version: the change cannot alter
                                                     what the helper does
  check_helper_compatibility.py --record --keep-version --keep-shared-git
                                                     both at once
"""
from __future__ import annotations

import hashlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
COMPATIBILITY = ROOT / "rust-core" / "remote-helper" / "COMPATIBILITY"
SHARED_GIT_MANIFEST = Path("rust-core") / "Cargo.toml"

# Everything the helper is built from in this repository, apart from devmil-git (pinned below).
CONTRACT_GLOBS = (
    "rust-core/remote-helper/Cargo.toml",
    "rust-core/remote-helper/src/**/*.rs",
    "rust-core/application/Cargo.toml",
    "rust-core/application/build.rs",
    "rust-core/application/src/**/*.rs",
    "rust-core/contract/Cargo.toml",
    "rust-core/contract/src/**/*.rs",
    "tooling/remote_wire/surface.json",
    "tooling/remote_wire/contract.json",
)
# Application sources the helper never compiles: the image codecs it builds without.
EXCLUDED_GLOBS = ("rust-core/application/src/image_decoder/engine.rs",)

HEADER = (
    "# The remote helper's compatibility version and the fingerprint of the sources it is built from.\n"
    "# Raise the version for any change to what the helper accepts, returns or does; read\n"
    "# \"Remote helper compatibility\" in AGENTS.md. Record with\n"
    "# scripts/check_helper_compatibility.py --record.\n"
)

MAX_VERSION = 999_999


class CompatibilityError(Exception):
    pass


def contract_files(root: Path = ROOT) -> list[Path]:
    files = {path for pattern in CONTRACT_GLOBS for path in root.glob(pattern) if path.is_file()}
    files -= {path for pattern in EXCLUDED_GLOBS for path in root.glob(pattern)}
    return sorted(files, key=lambda path: path.relative_to(root).as_posix())


def fingerprint(root: Path = ROOT) -> str:
    digest = hashlib.sha256()
    for path in contract_files(root):
        digest.update(path.relative_to(root).as_posix().encode("utf-8") + b"\0")
        # Line endings depend on the checkout, not on the contract.
        content = path.read_bytes().replace(b"\r\n", b"\n")
        digest.update(len(content).to_bytes(8, "big") + content)
    return digest.hexdigest()


def read(path: Path = COMPATIBILITY) -> tuple[int, str | None, int | None]:
    """The declared version, the recorded fingerprint and the version it was recorded for."""
    values: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        key, _, value = line.partition(" ")
        values[key] = value.strip()
    version = values.get("version", "")
    if not re.fullmatch(r"[1-9][0-9]*", version) or int(version) > MAX_VERSION:
        raise CompatibilityError(f"{path.name}: 'version' must be a positive integer")
    recorded = values.get("contract")
    if recorded is not None and not re.fullmatch(r"[0-9a-f]{64}", recorded):
        raise CompatibilityError(f"{path.name}: 'contract' must be a SHA-256")
    recorded_for = values.get("recorded-for")
    if recorded_for is not None and not re.fullmatch(r"[1-9][0-9]*", recorded_for):
        raise CompatibilityError(f"{path.name}: 'recorded-for' must be a version")
    return int(version), recorded, None if recorded_for is None else int(recorded_for)


def recorded_shared_git(path: Path = COMPATIBILITY) -> str | None:
    """The devmil-git revision the record was made for, if any."""
    for line in path.read_text(encoding="utf-8").splitlines():
        key, _, value = line.strip().partition(" ")
        if key == "shared-git":
            return value.strip()
    return None


def shared_git_pin(root: Path = ROOT) -> str | None:
    """The pinned devmil-git revision, or None where the tree has no manifest pin."""
    manifest = root / SHARED_GIT_MANIFEST
    if not manifest.is_file():
        return None
    match = re.search(
        r'(?m)^devmil-git\s*=\s*\{[^\n]*rev\s*=\s*"([^"]*)"', manifest.read_text(encoding="utf-8")
    )
    if match is None:
        return None
    if not re.fullmatch(r"[0-9a-f]{40}", match.group(1)):
        raise CompatibilityError(f"{SHARED_GIT_MANIFEST.as_posix()} must pin devmil-git to a 40-hex revision")
    return match.group(1)


def shared_git_decision(previous: str | None, current: str | None, version: int) -> str:
    return (
        f"The devmil-git pin moved from {(previous or 'none')[:12]} to {(current or 'none')[:12]}.\n"
        "The helper runs devmil-git's Git behaviour. If the move changes what the helper\n"
        f"does, raise 'version' to {version + 1} and run\n"
        "  python3 scripts/check_helper_compatibility.py --record\n"
        "If it cannot, keep the version with\n"
        "  python3 scripts/check_helper_compatibility.py --record --keep-shared-git"
    )


def helper_id(version: int) -> str:
    """The 40-digit ID a helper of ``version`` reports and is installed under."""
    return str(version).rjust(40, "0")


def check(root: Path = ROOT, path: Path = COMPATIBILITY) -> str:
    version, recorded, recorded_for = read(path)
    current = fingerprint(root)
    pin = shared_git_pin(root)
    recorded_pin = recorded_shared_git(path)
    if recorded == current and recorded_for == version and pin != recorded_pin:
        raise CompatibilityError(shared_git_decision(recorded_pin, pin, version))
    if recorded == current and recorded_for == version:
        return f"remote helper compatibility {version}: contract unchanged"
    if recorded != current and recorded_for == version:
        raise CompatibilityError(
            "The remote helper's contract changed but its compatibility version did not.\n"
            f"Raise 'version' in {path.relative_to(root)} to {version + 1}, then run\n"
            "  python3 scripts/check_helper_compatibility.py --record\n"
            "Hosts then receive the new helper on their next connection. If the change cannot\n"
            "alter what the helper does (tests, documentation, a refactor with identical\n"
            "output), keep the version with\n"
            "  python3 scripts/check_helper_compatibility.py --record --keep-version"
        )
    raise CompatibilityError(
        f"The compatibility record in {path.relative_to(root)} is stale; run\n"
        "  python3 scripts/check_helper_compatibility.py --record"
    )


def record(
    root: Path = ROOT,
    path: Path = COMPATIBILITY,
    *,
    keep_shared_git: bool = False,
    keep_version: bool = False,
) -> str:
    version, recorded, recorded_for = read(path)
    current = fingerprint(root)
    if recorded is not None and recorded != current and recorded_for == version and not keep_version:
        raise CompatibilityError(
            "The helper's contract changed: raise 'version' before recording.\n"
            "A changed contract with an unchanged version would connect new clients to\n"
            "helpers that do not understand them. If the change cannot alter what the\n"
            "helper does (tests, documentation, a refactor with identical output), keep the\n"
            "version with\n"
            "  python3 scripts/check_helper_compatibility.py --record --keep-version"
        )
    pin = shared_git_pin(root)
    recorded_pin = recorded_shared_git(path)
    if (
        recorded is not None
        and recorded_for == version
        and pin != recorded_pin
        and not keep_shared_git
    ):
        raise CompatibilityError(shared_git_decision(recorded_pin, pin, version))
    shared = "" if pin is None else f"shared-git {pin}\n"
    path.write_text(
        f"{HEADER}version {version}\ncontract {current}\nrecorded-for {version}\n{shared}",
        encoding="utf-8",
    )
    return f"recorded remote helper compatibility {version}"


def main(arguments: list[str]) -> int:
    try:
        if arguments == ["--record"]:
            print(record())
        elif arguments == ["--record", "--keep-shared-git"]:
            print(record(keep_shared_git=True))
        elif arguments == ["--record", "--keep-version"]:
            print(record(keep_version=True))
        elif arguments[:1] == ["--record"] and sorted(arguments[1:]) == [
            "--keep-shared-git",
            "--keep-version",
        ]:
            print(record(keep_shared_git=True, keep_version=True))
        elif not arguments:
            print(check())
        else:
            print(__doc__, file=sys.stderr)
            return 2
    except CompatibilityError as error:
        print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
