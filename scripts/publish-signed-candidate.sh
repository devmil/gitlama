#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "usage: publish-signed-candidate.sh DIRECTORY TAG SOURCE_SHA REPOSITORY" >&2
  exit 64
fi
directory="$1"
tag="$2"
source_sha="$3"
repository="$4"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
public_key="$root/release/northspline-release-ed25519.pub"

[[ -n "${GITHUB_RELEASE_TOKEN:-}" ]] || {
  echo "release publication configuration is incomplete" >&2; exit 1;
}
python3 "$root/scripts/release.py" verify --manifest "$directory/metadata.json" \
  --signature "$directory/metadata.json.sig" --public-key-file "$public_key" >/dev/null
cmp -s "$directory/northspline-release-ed25519.pub" "$public_key" || {
  echo "signed candidate trust root differs from this release checkout" >&2; exit 1;
}
python3 "$root/scripts/publish-release.py" stage --repository "$repository" --tag "$tag" \
  --source-sha "$source_sha" --directory "$directory" --public-key-file "$public_key"
python3 "$root/scripts/publish-release.py" publish --repository "$repository" --tag "$tag" \
  --source-sha "$source_sha" --directory "$directory" --public-key-file "$public_key"
"$root/scripts/publish-website-index.sh" "$directory" "$tag"
echo "GitHub release published and verified"
