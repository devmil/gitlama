# shellcheck shell=bash
# Load optional signing references without printing their values.

_gitlama_signing_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
_gitlama_signing_file="${GITLAMA_SIGNING_ENV:-$_gitlama_signing_root/.env.signing}"
if [[ -f "$_gitlama_signing_file" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$_gitlama_signing_file"
  set +a
fi
unset _gitlama_signing_file _gitlama_signing_root
