"""Closed release-package identities and platform version transforms."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import re


SEMVER = re.compile(
    r"^(?P<major>0|[1-9][0-9]*)\."
    r"(?P<minor>0|[1-9][0-9]*)\."
    r"(?P<patch>0|[1-9][0-9]*)"
    r"(?:-(?P<prerelease>[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$"
)
TARGETS = frozenset(
    {
        ("macos", "arm64", "dmg"),
        ("windows", "x86_64", "msi"),
        ("linux", "x86_64", "AppImage"),
        ("linux", "x86_64", "deb"),
        ("linux", "x86_64", "rpm"),
        ("linux", "x86_64", "tar.gz"),
    }
)


@dataclass(frozen=True)
class Version:
    marketing: str
    build: int

    @classmethod
    def read(cls, file: Path) -> "Version":
        lines = [line.strip() for line in file.read_text(encoding="utf-8").splitlines()]
        if len(lines) != 2:
            raise ValueError("VERSION must contain exactly two lines")
        if SEMVER.fullmatch(lines[0]) is None:
            raise ValueError("marketing version must be SemVer without build metadata")
        if not re.fullmatch(r"[1-9][0-9]*", lines[1]):
            raise ValueError("build number must be a positive integer")
        return cls(lines[0], int(lines[1]))

    @property
    def parts(self) -> tuple[int, int, int, str | None]:
        match = SEMVER.fullmatch(self.marketing)
        if match is None:
            raise ValueError("invalid marketing version")
        return (
            int(match["major"]),
            int(match["minor"]),
            int(match["patch"]),
            match["prerelease"],
        )

    def windows_msi(self) -> str:
        """Return a monotonic three-field MSI version.

        Windows Installer compares only the first three numeric fields. The
        globally increasing GitLama build occupies the third field, so a
        beta/stable or patch rebuild never becomes an ambiguous same-version
        major upgrade. The complete marketing version remains in the filename
        and executable version resource.
        """

        major, minor, _, _ = self.parts
        if major > 255 or minor > 255 or self.build > 65_535:
            raise ValueError("version exceeds Windows Installer numeric limits")
        return f"{major}.{minor}.{self.build}"

    def apple_bundle_short_version(self) -> str:
        """Return Flutter's numeric CFBundleShortVersionString.

        Flutter removes every character except digits and dots, drops empty
        segments, and pads the result to at least three segments. The complete
        marketing identity remains in VERSION and the DMG name.
        """

        numeric = re.sub(r"[^0-9.]", "", self.marketing)
        segments = [segment for segment in numeric.split(".") if segment]
        while len(segments) < 3:
            segments.append("0")
        return ".".join(segments)

    def debian_upstream(self) -> str:
        major, minor, patch, prerelease = self.parts
        base = f"{major}.{minor}.{patch}"
        return base if prerelease is None else f"{base}~{prerelease}"

    def rpm_fields(self) -> tuple[str, str]:
        major, minor, patch, prerelease = self.parts
        version = f"{major}.{minor}.{patch}"
        release = str(self.build)
        if prerelease is not None:
            safe = prerelease.replace("-", ".")
            release = f"0.{safe}.{self.build}"
        return version, release


def artifact_name(version: Version, platform: str, architecture: str, format_: str) -> str:
    target = (platform, architecture, format_)
    if target not in TARGETS:
        raise ValueError(f"unsupported package target: {target}")
    identity = f"{version.marketing}-{version.build}"
    if format_ == "deb":
        return f"gitlama_{identity}_amd64.deb"
    if format_ == "rpm":
        return f"gitlama-{identity}.x86_64.rpm"
    return f"GitLama-{identity}-{platform}-{architecture}.{format_}"


@dataclass(frozen=True)
class RemoteHelperTarget:
    """A host platform the remote helper is built for. ``name`` is also the bundle directory
    the application loads it from."""

    name: str
    triple: str
    platform: str
    architecture: str
    minimum_system: str


REMOTE_HELPER_TARGETS = (
    RemoteHelperTarget(
        "linux-x86_64", "x86_64-unknown-linux-gnu", "linux", "x86_64",
        "Linux x86_64, glibc 2.35, kernel 5.15, Git 2.39, OpenSSH server 8.9",
    ),
    RemoteHelperTarget(
        "linux-arm64", "aarch64-unknown-linux-gnu", "linux", "arm64",
        "Linux arm64 (64-bit Raspberry Pi OS and others), glibc 2.35, kernel 5.15, Git 2.39, "
        "OpenSSH server 8.9",
    ),
    RemoteHelperTarget(
        "macos-arm64", "aarch64-apple-darwin", "macos", "arm64",
        "macOS 13 on Apple silicon, Git 2.39, Remote Login",
    ),
    RemoteHelperTarget(
        "macos-x86_64", "x86_64-apple-darwin", "macos", "x86_64",
        "macOS 13 on Intel, Git 2.39, Remote Login",
    ),
)


def remote_helper_target(name: str) -> RemoteHelperTarget:
    for target in REMOTE_HELPER_TARGETS:
        if target.name == name:
            return target
    raise ValueError(f"unsupported remote helper target: {name}")


def remote_helper_id(root: Path) -> str:
    """The ID the remote helper of this checkout reports and is installed under: its
    compatibility version from ``rust-core/remote-helper/COMPATIBILITY`` as 40 decimal digits,
    exactly as ``rust-core/application/build.rs`` derives it."""
    text = (root / "rust-core" / "remote-helper" / "COMPATIBILITY").read_text(encoding="utf-8")
    for line in text.splitlines():
        if line.strip().startswith("version "):
            version = line.strip()[len("version "):].strip()
            if re.fullmatch(r"[1-9][0-9]{0,5}", version):
                return version.rjust(40, "0")
            break
    raise ValueError("rust-core/remote-helper/COMPATIBILITY declares no valid version")


def remote_helper_archive_name(version: Version, target: str = "linux-x86_64") -> str:
    """The remote helper archive of a release for one host platform."""
    remote_helper_target(target)
    return f"gitlama-remote-helper-{version.marketing}-{version.build}-{target}.tar.gz"


def remote_helper_metadata_name(version: Version, target: str = "linux-x86_64") -> str:
    remote_helper_target(target)
    return f"gitlama-remote-helper-{version.marketing}-{version.build}-{target}.json"


def source_date_epoch(environment: dict[str, str]) -> int:
    value = environment.get("SOURCE_DATE_EPOCH", "0")
    if not re.fullmatch(r"0|[1-9][0-9]*", value):
        raise ValueError("SOURCE_DATE_EPOCH must be a non-negative integer")
    return int(value)


def fpm_source_date_epoch(epoch: int) -> int:
    """Map the Unix epoch to the oldest timestamp accepted by FPM."""

    if epoch < 0:
        raise ValueError("FPM source date epoch must be non-negative")
    return max(epoch, 1)


def without_allowed_flutter_build_metadata(
    data: bytes,
    file_name: str,
    source_root: Path,
) -> bytes:
    """Ignore Flutter's one generated registrant URI during path scans."""

    if file_name != "libapp.so":
        return data
    registrant = (
        f"{source_root.resolve().as_uri()}/.dart_tool/flutter_build/"
        "dart_plugin_registrant.dart"
    ).encode()
    return data.replace(registrant, b"")


# Generic CI checkout roots. They only count where an absolute path starts, so
# Dart library URIs such as package:gitlama/app/workspace/... do not match.
CI_BUILD_ROOT = re.compile(rb"(?<![A-Za-z0-9_.-])(/home/runner/|/builds/|/workspace/)")


def leaked_build_path(data: bytes, source_root: Path) -> str | None:
    """Return the first source or CI build path embedded in a payload file."""

    if str(source_root.resolve()).encode() in data:
        return str(source_root.resolve())
    match = CI_BUILD_ROOT.search(data)
    return match.group(1).decode() if match else None
