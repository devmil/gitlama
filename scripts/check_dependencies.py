#!/usr/bin/env python3
"""Reject unpinned production sources and missing legal inventory inputs."""
from pathlib import Path
import re
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
errors: list[str] = []

# The reviewed first-party Git sources. Each is pinned to an exact commit.
MERIDIAN_URL = "https://github.com/devmil/meridian_ui.git"
LOGGING_URL = "https://github.com/devmil/devmil-logging.git"
LOGGING_CRATE_URL = "https://github.com/devmil/devmil-logging"
SHARED_GIT_URL = "https://github.com/devmil/devmil-rust-git"

cargo_manifest = (root / "rust-core/Cargo.toml").read_text(encoding="utf-8")
# The workspace root pins every shared dependency in [workspace.dependencies]; the member
# crates inherit them. Every manifest is checked for unpinned or unexpected sources.
MEMBER_MANIFESTS = ("contract", "application", "remote-helper")
manifests = {"rust-core/Cargo.toml": cargo_manifest} | {
    f"rust-core/{member}/Cargo.toml": (root / "rust-core" / member / "Cargo.toml").read_text(encoding="utf-8")
    for member in MEMBER_MANIFESTS
}
allowed_rust_paths = {
    "gitlama_contract": "contract",
    "gitlama_application": "application",
}
for manifest_name, manifest in manifests.items():
    for name in re.findall(r'(?m)^(\S+)\s*=\s*\{[^\n]*git\s*=\s*"[^"]+"[^\n]*\}', manifest):
        dependency_line = next(
            line for line in manifest.splitlines() if line.startswith(f"{name} =")
        )
        if not re.search(r'rev\s*=\s*"[0-9a-f]{40}"', dependency_line):
            errors.append(f"{manifest_name}: rust git dependency {name} needs an exact 40-character revision")
    path_dependencies = re.findall(
        r'(?m)^(\S+)\s*=\s*\{[^\n]*path\s*=\s*"([^"]+)"[^\n]*\}', manifest
    )
    if manifest_name != "rust-core/Cargo.toml" and path_dependencies:
        errors.append(f"{manifest_name}: path dependencies belong in [workspace.dependencies]")
    for name, path in path_dependencies:
        if allowed_rust_paths.get(name) != path:
            errors.append(f"unexpected rust path dependency: {name} at {path}")
path_dependencies = re.findall(
    r'(?m)^(\S+)\s*=\s*\{[^\n]*path\s*=\s*"([^"]+)"[^\n]*\}', cargo_manifest
)
for name, path in allowed_rust_paths.items():
    if (name, path) not in path_dependencies:
        errors.append(f"rust dependency {name} must use its workspace path")
devmil_line = next(
    (line for line in cargo_manifest.splitlines() if line.startswith("devmil-git =")),
    "",
)
if f'git = "{SHARED_GIT_URL}"' not in devmil_line or not re.search(r'rev\s*=\s*"[0-9a-f]{40}"', devmil_line):
    errors.append("devmil-git must come from the reviewed repository at an exact revision")
if not re.search(
    r'features\s*=\s*\[\s*"hosting"\s*,\s*"syntax-highlighting"\s*\]', devmil_line
):
    errors.append(
        "devmil-git must enable exactly the reviewed hosting and syntax-highlighting features"
    )
for required_pin in (
    'keyring = { version = "=3.6.3"',
    'zeroize = { version = "=1.8.2"',
    'getrandom = "=0.3.3"',
):
    if required_pin not in cargo_manifest:
        errors.append(f"missing exact hosting security dependency pin: {required_pin}")

cargo_lock = (root / "rust-core/Cargo.lock").read_text(encoding="utf-8")
for revision in re.findall(r'rev\s*=\s*"([0-9a-f]{40})"', cargo_manifest):
    if revision not in cargo_lock:
        errors.append(f"rust lockfile does not contain revision {revision}")

pubspec = (root / "pubspec.yaml").read_text(encoding="utf-8")
if "flutter_rust_bridge: 2.13.0-beta.5" not in pubspec:
    errors.append("flutter_rust_bridge must retain the reviewed exact pin")
# The shared Meridian design system, pinned to an exact commit. Apart from
# devmil_logging below, every other source must come from pub.dev.
meridian = re.search(
    r"(?m)^  meridian_ui:\n    git:\n      url: (\S+)\n      ref: (\S+)\n", pubspec
)
if meridian is None:
    errors.append("meridian_ui must be a Git dependency with url and ref")
else:
    if meridian.group(1) != MERIDIAN_URL:
        errors.append("meridian_ui must come from the reviewed repository")
    if not re.fullmatch(r"[0-9a-f]{40}", meridian.group(2)):
        errors.append("meridian_ui needs an exact 40-character commit ref")
    lock = (root / "pubspec.lock").read_text(encoding="utf-8")
    locked = re.search(
        r"(?ms)^  meridian_ui:\n.*?resolved-ref: \"?([0-9a-f]{40})\"?", lock
    )
    if locked is None or locked.group(1) != meridian.group(2):
        errors.append("pubspec.lock does not resolve meridian_ui to its pinned ref")
# Its native menu companion lives in the same repository and must come from
# the same commit.
companion = re.search(
    r"(?m)^  meridian_native_menus:\n(?:    #[^\n]*\n)?    git:\n      url: (\S+)\n      ref: (\S+)\n      path: packages/meridian_native_menus\n",
    pubspec,
)
if companion is None:
    errors.append("meridian_native_menus must be a Git dependency on packages/meridian_native_menus")
elif meridian is not None and (
    companion.group(1) != MERIDIAN_URL or companion.group(2) != meridian.group(2)
):
    errors.append("meridian_native_menus must be pinned to the meridian_ui commit")
without_meridian = pubspec if meridian is None else pubspec.replace(meridian.group(0), "")
if companion is not None:
    without_meridian = without_meridian.replace(companion.group(0), "")
# The diagnostic library is the other reviewed first-party Git source.
logging_source = re.search(
    r"(?m)^  devmil_logging:\n    git:\n      url: (\S+)\n      ref: (\S+)\n", pubspec
)
if logging_source is None or logging_source.group(1) != LOGGING_URL:
    errors.append("devmil_logging must come from the reviewed repository")
elif not re.fullmatch(r"[0-9a-f]{40}", logging_source.group(2)):
    errors.append("devmil_logging needs an exact 40-character commit ref")
else:
    lock = (root / "pubspec.lock").read_text(encoding="utf-8")
    locked_logging = re.search(r"(?ms)^  devmil_logging:\n.*?resolved-ref: \"?([0-9a-f]{40})\"?", lock)
    if locked_logging is None or locked_logging.group(1) != logging_source.group(2):
        errors.append("pubspec.lock must resolve the pinned devmil_logging ref")
    rust_logging = next((line for line in cargo_manifest.splitlines() if line.startswith("devmil-logging =")), "")
    if f'git = "{LOGGING_CRATE_URL}"' not in rust_logging:
        errors.append("devmil-logging must come from the reviewed repository")
    if logging_source.group(2) not in rust_logging:
        errors.append("Dart and Rust logging must use the same reviewed commit")
if logging_source is not None:
    without_meridian = without_meridian.replace(logging_source.group(0), "")
if re.search(r"(?m)^\s+(git|path):\s*", without_meridian):
    errors.append("pubspec production dependencies must not use local path or floating git sources")
if (root / "pubspec_overrides.yaml").exists():
    errors.append("pubspec_overrides.yaml is a local development override; remove it")

for legal_file in ("LICENSE", "THIRD_PARTY_NOTICES.md"):
    path = root / legal_file
    if not path.is_file() or not path.read_text(encoding="utf-8").strip():
        errors.append(f"missing legal inventory input: {legal_file}")
notices = (root / "THIRD_PARTY_NOTICES.md").read_text(encoding="utf-8")
for dependency in ("keyring", "zeroize", "getrandom"):
    if dependency not in notices:
        errors.append(f"third-party notices omit hosting dependency {dependency}")
for legal_text in (
    "Permission to use, copy, modify, and/or distribute this software",
    "Feather Icons MIT License",
    "JetBrains Mono 2.304",
):
    if legal_text not in notices:
        errors.append(f"third-party notices omit required text: {legal_text}")

license_outputs = (
    root / "assets/licenses/FLUTTER-DEPENDENCIES.md",
    root / "assets/licenses/RUST-DEPENDENCIES.md",
    root / "assets/licenses/SYNTAX-GRAMMARS.md",
)
for path in license_outputs:
    if not path.is_file() or path.stat().st_size == 0:
        errors.append(f"missing generated dependency notice: {path.relative_to(root)}")
    elif path.stat().st_size > 4 * 1024 * 1024:
        errors.append(f"dependency notice exceeds four MiB: {path.relative_to(root)}")

pubspec_assets = (root / "pubspec.yaml").read_text(encoding="utf-8")
for asset in (
    "assets/licenses/",
    "assets/fonts/OFL.txt",
    "LICENSE",
    "THIRD_PARTY_NOTICES.md",
):
    if asset not in pubspec_assets:
        errors.append(f"license asset is not bundled: {asset}")

license_source = (root / "lib/app/app_licenses.dart").read_text(encoding="utf-8")
for path in license_outputs:
    relative = path.relative_to(root).as_posix()
    if relative not in license_source:
        errors.append(f"in-app Licenses view omits {relative}")

if not errors:
    result = subprocess.run(
        [sys.executable, str(root / "scripts/generate-license-notices.py"), "--check"],
        cwd=root,
        check=False,
    )
    if result.returncode != 0:
        errors.append("generated dependency notices are stale")

if errors:
    raise SystemExit("\n".join(errors))
print("Dependency pins and legal inventory inputs passed")
