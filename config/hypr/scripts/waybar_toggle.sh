#!/usr/bin/env bash
# FILE: ~/.config/hypr/scripts/waybar_toggle.sh
# Default: toggle ONLY the focused monitor.

set -euo pipefail

SCRIPTS_DIR="${SCRIPTS_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts}"
WAYBAR_SH="${WAYBAR_SH:-$SCRIPTS_DIR/waybar.sh}"

[[ -x "$WAYBAR_SH" ]] || { printf 'waybar_toggle: missing: %s\n' "$WAYBAR_SH" >&2; exit 1; }

case "${1:-}" in
  --mon)
    mon="${2:-}"
    [[ -n "$mon" ]] || { printf 'usage: waybar_toggle.sh --mon <MON>\n' >&2; exit 2; }
    "$WAYBAR_SH" toggle-mon "$mon"
    ;;
  ""|--focused|-f)
    "$WAYBAR_SH" toggle-focused
    ;;
  *)
    printf 'usage: waybar_toggle.sh [--focused] | --mon <MON>\n' >&2
    exit 2
    ;;
esac
