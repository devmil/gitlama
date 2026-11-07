#!/usr/bin/env python3
"""The devmil-git revision GitLama is built and released against.

`rust-core/Cargo.toml` pins devmil-git as a Git dependency at one exact revision; helper
packaging and the helper compatibility record read that revision from here. `--check`
(run by verify.sh) fails when `rust-core/Cargo.lock` resolves another revision.

  shared_git_pin.py           print the pinned revision
  shared_git_pin.py --check   compare the lockfile with the pin

To build against a local devmil-git checkout while changing it, patch the dependency
without editing the repository, in your user-level `~/.cargo/config.toml`. The patch
applies only to crates that depend on this exact URL:

  [patch."https://github.com/devmil/devmil-rust-git"]
  devmil-git = { path = "/absolute/path/to/devmil-rust-git" }

`--locked` builds and verify.sh fail while the patch is active. Publish the change, move
the revision in `rust-core/Cargo.toml`, then remove the patch before committing.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "rust-core" / "Cargo.toml"
LOCKFILE = ROOT / "rust-core" / "Cargo.lock"
DEPENDENCY = re.compile(
    r'(?m)^devmil-git\s*=\s*\{[^\n]*git\s*=\s*"(?P<url>[^"]+)"[^\n]*rev\s*=\s*"(?P<rev>[0-9a-f]{40})"'
)


class PinError(Exception):
    pass


def pin(manifest: Path = MANIFEST) -> tuple[str, str]:
    """The devmil-git repository URL and revision the manifest pins."""
    match = DEPENDENCY.search(manifest.read_text(encoding="utf-8"))
    if match is None:
        raise PinError("rust-core/Cargo.toml must pin devmil-git as a Git dependency with rev")
    return match.group("url"), match.group("rev")


def revision(manifest: Path = MANIFEST) -> str:
    return pin(manifest)[1]


def check(manifest: Path = MANIFEST, lockfile: Path = LOCKFILE) -> list[str]:
    url, expected = pin(manifest)
    lock = lockfile.read_text(encoding="utf-8")
    sources = re.findall(
        r'(?m)^name = "devmil-git"\nversion = "[^"]+"\nsource = "git\+([^?"]+)\?rev=([0-9a-f]{40})#([0-9a-f]{40})"',
        lock,
    )
    if len(sources) != 1:
        return ["rust-core/Cargo.lock must resolve exactly one devmil-git Git source"]
    locked_url, requested, resolved = sources[0]
    problems = []
    if locked_url != url:
        problems.append(f"Cargo.lock resolves devmil-git from {locked_url}, not {url}")
    if requested != expected or resolved != expected:
        problems.append(
            f"Cargo.lock resolves devmil-git at {resolved[:12]}, but Cargo.toml pins {expected[:12]}"
        )
    return problems


def main(arguments: list[str]) -> int:
    try:
        if not arguments:
            print(revision())
            return 0
        if arguments != ["--check"]:
            print(__doc__, file=sys.stderr)
            return 2
        problems = check()
    except (OSError, PinError) as error:
        print(f"shared Git pin: {error}", file=sys.stderr)
        return 1
    if not problems:
        print(f"devmil-git is locked at the pin {revision()[:12]}")
        return 0
    for problem in problems:
        print(f"shared Git pin: {problem}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
