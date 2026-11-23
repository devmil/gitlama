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
# The helpers this build offers to install on remote hosts.
if [[ "${GITLAMA_DEV_REMOTE_HELPER:-1}" != "0" ]]; then
  python3 "$root/scripts/build_dev_helpers.py" || true
fi
export GITLAMA_QML_DIR="$root/qml"
export QT_FORCE_STDERR_LOGGING=1
# A separate profile runs as its own instance, not forwarded to an
# installed GitLama.
if [[ -n "${GITLAMA_PROFILE_ROOT:-}" && -z "${GITLAMA_RUNTIME_DIR:-}" ]]; then
  # Short: the socket path inside must fit a Unix socket address.
  export GITLAMA_RUNTIME_DIR="${TMPDIR:-/tmp}/gitlama-dev-$(printf '%s' "$GITLAMA_PROFILE_ROOT" | cksum | cut -d' ' -f1)"
  mkdir -p "$GITLAMA_RUNTIME_DIR" && chmod 700 "$GITLAMA_RUNTIME_DIR"
fi
exec "$root/rust-core/target/$target_dir/gitlama" "$@"
