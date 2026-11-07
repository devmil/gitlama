#!/usr/bin/env python3
"""Qualify a GitLama DMG from its mounted payload, not the build tree."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import time

from lib.package_contract import Version, artifact_name
from lib.release_appcast import FEED_URL


ROOT = Path(__file__).resolve().parent.parent
ALLOWED_DEPENDENCY_PREFIXES = (
    "/System/Library/",
    "/usr/lib/",
    "@rpath/",
    "@loader_path/",
    "@executable_path/",
)


def run(*arguments: object, environment: dict[str, str] | None = None) -> None:
    subprocess.run(
        [str(argument) for argument in arguments],
        cwd=ROOT,
        env=environment,
        check=True,
        stdout=subprocess.DEVNULL,
    )


def detach(mount: Path) -> None:
    result = subprocess.run(
        ["hdiutil", "detach", str(mount)],
        cwd=ROOT,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    if result.returncode != 0:
        run("hdiutil", "detach", "-force", mount)


def output(*arguments: object) -> str:
    return subprocess.check_output(
        [str(argument) for argument in arguments],
        cwd=ROOT,
        text=True,
        stderr=subprocess.STDOUT,
    ).strip()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


# Remote helpers run on other computers: each keeps the architecture of its platform directory.
# The application itself is arm64 only.
REMOTE_HELPER_ARCHITECTURES = {"macos-arm64": ["arm64"], "macos-x86_64": ["x86_64"]}


def expected_architectures(relative: str) -> list[str]:
    """The architectures a Mach-O file at ``relative`` (inside the app) must have."""
    parts = relative.split("/")
    if parts[:3] == ["Contents", "Resources", "remote-helper"] and len(parts) == 5:
        helper = REMOTE_HELPER_ARCHITECTURES.get(parts[3])
        require(helper is not None, f"unexpected remote helper platform: {relative}")
        return helper
    return ["arm64"]


def macho_files(app: Path) -> list[Path]:
    files = []
    for path in sorted(candidate for candidate in app.rglob("*") if candidate.is_file()):
        if "Mach-O" in output("file", "-b", path):
            files.append(path)
    require(bool(files), "DMG application contains no Mach-O payload")
    return files


def inspect_macho(app: Path) -> tuple[list[str], list[str]]:
    relative_files = []
    dependencies = set()
    forbidden_roots = (str(ROOT), str(ROOT.parent), "/Users/", "/home/")
    for file in macho_files(app):
        relative = file.relative_to(app).as_posix()
        relative_files.append(relative)
        expected = expected_architectures(relative)
        require(
            output("lipo", "-archs", file).split() == expected,
            f"payload is not {'/'.join(expected)}: {relative}",
        )
        load_commands = output("otool", "-L", file).splitlines()[1:]
        for line in load_commands:
            dependency = line.strip().split(" (", 1)[0]
            if dependency == str(file):
                continue
            require(
                dependency.startswith(ALLOWED_DEPENDENCY_PREFIXES),
                f"unexpected dynamic dependency in {relative}: {dependency}",
            )
            dependencies.add(dependency)
        commands = output("otool", "-l", file)
        require(
            not any(root in commands for root in forbidden_roots),
            f"private or source path in Mach-O load commands: {relative}",
        )
    return relative_files, sorted(dependencies)


def launch_once(
    executable: Path,
    profile_root: Path,
    repository: Path | None,
    *,
    expect_settings: bool,
    label: str,
    without_git: bool,
) -> None:
    runtime = profile_root / "runtime"
    runtime.mkdir(parents=True, mode=0o700)
    environment = dict(os.environ)
    environment["GITLAMA_PROFILE_ROOT"] = str(profile_root)
    environment["GITLAMA_RUNTIME_DIR"] = str(runtime)
    environment.pop("GITLAMA_NATIVE_LIBRARY", None)
    environment.pop("GITLAMA_KEEP_PATH", None)
    if without_git:
        environment["PATH"] = str(profile_root / "empty-path")
        (profile_root / "empty-path").mkdir()
        # The application otherwise restarts with the login shell's PATH,
        # which contains Git.
        environment["GITLAMA_KEEP_PATH"] = "1"
    command = [str(executable)]
    if repository is not None:
        command.append(str(repository))
    process = subprocess.Popen(
        command,
        cwd=profile_root,
        env=environment,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    deadline = time.monotonic() + 8
    settings = profile_root / "settings.json"
    try:
        while time.monotonic() < deadline and process.poll() is None and not settings.is_file():
            time.sleep(0.1)
        if process.poll() is not None:
            stdout, stderr = process.communicate()
            diagnostic = (stderr or stdout).replace(
                str(profile_root), "<qualification-profile>"
            )
            if repository is not None:
                diagnostic = diagnostic.replace(str(repository), "<qualification-repository>")
            diagnostic = diagnostic.replace(str(executable.parent.parent.parent), "<qualified-app>")
            raise RuntimeError(
                f"packaged application exited during {label} launch qualification: "
                f"code={process.returncode}; {diagnostic[-1000:].strip()}"
            )
        if expect_settings:
            require(settings.is_file(), "packaged application did not initialize its settings namespace")
        time.sleep(1)
        require(process.poll() is None, f"packaged application did not remain running: {label}")
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)


def qualify(
    dmg: Path,
    report_path: Path,
    skip_native: bool,
    skip_launch: bool,
    require_signature: bool,
    require_notarization: bool,
) -> None:
    version = Version.read(ROOT / "VERSION")
    require(dmg.name == artifact_name(version, "macos", "arm64", "dmg"), "unexpected DMG filename")
    run("hdiutil", "verify", dmg)

    # Keep the Unix-domain socket below macOS's sockaddr_un path limit. The
    # repository and app mount names still exercise spaces and Unicode.
    with tempfile.TemporaryDirectory(prefix="nsq-", dir="/tmp") as temporary_directory:
        temporary = Path(temporary_directory)
        mount = temporary / "mounted image"
        mount.mkdir()
        run("hdiutil", "attach", "-readonly", "-nobrowse", "-mountpoint", mount, dmg)
        try:
            app = mount / "GitLama.app"
            require(app.is_dir(), "DMG is missing GitLama.app")
            applications = mount / "Applications"
            require(applications.is_symlink(), "DMG is missing Applications symlink")
            require(os.readlink(applications) == "/Applications", "Applications link has wrong target")

            with (app / "Contents/Info.plist").open("rb") as stream:
                plist = plistlib.load(stream)
            expected = {
                "CFBundleIdentifier": "de.devmil.gitlama",
                "CFBundleName": "GitLama",
                "CFBundleExecutable": "GitLama",
                "CFBundleShortVersionString": version.apple_bundle_short_version(),
                "CFBundleVersion": str(version.build),
                "LSMinimumSystemVersion": "13.0",
                # The updater trusts only this feed and this signing key.
                "SUFeedURL": FEED_URL,
                "SUPublicEDKey": (ROOT / "release/northspline-release-ed25519.pub")
                .read_text(encoding="utf-8")
                .strip(),
            }
            for key, value in expected.items():
                actual = plist.get(key)
                require(
                    actual == value,
                    f"unexpected Info.plist value for {key}: expected {value!r}, got {actual!r}",
                )

            require(
                (app / "Contents/Frameworks/Sparkle.framework/Versions/Current/Sparkle").is_file(),
                "packaged application is missing the update framework",
            )
            assets = app / "Contents/Frameworks/App.framework/Resources/flutter_assets"
            for relative in (
                "AssetManifest.bin",
                "NOTICES.Z",
                "LICENSE",
                "THIRD_PARTY_NOTICES.md",
                "assets/licenses/RUST-DEPENDENCIES.md",
                "assets/licenses/FLUTTER-DEPENDENCIES.md",
                "assets/licenses/SYNTAX-GRAMMARS.md",
            ):
                require((assets / relative).is_file(), f"packaged legal or Flutter asset missing: {relative}")

            run("codesign", "--verify", "--deep", "--strict", app)
            signature = output("codesign", "-dvvv", app)
            signing = "adhoc" if "Signature=adhoc" in signature else "developer-id"
            if require_signature:
                require(signing == "developer-id", "Developer ID application signature is required")
                require("Authority=Developer ID Application:" in signature, "unexpected application signing authority")
                run("codesign", "--verify", "--strict", dmg)
            notarized = False
            if require_notarization:
                require(require_signature, "notarization requires signature validation")
                run("xcrun", "stapler", "validate", dmg)
                run("spctl", "-a", "-t", "open", "--context", "context:primary-signature", "-v", dmg)
                run("spctl", "-a", "-t", "exec", "-v", app)
                notarized = True
            machos, dependencies = inspect_macho(app)

            if not skip_native:
                run("python3", ROOT / "scripts/native-smoke.py", app)
            launches = []
            if not skip_launch:
                repository = temporary / "repository with spaces and ünicode"
                repository.mkdir()
                run("git", "init", "--quiet", repository)
                for index in range(2):
                    profile_root = temporary / f"cold profile {index + 1}"
                    profile_root.mkdir()
                    launch_once(
                        app / "Contents/MacOS/GitLama",
                        profile_root,
                        repository,
                        expect_settings=True,
                        label=f"cold-restart-{index + 1}",
                        without_git=False,
                    )
                    launches.append("repository")
                profile_root = temporary / "missing git profile"
                profile_root.mkdir()
                launch_once(
                    app / "Contents/MacOS/GitLama",
                    profile_root,
                    None,
                    expect_settings=False,
                    label="missing-git",
                    without_git=True,
                )
                launches.append("missing-git")
        finally:
            detach(mount)

    report = {
        "schema": 1,
        "artifact": dmg.name,
        "bytes": dmg.stat().st_size,
        "sha256": sha256(dmg),
        "platform": "macos",
        "architecture": "arm64",
        "minimumOs": "13.0",
        "identifier": "de.devmil.gitlama",
        "marketingVersion": version.marketing,
        "buildNumber": version.build,
        "signing": signing,
        "notarized": notarized,
        "nativeBridge": "passed" if not skip_native else "not-run",
        "launches": launches if not skip_launch else [],
        "machOFiles": machos,
        "dynamicDependencies": dependencies,
        "updateFeed": FEED_URL,
    }
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(report_path)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dmg", type=Path)
    parser.add_argument(
        "--report",
        type=Path,
        default=ROOT / "dist/qualification/macos-arm64.json",
    )
    parser.add_argument("--skip-native", action="store_true")
    parser.add_argument("--skip-launch", action="store_true")
    parser.add_argument("--require-signature", action="store_true")
    parser.add_argument("--require-notarization", action="store_true")
    arguments = parser.parse_args()
    dmg = arguments.dmg.resolve()
    require(dmg.is_file(), "DMG candidate does not exist")
    if arguments.require_notarization and not arguments.require_signature:
        raise RuntimeError("--require-notarization requires --require-signature")
    qualify(
        dmg,
        arguments.report.resolve(),
        arguments.skip_native,
        arguments.skip_launch,
        arguments.require_signature,
        arguments.require_notarization,
    )


if __name__ == "__main__":
    main()
