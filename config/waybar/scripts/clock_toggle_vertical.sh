#!/usr/bin/env bash
# ~/.config/waybar/scripts/clock_toggle_vertical.sh
# Keeps JSON output from clock_toggle.sh, but:
# - removes leading icon from .text
# - "HH:MM" -> "HH\nMM"
# - "MM-DD" -> "MM\nDD"
set -euo pipefail
SRC="${XDG_CONFIG_HOME:-$HOME/.config}/waybar/scripts/clock_toggle.sh"
json="$("$SRC" 2>/dev/null || true)"

if command -v jq >/dev/null 2>&1; then
  jq -c '
    .text |= sub("^[^ ]+ +";"")
    | if (.text|test(":")) then .text |= gsub(":";"\n")
      elif (.text|test("-")) then .text |= gsub("-";"\n")
      else . end
  ' <<<"$json"
else
  printf '%s\n' "$json"
fi
