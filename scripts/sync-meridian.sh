#!/usr/bin/env bash
# Vendors Meridian's QML module from a meridian_ui checkout into qml/Meridian
# and records the commit and a content hash. Usage:
#   scripts/sync-meridian.sh /path/to/meridian_ui
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source="${1:?usage: sync-meridian.sh <meridian_ui checkout>}"
source="$(cd "$source" && pwd)"
[[ -f "$source/qml/Meridian/qmldir" ]] || { echo "no qml/Meridian in $source" >&2; exit 1; }
revision="$(git -C "$source" rev-parse HEAD)"
dirty=""
if [[ -n "$(git -C "$source" status --porcelain -- qml/Meridian)" ]]; then
  dirty="-dirty"
fi
rm -rf "$root/qml/Meridian"
cp -R "$source/qml/Meridian" "$root/qml/Meridian"
hash="$(cd "$root/qml/Meridian" && find . -type f ! -name MERIDIAN_REVISION | LC_ALL=C sort | xargs sha256sum | sha256sum | cut -c1-64)"
cat > "$root/qml/Meridian/MERIDIAN_REVISION" <<REV
# Vendored from meridian_ui by scripts/sync-meridian.sh. Do not edit by hand.
revision $revision$dirty
content $hash
REV
echo "Meridian $revision$dirty ($hash)"
