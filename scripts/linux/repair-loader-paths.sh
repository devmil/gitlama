#!/usr/bin/env bash
set -euo pipefail
bundle="${1:?Expected bundle directory}"
[[ -d "$bundle" ]] || exit 1
command -v patchelf >/dev/null

# Imported-engine paths may point into RUNNER_TEMP's portable SDK as well as
# the app checkout. Retain existing origin-relative entries, replacing absolute
# producer paths with the adjacent bundled library directory.
while IFS= read -r -d '' elf; do
  current_rpath="$(patchelf --print-rpath "$elf" 2>/dev/null || true)"
  if [[ "$current_rpath" == /* || "$current_rpath" == *:/* ]]; then
    relative_paths=()
    IFS=: read -r -a loader_paths <<< "$current_rpath"
    for loader_path in "${loader_paths[@]}"; do
      case "$loader_path" in
        '$ORIGIN'|'$ORIGIN/'*|'${ORIGIN}'|'${ORIGIN}/'*) relative_paths+=("$loader_path") ;;
      esac
    done
    relative_paths+=('$ORIGIN')
    repaired_rpath="$(IFS=:; echo "${relative_paths[*]}")"
    patchelf --set-rpath "$repaired_rpath" "$elf"
  fi
done < <(find "$bundle" -type f -print0)

