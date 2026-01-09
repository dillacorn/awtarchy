#!/usr/bin/env bash
# ~/.config/hypr/scripts/waybar_toggle_idle.sh
#
# Called on idle/lock: stop ALL waybar instances via waybar.sh,
# but only mark restore if waybar was running.

set -euo pipefail

CONF="${XDG_CONFIG_HOME:-$HOME/.config}"
SCRIPTS_DIR="${CONF}/hypr/scripts"
WAYBAR_SH="${WAYBAR_SH:-${SCRIPTS_DIR}/waybar.sh}"

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
IDLE_MARKER="${IDLE_MARKER:-${RUNTIME_DIR}/waybar.idle_restore}"

[[ -x "$WAYBAR_SH" ]] || { printf 'waybar_toggle_idle: missing executable: %s\n' "$WAYBAR_SH" >&2; exit 1; }

if [[ "$("$WAYBAR_SH" status)" == "running" ]]; then
  echo "running" > "$IDLE_MARKER"
  "$WAYBAR_SH" stop
else
  rm -f "$IDLE_MARKER" 2>/dev/null || true
fi
