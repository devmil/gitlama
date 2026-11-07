#!/usr/bin/env bash
# Run inside the build container before the host copies private diagnostics.
set -euo pipefail
[[ "$#" == 2 ]] || { echo "diagnostics_handoff_arguments_invalid" >&2; exit 1; }
reference="$1"
directory="$2"
[[ -d "$reference" && ! -L "$reference" && -d "$directory" && ! -L "$directory" ]] || {
  echo "diagnostics_handoff_directory_invalid" >&2; exit 1;
}
shopt -s nullglob
archives=("$directory/"*-diagnostics.tar.gz)
[[ "${#archives[@]}" -gt 0 ]] || { echo "diagnostics_handoff_archives_missing" >&2; exit 1; }
for archive in "${archives[@]}"; do
  [[ -f "$archive" && ! -L "$archive" ]] || { echo "diagnostics_handoff_archive_invalid" >&2; exit 1; }
done
# The bind-mount owner's container UID/GID map back to the host owner under
# both rootful and rootless engines. Do not pass raw host IDs into a userns.
chmod 0700 -- "$directory"
chmod 0600 -- "${archives[@]}"
chown --reference="$reference" -- "$directory" "${archives[@]}"
