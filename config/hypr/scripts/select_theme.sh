#!/usr/bin/env bash
# github.com/dillacorn/awtarchy/tree/main/config/hypr/scripts
# ~/.config/hypr/scripts/select_theme.sh

set -euo pipefail

THEME_DIR="${HOME}/.config/hypr/themes"

# Prefer fuzzel; fall back to wofi if fuzzel is missing.
if command -v fuzzel >/dev/null 2>&1; then
  THEME="$(
    find "$THEME_DIR" -maxdepth 1 -type f -executable -printf '%f\n' 2>/dev/null \
      | LC_ALL=C sort \
      | fuzzel --dmenu --prompt "Choose theme: " --lines 12 --width 40
  )"
else
  THEME="$(
    find "$THEME_DIR" -maxdepth 1 -type f -executable -exec basename {} \; 2>/dev/null \
      | wofi --dmenu -i -p "Choose theme"
  )"
fi

if [[ -n "${THEME:-}" ]]; then
  "${THEME_DIR}/${THEME}"
fi
