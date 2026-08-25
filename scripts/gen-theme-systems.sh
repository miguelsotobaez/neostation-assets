#!/usr/bin/env bash
# Regenerates the "systems" array in every theme's theme.json from the actual
# files in that theme's backgrounds/ directory. Requires: jq
set -euo pipefail

# Defaults to the repo itself; pass a root (e.g. dist/) to regenerate the
# systems lists of a built pack against the files that pack actually contains.
repo_root="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")/..}" && pwd)"
themes_dir="$repo_root/themes"

changed=0
for theme_dir in "$themes_dir"/*/; do
  theme_json="$theme_dir/theme.json"
  bg_dir="$theme_dir/backgrounds"
  [ -f "$theme_json" ] || continue

  systems_json="[]"
  if [ -d "$bg_dir" ]; then
    systems_json=$(
      find "$bg_dir" -maxdepth 1 -type f \( -name '*.webp' -o -name '*.gif' \) \
        -printf '%f\n' 2>/dev/null \
        | sed -E 's/\.(webp|gif)$//' \
        | sort -u \
        | jq -R . | jq -s .
    )
  fi

  tmp="$(mktemp)"
  jq --argjson systems "$systems_json" '.systems = $systems' "$theme_json" > "$tmp"

  if ! cmp -s "$tmp" "$theme_json"; then
    mv "$tmp" "$theme_json"
    echo "updated: ${theme_json#"$repo_root"/} ($(echo "$systems_json" | jq length) systems)"
    changed=1
  else
    rm -f "$tmp"
  fi
done

if [ "$changed" -eq 0 ]; then
  echo "theme.json systems lists already up to date"
fi
