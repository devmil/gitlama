#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "$(uname -s)" == Linux ]]; then
  exec "$root/scripts/linux/flutter.sh" "$@"
fi
exec flutter "$@"
