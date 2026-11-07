#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: publish-candidate.sh DIRECTORY TAG CHANNEL" >&2
  exit 64
fi
directory="$1"
tag="$2"
channel="$3"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
public_key="$root/release/northspline-release-ed25519.pub"
key_arguments=()
update_key_arguments=()
if [[ -n "${GITLAMA_RELEASE_PRIVATE_KEY_FILE:-}" ]]; then
  [[ -f "$GITLAMA_RELEASE_PRIVATE_KEY_FILE" ]] || {
    echo "protected signing key file does not exist" >&2
    exit 1
  }
  key_arguments=(--key-file "$GITLAMA_RELEASE_PRIVATE_KEY_FILE")
  update_key_arguments=(--update-key-file "$GITLAMA_RELEASE_PRIVATE_KEY_FILE")
else
  key_arguments=(--key-env GITLAMA_RELEASE_PRIVATE_KEY)
  update_key_arguments=(--update-key-env GITLAMA_RELEASE_PRIVATE_KEY)
fi

[[ -n "${PUBLIC_GITHUB_REPOSITORY:-}" ]] || { echo "PUBLIC_GITHUB_REPOSITORY is not configured" >&2; exit 1; }
[[ -d "$directory" ]] || { echo "candidate directory does not exist" >&2; exit 1; }
temporary="$(mktemp -d)"
trap 'rm -rf -- "$temporary"' EXIT
python3 "$root/scripts/release.py" public-key "${key_arguments[@]}" \
  --output "$temporary/public-key" >/dev/null
cmp -s "$temporary/public-key" "$public_key" || { echo "protected signing key does not match the versioned trust root" >&2; exit 1; }

manifest_arguments=(
  --directory "$directory"
  --base-url "https://github.com/${PUBLIC_GITHUB_REPOSITORY}/releases/download/${tag}"
  --channel "$channel"
  --output "$directory/metadata.json"
  --notes "$root/RELEASE_NOTES.md"
  "${update_key_arguments[@]}"
)
if [[ -f "$root/release/metadata.json" || -f "$root/release/metadata.json.sig" ]]; then
  [[ -f "$root/release/metadata.json" && -f "$root/release/metadata.json.sig" ]] || {
    echo "versioned release metadata is incomplete" >&2; exit 1;
  }
  manifest_arguments+=(
    --previous-manifest "$root/release/metadata.json"
    --previous-signature "$root/release/metadata.json.sig"
    --public-key-file "$public_key"
  )
fi
python3 "$root/scripts/release.py" manifest "${manifest_arguments[@]}"
python3 "$root/scripts/release.py" sign --manifest "$directory/metadata.json" \
  --signature "$directory/metadata.json.sig" "${key_arguments[@]}" >/dev/null
cp "$public_key" "$directory/northspline-release-ed25519.pub"
python3 "$root/scripts/release.py" verify --manifest "$directory/metadata.json" \
  --signature "$directory/metadata.json.sig" --public-key-file "$public_key" >/dev/null
# The macOS updater installs this package only when its signature verifies
# against the key embedded in the application.
update_package="$directory/GitLama-${tag#v}-macos-arm64.dmg"
[[ -f "$update_package" ]] || { echo "candidate has no macOS update package for $tag" >&2; exit 1; }
python3 "$root/scripts/release.py" verify --manifest "$directory/metadata.json" \
  --signature "$directory/metadata.json.sig" --public-key-file "$public_key" \
  --artifact "$update_package" --platform macos --architecture arm64 --format dmg \
  --require-update-signature >/dev/null

echo "Signed candidate prepared for the publication job"
