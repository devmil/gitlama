#!/usr/bin/env bash
set -euo pipefail

# Finishes the publication of an existing tag from the bytes its GitHub release already
# holds. It never builds or signs: every file must match the signed metadata stored with it.
if [[ $# -ne 4 ]]; then
  echo "usage: recover-publication.sh DIRECTORY TAG SOURCE_SHA REPOSITORY" >&2
  exit 64
fi
directory="$1"
tag="$2"
source_sha="$3"
repository="$4"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
public_key="$root/release/northspline-release-ed25519.pub"

[[ -n "${GITHUB_RELEASE_TOKEN:-}" ]] || {
  echo "release publication recovery configuration is incomplete" >&2; exit 1;
}
mkdir -p "$directory"
python3 "$root/scripts/publish-release.py" recover --repository "$repository" --tag "$tag" \
  --source-sha "$source_sha" --directory "$directory" --public-key-file "$public_key"
python3 "$root/scripts/publish-release.py" publish --repository "$repository" --tag "$tag" \
  --source-sha "$source_sha" --directory "$directory" --public-key-file "$public_key"
"$root/scripts/publish-website-index.sh" "$directory" "$tag"
