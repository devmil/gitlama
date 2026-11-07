"""Detached Ed25519 signing helpers for exact release-manifest bytes."""

from __future__ import annotations

import base64
import binascii
import os
import re
import shutil
import stat
import subprocess
import tempfile
from contextlib import contextmanager
from pathlib import Path
from typing import Iterator


PRIVATE_KEY_ENV = "GITLAMA_RELEASE_PRIVATE_KEY"
PKCS8_SEED_PREFIX = bytes.fromhex("302e020100300506032b657004220420")
SPKI_PUBLIC_PREFIX = bytes.fromhex("302a300506032b6570032100")


def openssl_binary() -> str:
    configured = os.environ.get("OPENSSL", "").strip()
    candidates = [configured] if configured else []
    candidates.extend(("/opt/homebrew/opt/openssl@3/bin/openssl",
                       "/usr/local/opt/openssl@3/bin/openssl"))
    git = shutil.which("git")
    if git:
        git_path = Path(git).resolve()
        for parent in git_path.parents:
            candidates.extend((
                str(parent / "mingw64/bin/openssl.exe"),
                str(parent / "usr/bin/openssl.exe"),
            ))
    discovered = shutil.which("openssl")
    if discovered:
        candidates.append(discovered)
    for candidate in dict.fromkeys(candidates):
        if candidate and Path(candidate).is_file():
            version = subprocess.run([candidate, "version"], stdout=subprocess.PIPE,
                                     stderr=subprocess.DEVNULL, text=True, check=False)
            match = re.match(r"OpenSSL ([0-9]+)\.", version.stdout)
            if version.returncode == 0 and match and int(match.group(1)) >= 3:
                return candidate
    raise ValueError("OpenSSL 3 is required for Ed25519 release signing")


def _openssl(arguments: list[str], *, input_bytes: bytes | None = None) -> bytes:
    try:
        result = subprocess.run(
            [openssl_binary(), *arguments], input=input_bytes,
            stdin=subprocess.DEVNULL if input_bytes is None else None,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
        )
    except FileNotFoundError as error:
        raise ValueError("OpenSSL is required for release signing") from error
    if result.returncode != 0:
        raise ValueError("OpenSSL could not use the GitLama release signing key")
    return result.stdout


def _environment_key(variable: str) -> bytes:
    value = os.environ.get(variable, "").strip()
    if not value:
        raise ValueError(f"release private-key environment variable {variable} is not set")
    if value.startswith("-----BEGIN"):
        return value.encode("utf-8")
    try:
        seed = base64.b64decode(value, validate=True)
    except (binascii.Error, ValueError) as error:
        raise ValueError("release private-key environment value is not valid base64") from error
    if len(seed) != 32:
        raise ValueError("release private-key environment value must contain a 32-byte seed")
    return PKCS8_SEED_PREFIX + seed


@contextmanager
def private_key_path(*, key_file: Path | None = None,
                     key_environment: str | None = None) -> Iterator[Path]:
    if (key_file is None) == (key_environment is None):
        raise ValueError("choose exactly one release private-key source")
    if key_file is not None:
        if key_file.is_symlink() or not key_file.is_file():
            raise ValueError("release private key must be a regular file")
        # Windows access is ACL-based; its synthesized POSIX mode bits do not describe
        # whether another principal can read the key. Native release signing validates
        # that boundary through the protected runner account and secret store.
        permissions = stat.S_IMODE(key_file.stat().st_mode)
        if os.name != "nt" and permissions & (stat.S_IRWXG | stat.S_IRWXO):
            raise ValueError("release private key must not be accessible by group or others")
        yield key_file
        return
    descriptor, name = tempfile.mkstemp(prefix="gitlama-release-key-")
    path = Path(name)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(_environment_key(key_environment or PRIVATE_KEY_ENV))
        yield path
    finally:
        path.unlink(missing_ok=True)


def _format(path: Path) -> str:
    return "PEM" if path.read_bytes()[:32].lstrip().startswith(b"-----BEGIN") else "DER"


def _public_bytes(path: Path) -> bytes:
    public = _openssl([
        "pkey", "-in", str(path), "-inform", _format(path),
        "-pubout", "-outform", "DER",
    ])
    if len(public) != 44 or not public.startswith(SPKI_PUBLIC_PREFIX):
        raise ValueError("release signing key is not an Ed25519 private key")
    return public[len(SPKI_PUBLIC_PREFIX):]


def public_key_base64(*, key_file: Path | None = None,
                      key_environment: str | None = None) -> str:
    with private_key_path(key_file=key_file, key_environment=key_environment) as path:
        return base64.b64encode(_public_bytes(path)).decode("ascii")


def _atomic_bytes(path: Path, value: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary = Path(name)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(value)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def write_public_key(output: Path, *, key_file: Path | None = None,
                     key_environment: str | None = None) -> str:
    public = public_key_base64(key_file=key_file, key_environment=key_environment)
    _atomic_bytes(output, public.encode("ascii") + b"\n")
    return public


def sign_update_archive(archive: Path, *, key_file: Path | None = None,
                        key_environment: str | None = None) -> str:
    """Return the base64 Ed25519 signature Sparkle verifies over exact bytes."""
    if archive.is_symlink() or not archive.is_file() or archive.stat().st_size < 1:
        raise ValueError("update archive must be a nonempty regular file")
    with private_key_path(key_file=key_file, key_environment=key_environment) as path:
        signed = _openssl([
            "pkeyutl", "-sign", "-rawin", "-inkey", str(path),
            "-keyform", _format(path), "-in", str(archive),
        ])
    if len(signed) != 64:
        raise ValueError("OpenSSL returned an invalid Ed25519 signature")
    return base64.b64encode(signed).decode("ascii")


def sign_manifest(manifest: Path, signature: Path, *, key_file: Path | None = None,
                  key_environment: str | None = None) -> str:
    if manifest.resolve() == signature.resolve():
        raise ValueError("manifest and signature output must differ")
    with private_key_path(key_file=key_file, key_environment=key_environment) as path:
        signed = _openssl([
            "pkeyutl", "-sign", "-rawin", "-inkey", str(path),
            "-keyform", _format(path), "-in", str(manifest),
        ])
        public = _public_bytes(path)
    if len(signed) != 64:
        raise ValueError("OpenSSL returned an invalid Ed25519 signature")
    _atomic_bytes(signature, base64.b64encode(signed) + b"\n")
    return base64.b64encode(public).decode("ascii")
