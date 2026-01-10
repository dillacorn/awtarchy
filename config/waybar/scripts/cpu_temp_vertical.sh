#!/usr/bin/env bash
# ~/.config/waybar/scripts/cpu_temp_vertical.sh
#
# Vertical-friendly CPU temp for Waybar custom module.
# Emits ONE LINE of JSON with a real newline in .text.

set -euo pipefail

command -v jq >/dev/null 2>&1 || { echo '{"text":"jq missing","class":["cputemp"]}'; exit 0; }

SRC="${XDG_CONFIG_HOME:-$HOME/.config}/waybar/scripts/cpu_temp.sh"
out="$("$SRC" 2>/dev/null || true)"
out="${out//$'\r'/}"

# cpu_temp.sh prints: "<temp>°<icon>" (example: "60°")
if [[ "$out" =~ ^([0-9]+)°(.+)$ ]]; then
  temp="${BASH_REMATCH[1]}"
  icon="${BASH_REMATCH[2]}"
  text="${icon}"$'\n'"${temp}°"
  jq -cn --arg t "$text" '{text:$t, class:["cputemp"]}'
  exit 0
fi

jq -cn --arg t "$out" '{text:$t, class:["cputemp"]}'
