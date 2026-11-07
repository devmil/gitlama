#!/usr/bin/env python3
"""Build and archive the remote helper of this source commit for one host platform.

The helper is identified by its compatibility version (rust-core/remote-helper/COMPATIBILITY),
compiled into both the client library and the helper as a 40-digit helper ID; releases that keep
the version share installed helpers. The metadata also records the source commit. The archive is reproducible (fixed timestamps, owners and order) and the
metadata records the build identity, target, protocol, glibc floor and digests. Release
publication carries the metadata in the signed release manifest; users install the archive
manually into ``~/.local/lib/gitlama/remote/<build-id>/`` (docs/remote-workspaces/SETUP.md).
"""
from __future__ import annotations

import argparse
import gzip
import hashlib
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tarfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from lib.package_contract import (  # noqa: E402
    REMOTE_HELPER_TARGETS,
    RemoteHelperTarget,
    Version,
    remote_helper_archive_name,
    remote_helper_id,
    remote_helper_metadata_name,
    remote_helper_target,
    source_date_epoch,
)

ROOT = Path(__file__).resolve().parent.parent
TARGET = "x86_64-unknown-linux-gnu"
GLIBC_FLOOR = (2, 35)
MINIMUM_SYSTEM = REMOTE_HELPER_TARGETS[0].minimum_system
# The oldest macOS a macOS helper runs on, as its minimum system states.
MACOS_DEPLOYMENT_TARGET = "13.0"
BINARY = "gitlama-remote-helper"


archive_name = remote_helper_archive_name
metadata_name = remote_helper_metadata_name


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


# Cross toolchains for Linux targets other than the build host's, as Ubuntu packages them
# (gcc-aarch64-linux-gnu, libc6-dev-arm64-cross, binutils-aarch64-linux-gnu, qemu-user).
CROSS = {
    "aarch64-unknown-linux-gnu": {
        "gcc": "aarch64-linux-gnu-gcc",
        "objdump": "aarch64-linux-gnu-objdump",
        "qemu": "qemu-aarch64",
        "sysroot": "/usr/aarch64-linux-gnu",
    },
}


def glibc_requirement(binary: Path, triple: str = TARGET) -> tuple[int, int] | None:
    """The newest GLIBC symbol version the binary needs, from its dynamic symbol table."""
    cross = CROSS.get(triple, {})
    objdump = shutil.which(cross.get("objdump", "")) if cross else None
    objdump = objdump or shutil.which("objdump")
    if objdump is None:
        raise RuntimeError("objdump is required to check the glibc floor")
    output = subprocess.run([objdump, "-T", str(binary)], capture_output=True, text=True, check=True).stdout
    versions = {
        (int(major), int(minor))
        for major, minor in re.findall(r"GLIBC_(\d+)\.(\d+)", output)
    }
    return max(versions) if versions else None


def build_archive(binary: bytes, epoch: int) -> bytes:
    """A gzip tar holding only the helper, with fixed metadata."""
    payload = io.BytesIO()
    with tarfile.open(fileobj=payload, mode="w", format=tarfile.PAX_FORMAT) as archive:
        entry = tarfile.TarInfo(BINARY)
        entry.size = len(binary)
        entry.mode = 0o755
        entry.mtime = epoch
        entry.uid = entry.gid = 0
        entry.uname = entry.gname = ""
        archive.addfile(entry, io.BytesIO(binary))
    compressed = io.BytesIO()
    with gzip.GzipFile(fileobj=compressed, mode="wb", mtime=epoch, compresslevel=9) as stream:
        stream.write(payload.getvalue())
    return compressed.getvalue()


def metadata(*, version: Version, build_id: str, source_commit: str, shared_revision: str,
             archive: bytes, binary: bytes, glibc: tuple[int, int] | None,
             target: RemoteHelperTarget = REMOTE_HELPER_TARGETS[0]) -> dict:
    return {
        "schema_version": 1,
        "kind": "gitlama-remote-helper",
        "version": version.marketing,
        "build": version.build,
        "build_id": build_id,
        "source_commit": source_commit,
        "target": target.triple,
        "protocol_major": 1,
        "protocol_minor": 0,
        "shared_git_revision": shared_revision,
        "glibc_requirement": None if glibc is None else f"{glibc[0]}.{glibc[1]}",
        "minimum_system": target.minimum_system,
        "install_path": f"~/.local/lib/gitlama/remote/{build_id}/{BINARY}",
        "file": archive_name(version, target.name),
        "bytes": len(archive),
        "sha256": sha256(archive),
        "binary_sha256": sha256(binary),
    }


def in_checkout() -> bool:
    return (ROOT / ".git").exists()


def source_commit() -> str:
    """The commit compiled into the helper. A release container has no Git metadata and
    receives the release revision in ``GITLAMA_SOURCE_COMMIT``."""
    commit = os.environ.get("GITLAMA_SOURCE_COMMIT") or subprocess.run(
        ["git", "-C", str(ROOT), "rev-parse", "HEAD"], capture_output=True, text=True, check=True
    ).stdout.strip()
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise RuntimeError("the source commit is not a 40-hex SHA-1")
    return commit


def shared_revision() -> str:
    """The pinned devmil-git revision, checked against the revision Cargo.lock resolves."""
    sys.path.insert(0, str(ROOT / "scripts"))
    import shared_git_pin

    try:
        pinned = shared_git_pin.revision()
        problems = shared_git_pin.check()
    except (shared_git_pin.PinError, OSError) as error:
        raise RuntimeError(f"the shared Git revision pin cannot be checked: {error}") from error
    if problems:
        raise RuntimeError("; ".join(problems))
    return pinned


def sign_macos(binary: Path) -> None:
    """Signs a macOS helper ad hoc: Apple silicon runs no unsigned code, and a stripped binary
    may lose the linker's signature. A helper copied over SSH carries no quarantine, so hosts
    run it; the macOS package re-signs its copies with the Developer ID for notarization."""
    subprocess.run(["codesign", "--force", "--sign", "-", str(binary)], check=True)
    subprocess.run(["codesign", "--verify", "--strict", str(binary)], check=True)


def reports_build(binary: Path, target: RemoteHelperTarget, build_id: str, commit: str) -> bool:
    """Whether the built helper reports ``build_id`` and ``commit``. A helper this machine can
    run answers ``--version``; another architecture is checked for the embedded values."""
    native = (target.platform, target.architecture) == (
        {"Darwin": "macos", "Linux": "linux"}.get(os.uname().sysname),
        {"aarch64": "arm64", "arm64": "arm64", "x86_64": "x86_64"}.get(os.uname().machine),
    )
    command = [str(binary), "--version"]
    cross = CROSS.get(target.triple)
    if not native and cross and shutil.which(cross["qemu"]) and Path(cross["sysroot"]).is_dir():
        # The cross toolchain's emulator runs the helper against the target's own C library.
        command = [cross["qemu"], "-L", cross["sysroot"], *command]
        native = True
    if native:
        reported = json.loads(
            subprocess.run(command, capture_output=True, text=True, check=True).stdout
        )
        return reported.get("buildId") == build_id and reported.get("sourceCommit") == commit
    data = binary.read_bytes()
    return build_id.encode("ascii") in data and commit.encode("ascii") in data


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--output", type=Path, default=ROOT / "dist")
    parser.add_argument("--target", default=REMOTE_HELPER_TARGETS[0].name,
                        choices=[target.name for target in REMOTE_HELPER_TARGETS],
                        help="the host platform; macOS targets build on macOS")
    parser.add_argument("--allow-dirty", action="store_true",
                        help="development only: package a checkout with local changes")
    parser.add_argument("--skip-glibc-floor", action="store_true",
                        help="development only: package on a host newer than the glibc floor")
    arguments = parser.parse_args()
    dirty = in_checkout() and subprocess.run(
        ["git", "-C", str(ROOT), "status", "--porcelain"], capture_output=True, text=True, check=True
    ).stdout.strip()
    if not in_checkout() and "GITLAMA_SOURCE_COMMIT" not in os.environ:
        parser.error("outside a checkout, GITLAMA_SOURCE_COMMIT must name the release revision")
    if dirty and not arguments.allow_dirty:
        parser.error("the checkout has local changes; a helper must match an exact commit")
    target = remote_helper_target(arguments.target)
    macos = target.platform == "macos"
    if macos and os.uname().sysname != "Darwin":
        parser.error("macOS helpers build on macOS with its SDK and codesign")
    version = Version.read(ROOT / "VERSION")
    commit = source_commit()
    build_id = remote_helper_id(ROOT)
    epoch = source_date_epoch(dict(os.environ))
    environment = {**os.environ, "GITLAMA_SOURCE_COMMIT": commit}
    if arguments.allow_dirty or arguments.skip_glibc_floor:
        environment["GITLAMA_DIAGNOSTICS_DEVELOPMENT"] = "1"
    if macos:
        environment["MACOSX_DEPLOYMENT_TARGET"] = MACOS_DEPLOYMENT_TARGET
    cross = CROSS.get(target.triple)
    if cross and os.uname().machine not in ("aarch64", "arm64") and shutil.which(cross["gcc"]):
        # Link and compile C parts with the cross toolchain, against its glibc.
        variable = target.triple.upper().replace("-", "_")
        environment.setdefault(f"CARGO_TARGET_{variable}_LINKER", cross["gcc"])
        environment.setdefault(f"CC_{target.triple.replace('-', '_')}", cross["gcc"])
    subprocess.run(
        [
            "cargo", "build", "--manifest-path", str(ROOT / "rust-core" / "Cargo.toml"),
            "--locked", "--release", "-p", "gitlama-remote-helper", "--target", target.triple,
        ],
        env=environment,
        check=True,
    )
    # Cargo's output follows CARGO_TARGET_DIR (relative to where cargo runs) when it is set.
    configured = os.environ.get("CARGO_TARGET_DIR")
    target_root = Path.cwd() / configured if configured else ROOT / "rust-core" / "target"
    built_binary = target_root / target.triple / "release" / BINARY
    # Preserve Cargo's original debug-bearing output across retries. Strip and
    # sign a runtime copy, then match it to the original by UUID/build ID.
    runtime_root = ROOT / "build/remote-helper-runtime" / target.name
    runtime_root.mkdir(parents=True, exist_ok=True)
    binary_path = runtime_root / BINARY
    shutil.copy2(built_binary, binary_path)
    if macos:
        subprocess.run(["xcrun", "strip", "-S", "-x", str(binary_path)], check=True)
    else:
        strip = cross["objdump"].replace("objdump", "strip") if cross else "strip"
        subprocess.run([strip, "--strip-unneeded", str(binary_path)], check=True)
    if macos:
        sign_macos(binary_path)
    if not reports_build(binary_path, target, build_id, commit):
        raise RuntimeError("the built helper does not report this helper ID and source commit")
    glibc = glibc_requirement(binary_path, target.triple) if not macos else None
    if glibc is not None and glibc > GLIBC_FLOOR and not arguments.skip_glibc_floor:
        raise RuntimeError(
            f"the helper needs glibc {glibc[0]}.{glibc[1]}; build it on the glibc "
            f"{GLIBC_FLOOR[0]}.{GLIBC_FLOOR[1]} baseline"
        )
    binary = binary_path.read_bytes()
    archive = build_archive(binary, epoch)
    record = metadata(
        version=version,
        build_id=build_id,
        source_commit=commit,
        shared_revision=shared_revision(),
        archive=archive,
        binary=binary,
        glibc=glibc,
        target=target,
    )
    arguments.output.mkdir(parents=True, exist_ok=True)
    (arguments.output / archive_name(version, target.name)).write_bytes(archive)
    (arguments.output / metadata_name(version, target.name)).write_text(
        json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    if os.environ.get("GITLAMA_COLLECT_DIAGNOSTICS") == "1":
        subprocess.run([
            sys.executable, str(ROOT / "scripts/collect-debug-symbols.py"),
            "--unit", f"helper-{target.name}", "--bundle", str(binary_path),
            "--search", str(built_binary),
            "--package", str(arguments.output / archive_name(version, target.name)),
            "--package", str(arguments.output / metadata_name(version, target.name)),
            "--output", str(arguments.output.parent / "diagnostics"),
        ], check=True, env=environment)
    print(json.dumps(record, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
