#!/usr/bin/env python3
"""Reject unpinned production sources and missing legal inventory inputs."""
from pathlib import Path
import hashlib
import re
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
errors: list[str] = []

# The reviewed first-party Git sources. Each is pinned to an exact commit.
LOGGING_CRATE_URL = "https://github.com/devmil/devmil-logging"
SHARED_GIT_URL = "https://github.com/devmil/devmil-rust-git"

cargo_manifest = (root / "rust-core/Cargo.toml").read_text(encoding="utf-8")
# The workspace root pins every shared dependency in [workspace.dependencies]; the member
# crates inherit them. Every manifest is checked for unpinned or unexpected sources.
MEMBER_MANIFESTS = ("contract", "application", "remote-helper", "desktop/workbench", "desktop/qt", "desktop/app")
manifests = {"rust-core/Cargo.toml": cargo_manifest} | {
    f"rust-core/{member}/Cargo.toml": (root / "rust-core" / member / "Cargo.toml").read_text(encoding="utf-8")
    for member in MEMBER_MANIFESTS
}
allowed_rust_paths = {
    "gitlama_contract": "contract",
    "gitlama_application": "application",
    "gitlama_core": ".",
    "gitlama-workbench": "desktop/workbench",
    "gitlama-qt": "desktop/qt",
    # The reviewed patch of the Qt bridge's interface crate.
    "qtbridge-interfaces": "third_party/qtbridge-interfaces",
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

# The shared Meridian design system's QML module is vendored from an exact,
# clean meridian_ui commit, and the vendored tree must match its recorded hash.
revision_file = root / "qml/Meridian/MERIDIAN_REVISION"
if not revision_file.is_file():
    errors.append("qml/Meridian is not vendored by scripts/sync-meridian.sh")
else:
    recorded = dict(
        line.split(" ", 1)
        for line in revision_file.read_text(encoding="utf-8").splitlines()
        if line and not line.startswith("#")
    )
    if not re.fullmatch(r"[0-9a-f]{40}", recorded.get("revision", "")):
        errors.append("qml/Meridian must come from a clean meridian_ui commit")
    meridian_root = root / "qml/Meridian"
    digest = hashlib.sha256()
    for path in sorted(
        (path for path in meridian_root.rglob("*") if path.is_file() and path.name != "MERIDIAN_REVISION"),
        key=lambda path: ("./" + path.relative_to(meridian_root).as_posix()).encode(),
    ):
        relative = "./" + path.relative_to(meridian_root).as_posix()
        digest.update(f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {relative}\n".encode())
    if digest.hexdigest() != recorded.get("content"):
        errors.append("qml/Meridian differs from its recorded meridian_ui content; resync it")

# The diagnostic library is the other reviewed first-party Git source.
rust_logging = next((line for line in cargo_manifest.splitlines() if line.startswith("devmil-logging =")), "")
if f'git = "{LOGGING_CRATE_URL}"' not in rust_logging or not re.search(r'rev\s*=\s*"[0-9a-f]{40}"', rust_logging):
    errors.append("devmil-logging must come from the reviewed repository at an exact revision")

# No Flutter build input may come back.
for leftover in ("pubspec.yaml", "pubspec.lock", "pubspec_overrides.yaml", "lib", "flutter_rust_bridge.yaml"):
    if (root / leftover).exists():
        errors.append(f"Flutter build input present: {leftover}")
if "flutter_rust_bridge" in cargo_lock:
    errors.append("the Rust workspace still resolves flutter_rust_bridge")

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
    root / "assets/licenses/QT-RUNTIME.md",
    root / "assets/licenses/RUST-DEPENDENCIES.md",
    root / "assets/licenses/SYNTAX-GRAMMARS.md",
)
for path in license_outputs:
    if not path.is_file() or path.stat().st_size == 0:
        errors.append(f"missing generated dependency notice: {path.relative_to(root)}")
    elif path.stat().st_size > 4 * 1024 * 1024:
        errors.append(f"dependency notice exceeds four MiB: {path.relative_to(root)}")

# The license dialog embeds every legal document in the binary.
license_source = (root / "rust-core/desktop/qt/src/settings_state.rs").read_text(encoding="utf-8")
for relative in ("LICENSE", "THIRD_PARTY_NOTICES.md", "assets/fonts/OFL.txt") + tuple(
    path.relative_to(root).as_posix() for path in license_outputs
):
    if f'include_str!("../../../../{relative}")' not in license_source:
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
