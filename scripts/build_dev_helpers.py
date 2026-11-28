#!/usr/bin/env python3
"""Builds the remote helpers a build from source offers to install on a host.

Writes `build/remote-helper/<platform>/gitlama-remote-helper` and its descriptor (schema, build
ID, target, SHA-256 and size), which the application checks before offering **Install helper**
(see docs/remote-workspaces/SETUP.md). On Linux it builds the x86_64 helper with the Rust
toolchain alone and the arm64 helper with a cross linker (`aarch64-linux-gnu-gcc`) or
cargo-zigbuild; on a Mac the helper for the Mac's own processor natively and both Linux helpers
with cargo-zigbuild. A helper whose tools are missing is skipped with a note in
`build/remote-helper/build-failure-<platform>.txt`; the application still runs.

`scripts/run-dev.sh` runs this unless GITLAMA_DEV_REMOTE_HELPER=0.
"""
from __future__ import annotations

import hashlib
import json
import os
import platform
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts" / "lib"))
from package_contract import remote_helper_id  # noqa: E402

NAME = "gitlama-remote-helper"
# Glibc floor of the release helpers, so a development helper runs on every supported host.
GLIBC = "2.35"


def target_root() -> Path:
    configured = os.environ.get("CARGO_TARGET_DIR")
    return (ROOT / configured) if configured else ROOT / "rust-core" / "target"


def build(directory: str, triple: str, *, zig: bool = False, environment: dict[str, str] | None = None) -> bool:
    destination = ROOT / "build" / "remote-helper" / directory
    failure = ROOT / "build" / "remote-helper" / f"build-failure-{directory}.txt"

    def fail(reason: str) -> bool:
        failure.parent.mkdir(parents=True, exist_ok=True)
        failure.write_text(reason[-4096:], encoding="utf-8")
        print(f"remote helper {directory}: not built ({failure.relative_to(ROOT)})", file=sys.stderr)
        return False

    tool = "zigbuild" if zig else "build"
    if zig and shutil.which("cargo-zigbuild") is None:
        return fail("cargo-zigbuild is not installed.\n")
    try:
        build_id = remote_helper_id(ROOT)
    except ValueError as error:
        return fail(f"No helper ID: {error}.\n")
    result = subprocess.run(
        [
            "cargo", tool, "--manifest-path", str(ROOT / "rust-core" / "Cargo.toml"), "--locked",
            "--package", NAME, "--profile", "helper-dev",
            "--target", f"{triple}.{GLIBC}" if zig and "linux" in triple else triple,
        ],
        cwd=ROOT,
        env=environment,
        capture_output=True,
        text=True,
    )
    # A bundle left from an earlier build stays; the application checks its build ID and
    # digest before offering it.
    if result.returncode != 0:
        return fail(f"cargo {tool} exited with {result.returncode}.\n{result.stderr}")
    data = (target_root() / triple / "helper-dev" / NAME).read_bytes()
    destination.mkdir(parents=True, exist_ok=True)
    descriptor = destination / f"{NAME}.json"
    # The descriptor is written last: a bundle without one is never offered.
    descriptor.unlink(missing_ok=True)
    helper = destination / NAME
    helper.write_bytes(data)
    helper.chmod(0o755)
    descriptor.write_text(
        json.dumps(
            {
                "schema": 1,
                "build_id": build_id,
                "target": triple,
                "sha256": hashlib.sha256(data).hexdigest(),
                "bytes": len(data),
            },
            separators=(",", ":"),
        )
        + "\n",
        encoding="utf-8",
    )
    failure.unlink(missing_ok=True)
    return True


def main() -> int:
    system = platform.system()
    if system == "Darwin":
        arm = platform.machine() in ("arm64", "aarch64")
        build("macos-arm64" if arm else "macos-x86_64", "aarch64-apple-darwin" if arm else "x86_64-apple-darwin")
        build("linux-x86_64", "x86_64-unknown-linux-gnu", zig=True)
        build("linux-arm64", "aarch64-unknown-linux-gnu", zig=True)
    elif system == "Linux":
        build("linux-x86_64", "x86_64-unknown-linux-gnu")
        if shutil.which("aarch64-linux-gnu-gcc"):
            build(
                "linux-arm64",
                "aarch64-unknown-linux-gnu",
                environment={
                    **os.environ,
                    "CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER": "aarch64-linux-gnu-gcc",
                    "CC_aarch64_unknown_linux_gnu": "aarch64-linux-gnu-gcc",
                },
            )
        else:
            build("linux-arm64", "aarch64-unknown-linux-gnu", zig=True)
    # Windows hosts cannot be remote hosts and builds there bundle no helper.
    return 0


if __name__ == "__main__":
    sys.exit(main())
