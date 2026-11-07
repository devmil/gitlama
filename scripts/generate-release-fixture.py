#!/usr/bin/env python3
"""Refresh the release index and appcast fixtures shared with the application.

The production manifest and appcast rules write these files, signed with a
key that exists only for tests. The Dart update service parses the index and
the package tests verify every signature, so a change to the metadata contract
fails on both sides. Run without arguments to refresh, with --check to compare.
"""

from __future__ import annotations

import argparse
from pathlib import Path
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from scripts.lib.package_contract import TARGETS, Version, artifact_name  # noqa: E402
from scripts.lib.release_appcast import build_appcast  # noqa: E402
from scripts.lib.release_manifest import build_manifest, encode, merge  # noqa: E402
from scripts.lib.release_signing import (  # noqa: E402
    PKCS8_SEED_PREFIX, public_key_base64, sign_update_archive,
)


ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "test/fixtures"
# TEST ONLY. This seed is public and signs nothing but these fixtures.
TEST_ONLY_SEED = bytes(range(1, 33))
# The first release predates the in-app updater and has no update signature.
RELEASES = (
    (Version("1.4.0-beta.3", 40), "beta", False),
    (Version("1.4.0", 41), "stable", True),
    (Version("1.5.0-beta.1", 42), "beta", True),
)
NOTES = ("Fetch & pull show <progress> in the operation center.", "Faster history.")


def artifact_bytes(version: Version, target: tuple[str, str, str]) -> bytes:
    return f"GitLama fixture {version.marketing}+{version.build} {'/'.join(target)}\n".encode()


def write_candidate(directory: Path, version: Version) -> None:
    directory.mkdir()
    for target in TARGETS:
        (directory / artifact_name(version, *target)).write_bytes(artifact_bytes(version, target))


def generate() -> dict[str, bytes]:
    with tempfile.TemporaryDirectory(prefix="gitlama-release-fixture-") as temporary:
        root = Path(temporary)
        key = root / "test-only-key.der"
        key.write_bytes(PKCS8_SEED_PREFIX + TEST_ONLY_SEED)
        key.chmod(0o600)
        document = None
        for version, channel, signed in RELEASES:
            candidate = root / f"candidate-{version.build}"
            write_candidate(candidate, version)
            current = build_manifest(
                candidate, version,
                f"https://github.com/devmil/gitlama/releases/download/v{version.marketing}-{version.build}",
                channel, notes=NOTES,
                sign_update=(lambda path: sign_update_archive(path, key_file=key)) if signed else None,
            )
            document = current if document is None else merge(document, current)
        assert document is not None
        return {
            "release_index.json": encode(document),
            "appcast.xml": build_appcast(document),
            "release_test_only.pub": public_key_base64(key_file=key).encode("ascii") + b"\n",
        }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    options = parser.parse_args()
    stale = []
    for name, value in generate().items():
        path = FIXTURES / name
        if options.check:
            if not path.is_file() or path.read_bytes() != value:
                stale.append(name)
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(value)
    if stale:
        print("stale release fixtures: " + ", ".join(stale)
              + "; run python3 scripts/generate-release-fixture.py", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
