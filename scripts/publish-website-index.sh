#!/usr/bin/env bash
set -euo pipefail

# Records the verified signed metadata of a published release in release/ and the website
# index. Run only after the GitHub release holds every signed file.
if [[ $# -ne 2 ]]; then
  echo "usage: publish-website-index.sh DIRECTORY TAG" >&2
  exit 64
fi
directory="$1"
tag="$2"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
public_key="$root/release/northspline-release-ed25519.pub"

cp "$directory/metadata.json" "$root/release/metadata.json"
cp "$directory/metadata.json.sig" "$root/release/metadata.json.sig"
receipt="$(mktemp)"
trap 'rm -f -- "$receipt"' EXIT
python3 "$root/scripts/sync-release-website.py" receipt \
  --manifest "$directory/metadata.json" --tag "$tag" --output "$receipt"
python3 "$root/scripts/sync-release-website.py" index --webfront "$root/webfront" \
  --manifest "$directory/metadata.json" --signature "$directory/metadata.json.sig" \
  --public-key-file "$public_key" --receipt "$receipt" --tag "$tag"
