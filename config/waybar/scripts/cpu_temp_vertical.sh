#!/usr/bin/env bash
# ~/.config/waybar/scripts/cpu_temp_vertical.sh
# Outputs one field for vertical split: icon|temp
#
# cpu_temp.sh expected output: "<temp>°<icon>" (example: "50°")

set -euo pipefail

mode="${1:-}"
SRC="${XDG_CONFIG_HOME:-$HOME/.config}/waybar/scripts/cpu_temp.sh"

out="$("$SRC" 2>/dev/null || true)"
out="${out//$'\r'/}"

temp="$out"
icon=""

if [[ "$out" =~ ^([0-9]+)°(.+)$ ]]; then
  temp="${BASH_REMATCH[1]}°"
  icon="${BASH_REMATCH[2]}"
fi

case "$mode" in
  icon) printf '%s\n' "$icon" ;;
  temp) printf '%s\n' "$temp" ;;
  *)
    # default: keep something useful
    printf '%s\n' "$out"
    ;;
esac
