#!/usr/bin/env bash
# Vaultwarden access for the protected release workflow. This file must be sourced.
#
# The server address is a secret (BW_SERVER) like the credentials: it is masked in the
# workflow log and never printed. Bitwarden CLI output and errors are discarded because
# they can name the server; failures report a fixed message instead.

gitlama_vault_require_environment() {
  local missing=0 variable
  for variable in BW_SERVER BW_CLIENTID BW_CLIENTSECRET BW_PASSWORD BW_RELEASE_ITEM_ID; do
    if [[ -z "${!variable:-}" ]]; then
      echo "vaultwarden-release: missing $variable" >&2
      missing=1
    fi
  done
  [[ "$missing" -eq 0 ]]
}

gitlama_vault_login() {
  gitlama_vault_require_environment || return 1
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::add-mask::$BW_SERVER"
  fi
  command -v bw >/dev/null || {
    echo "vaultwarden-release: the Bitwarden CLI (bw) is required" >&2
    return 1
  }
  command -v jq >/dev/null || {
    echo "vaultwarden-release: jq is required" >&2
    return 1
  }
  bw config server "$BW_SERVER" >/dev/null 2>&1 || {
    echo "vaultwarden-release: the vault server could not be configured" >&2
    return 1
  }
  bw login --apikey >/dev/null 2>&1 || {
    echo "vaultwarden-release: vault login failed" >&2
    return 1
  }
  bw sync >/dev/null 2>&1 || {
    echo "vaultwarden-release: vault sync failed" >&2
    return 1
  }
  BW_SESSION="$(bw unlock --passwordenv BW_PASSWORD --raw 2>/dev/null)" || BW_SESSION=""
  [[ -n "$BW_SESSION" ]] || {
    echo "vaultwarden-release: vault unlock returned no session" >&2
    return 1
  }
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::add-mask::$BW_SESSION"
  fi
  export BW_SESSION
}

gitlama_vault_item() {
  bw get item "$BW_RELEASE_ITEM_ID" --session "$BW_SESSION" 2>/dev/null || {
    echo "vaultwarden-release: the release item could not be read" >&2
    return 1
  }
}

gitlama_vault_field() {
  local item_json="$1" field="$2" value
  value="$(jq -er --arg field "$field" \
    '.fields[] | select(.name == $field) | .value' <<<"$item_json")" || {
    echo "vaultwarden-release: release item has no $field field" >&2
    return 1
  }
  [[ -n "$value" && "$value" != "null" ]] || {
    echo "vaultwarden-release: item field $field is empty" >&2
    return 1
  }
  printf '%s' "$value"
}

gitlama_vault_attachment() {
  local filename="$1" output="$2"
  bw get attachment "$filename" --itemid "$BW_RELEASE_ITEM_ID" \
    --output "$output" --session "$BW_SESSION" >/dev/null 2>&1 || true
  [[ -s "$output" ]] || {
    echo "vaultwarden-release: attachment $filename was not downloaded" >&2
    return 1
  }
  chmod 600 "$output"
}

gitlama_vault_logout() {
  if command -v bw >/dev/null 2>&1; then
    bw lock >/dev/null 2>&1 || true
    bw logout >/dev/null 2>&1 || true
  fi
  unset BW_SESSION
}
