#!/usr/bin/env bash
# FILE: ~/.config/hypr/scripts/waybar_flip.sh
#
# Flip Waybar side for the focused monitor:
#   top <-> bottom
#   left <-> right
#
# Closes fuzzel to avoid stale placement.

set -euo pipefail

SCRIPTS_DIR="${SCRIPTS_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts}"
WAYBAR_SH="${WAYBAR_SH:-${SCRIPTS_DIR}/waybar.sh}"

[[ -x "$WAYBAR_SH" ]] || { printf 'waybar_flip: missing executable: %s\n' "$WAYBAR_SH" >&2; exit 1; }

pkill -x fuzzel 2>/dev/null || true
"$WAYBAR_SH" flip-focused
