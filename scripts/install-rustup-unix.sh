#!/usr/bin/env bash
set -euo pipefail

cargo_bin="${CARGO_HOME:-$HOME/.cargo}/bin"

if ! command -v rustup >/dev/null 2>&1; then
  installer="$(mktemp)"
  cleanup() {
    rm -f "$installer"
  }
  trap cleanup EXIT
  curl --proto '=https' --tlsv1.2 --fail --silent --show-error \
    https://sh.rustup.rs --output "$installer"
  sh "$installer" -y --profile minimal --default-toolchain none
fi

export PATH="$cargo_bin:$PATH"
if [[ -n "${GITHUB_PATH:-}" ]]; then
  printf '%s\n' "$cargo_bin" >> "$GITHUB_PATH"
fi
rustup --version
