#!/usr/bin/env bash

# Normalize `security list-keychains` output before passing paths back to
# `security list-keychains -s`. macOS indents and quotes each path.
gitlama_existing_keychains() {
  local line seen
  seen=$'\n'
  while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line#\"}"
    line="${line%\"}"
    [[ -f "$line" ]] || continue
    if [[ "$seen" != *$'\n'"$line"$'\n'* ]]; then
      printf '%s\n' "$line"
      seen+="$line"$'\n'
    fi
  done
}
