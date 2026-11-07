#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/load-signing-env.sh
source "$ROOT/scripts/lib/load-signing-env.sh"

mode="${1:-}"
candidate="${2:-}"
[[ -e "$candidate" ]] || { echo "sign-macos-candidate: candidate is missing" >&2; exit 64; }

resolve_identity() {
  local configured="$1" resolved
  if [[ "$configured" =~ ^[0-9A-Fa-f]{40}$ ]]; then
    printf '%s\n' "$configured"
    return
  fi
  resolved="$(security find-identity -v -p codesigning | grep -F "\"$configured\"" | awk 'NR == 1 { print $2 }')"
  [[ "$resolved" =~ ^[0-9A-Fa-f]{40}$ ]] || {
    echo "sign-macos-candidate: configured signing identity was not found" >&2
    return 1
  }
  printf '%s\n' "$resolved"
}

# Stapling fetches the fresh ticket from Apple's CloudKit service, which can drop
# the connection right after notarization. Retry with growing pauses.
staple_with_retry() {
  local candidate="$1" attempt delay
  for attempt in 1 2 3 4 5; do
    if (( attempt == 1 )); then
      xcrun stapler staple "$candidate" && return 0
    else
      # Verbose output shows where the ticket request fails.
      xcrun stapler staple -v "$candidate" && return 0
    fi
    (( attempt < 5 )) || break
    delay=$(( attempt * ${GITLAMA_STAPLE_RETRY_SECONDS:-30} ))
    echo "sign-macos-candidate: stapling attempt $attempt failed; retrying in ${delay}s" >&2
    sleep "$delay"
  done
  echo "sign-macos-candidate: stapling failed after $attempt attempts" >&2
  return 1
}

case "$mode" in
  app)
    [[ -n "${CODESIGN_IDENTITY:-}" ]] || { echo "sign-macos-candidate: CODESIGN_IDENTITY is required" >&2; exit 1; }
    signing_identity="$(resolve_identity "$CODESIGN_IDENTITY")"
    codesign --force --deep --options runtime --timestamp \
      --entitlements "$ROOT/macos/Runner/Release.entitlements" \
      --sign "$signing_identity" "$candidate"
    codesign --verify --strict --deep "$candidate"
    codesign -d --verbose=4 "$candidate" 2>&1 | grep -F 'Authority=Developer ID Application:' >/dev/null
    ;;
  helper)
    # A remote helper bundled into the app: notarization inspects every Mach-O file, so it
    # carries the Developer ID, hardened runtime and a secure timestamp before its digest is
    # recorded. The app's own signing never touches Resources.
    [[ -n "${CODESIGN_IDENTITY:-}" ]] || { echo "sign-macos-candidate: CODESIGN_IDENTITY is required" >&2; exit 1; }
    signing_identity="$(resolve_identity "$CODESIGN_IDENTITY")"
    codesign --force --options runtime --timestamp --sign "$signing_identity" "$candidate"
    codesign --verify --strict "$candidate"
    codesign -d --verbose=4 "$candidate" 2>&1 | grep -F 'Authority=Developer ID Application:' >/dev/null
    ;;
  dmg)
    [[ -n "${CODESIGN_IDENTITY:-}" ]] || { echo "sign-macos-candidate: CODESIGN_IDENTITY is required" >&2; exit 1; }
    signing_identity="$(resolve_identity "$CODESIGN_IDENTITY")"
    codesign --force --timestamp --sign "$signing_identity" "$candidate"
    codesign --verify --strict "$candidate"
    ;;
  notarize)
    if [[ -n "${APPLE_API_KEY_FILE:-}" && -n "${APPLE_API_KEY_ID:-}" && -n "${APPLE_API_ISSUER_ID:-}" ]]; then
      xcrun notarytool submit "$candidate" \
        --key "$APPLE_API_KEY_FILE" \
        --key-id "$APPLE_API_KEY_ID" \
        --issuer "$APPLE_API_ISSUER_ID" \
        --wait
    elif [[ -n "${NOTARY_PROFILE:-}" ]]; then
      xcrun notarytool submit "$candidate" --keychain-profile "$NOTARY_PROFILE" --wait
    elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" && -n "${TEAM_ID:-}" ]]; then
      xcrun notarytool submit "$candidate" \
        --apple-id "$APPLE_ID" --password "$APPLE_APP_PASSWORD" --team-id "$TEAM_ID" --wait
    else
      echo "sign-macos-candidate: notarization credentials are required" >&2
      exit 1
    fi
    staple_with_retry "$candidate"
    xcrun stapler validate "$candidate"
    spctl -a -t open --context context:primary-signature -v "$candidate"
    ;;
  *)
    echo "Usage: sign-macos-candidate.sh app|dmg|notarize PATH" >&2
    exit 64
    ;;
esac
