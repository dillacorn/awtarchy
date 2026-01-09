#!/usr/bin/env bash
# FILE: ~/.config/hypr/scripts/waybar_toggle.sh
#
# Toggle Waybar via waybar.sh and keep /tmp/waybar.state updated.

set -euo pipefail

STATE_FILE="${STATE_FILE:-/tmp/waybar.state}"
SCRIPTS_DIR="${SCRIPTS_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts}"
WAYBAR_SH="${WAYBAR_SH:-${SCRIPTS_DIR}/waybar.sh}"

[[ -x "$WAYBAR_SH" ]] || { printf 'waybar_toggle: missing executable: %s\n' "$WAYBAR_SH" >&2; exit 1; }

if [[ "$("$WAYBAR_SH" status)" == "running" ]]; then
  "$WAYBAR_SH" disable
  "$WAYBAR_SH" stop
  echo waybar_not_running > "$STATE_FILE"
else
  "$WAYBAR_SH" enable
  "$WAYBAR_SH" start
  echo waybar_running > "$STATE_FILE"
fi
