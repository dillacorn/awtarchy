#!/usr/bin/env bash
# ~/.config/hypr/scripts/waybar_restore_resume.sh
#
# Called on resume/unlock: restore waybar ONLY if idle stopped it.

set -euo pipefail

CONF="${XDG_CONFIG_HOME:-$HOME/.config}"
SCRIPTS_DIR="${CONF}/hypr/scripts"
WAYBAR_SH="${WAYBAR_SH:-${SCRIPTS_DIR}/waybar.sh}"

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
IDLE_MARKER="${IDLE_MARKER:-${RUNTIME_DIR}/waybar.idle_restore}"

[[ -x "$WAYBAR_SH" ]] || { printf 'waybar_restore_resume: missing executable: %s\n' "$WAYBAR_SH" >&2; exit 1; }

if [[ "$(cat "$IDLE_MARKER" 2>/dev/null || true)" == "running" ]]; then
  if [[ "$("$WAYBAR_SH" status)" != "running" ]]; then
    "$WAYBAR_SH" start
  fi
  rm -f "$IDLE_MARKER" 2>/dev/null || true
fi
