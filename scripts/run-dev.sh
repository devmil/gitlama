#!/usr/bin/env bash
# Builds and runs GitLama from the checkout, loading QML from disk.
#   scripts/run-dev.sh [--release] [args...]
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
profile=dev
target_dir=debug
if [[ "${1:-}" == "--release" ]]; then
  profile=dev-opt
  target_dir=dev-opt
  shift
fi
cargo build --manifest-path "$root/rust-core/Cargo.toml" -p gitlama --profile "$profile"
export GITLAMA_QML_DIR="$root/qml"
export QT_FORCE_STDERR_LOGGING=1
exec "$root/rust-core/target/$target_dir/gitlama" "$@"
