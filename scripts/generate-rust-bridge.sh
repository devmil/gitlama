#!/usr/bin/env bash
set -euo pipefail

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

required_frb_version() {
  local dart_version rust_version
  dart_version="$(sed -nE 's|^[[:space:]]*flutter_rust_bridge:[[:space:]]*['\''"]?([^[:space:]'\''"]+)['\''"]?[[:space:]]*$|\1|p' "$ROOT/pubspec.yaml")"
  rust_version="$(sed -nE 's|^[[:space:]]*flutter_rust_bridge[[:space:]]*=[[:space:]]*(\{[[:space:]]*version[[:space:]]*=[[:space:]]*)?"=([^\"]+)".*$|\2|p' "$ROOT/rust-core/Cargo.toml")"

  [[ -n "$dart_version" ]] || {
    echo "flutter_rust_bridge is missing from pubspec.yaml." >&2
    exit 1
  }
  [[ -n "$rust_version" ]] || {
    echo "flutter_rust_bridge is missing or not exactly pinned in rust-core/Cargo.toml." >&2
    exit 1
  }
  [[ "$dart_version" == "$rust_version" ]] || {
    echo "flutter_rust_bridge versions disagree: pubspec.yaml has $dart_version; rust-core/Cargo.toml has $rust_version." >&2
    exit 1
  }

  printf '%s\n' "$dart_version"
}

require_codegen_version() {
  local required_version
  required_version="$(required_frb_version)"

  if ! command -v flutter_rust_bridge_codegen >/dev/null 2>&1; then
    echo "flutter_rust_bridge_codegen is required; install version $required_version." >&2
    exit 127
  fi

  local installed_version
  installed_version="$(flutter_rust_bridge_codegen --version | awk '{print $2}')"
  if [[ "$installed_version" != "$required_version" ]]; then
    echo "flutter_rust_bridge_codegen $required_version is required; found $installed_version." >&2
    echo "Install it with: cargo install flutter_rust_bridge_codegen --version $required_version --locked --force" >&2
    exit 1
  fi
}

if [[ "${1:-}" == "--check-version" ]]; then
  [[ "$#" -eq 1 ]] || { echo "usage: $0 [--check-version]" >&2; exit 64; }
  require_codegen_version
  exit 0
fi
[[ "$#" -eq 0 ]] || { echo "usage: $0 [--check-version]" >&2; exit 64; }

require_codegen_version

cd "$ROOT"
flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml
cargo fmt --manifest-path "$ROOT/rust-core/Cargo.toml"
