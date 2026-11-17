#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 "$root/scripts/prepare-flutter-framework.py" | python3 -c 'import json,sys; print(json.load(sys.stdin)["sdk"])'
