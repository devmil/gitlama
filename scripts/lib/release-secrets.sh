#!/usr/bin/env bash
# Release credentials from repository secrets. This file must be sourced.
#
# Key files arrive as base64 text in environment variables and are decoded into
# owner-only files. Values are never printed; failures name only the variable.

gitlama_secret_require() {
  local missing=0 variable
  for variable in "$@"; do
    if [[ -z "${!variable:-}" ]]; then
      echo "release-secrets: missing $variable" >&2
      missing=1
    fi
  done
  [[ "$missing" -eq 0 ]]
}

# Decodes the base64 secret named by $1 into the file $2.
gitlama_secret_file() {
  local variable="$1" output="$2"
  rm -f -- "$output"
  gitlama_secret_require "$variable" || return 1
  (
    umask 077
    GITLAMA_SECRET_VARIABLE="$variable" python3 -c '
import base64, binascii, os, sys
text = "".join(os.environ[os.environ["GITLAMA_SECRET_VARIABLE"]].split())
try:
    data = base64.b64decode(text, validate=True)
except (binascii.Error, ValueError):
    sys.exit(1)
if not data:
    sys.exit(1)
sys.stdout.buffer.write(data)
' >"$output" 2>/dev/null
  ) || {
    rm -f -- "$output"
    echo "release-secrets: $variable is not valid base64" >&2
    return 1
  }
  chmod 600 "$output"
}
