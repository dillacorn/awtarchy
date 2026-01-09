#!/usr/bin/env bash
# FILE: ~/.config/hypr/scripts/waybar_rotate.sh
#
# Rotate ONLY the focused monitor between horizontal and vertical.
# Does NOT start/enable bars that are currently disabled/off.
# Remembers last horizontal + last vertical per monitor in ~/.cache/waybar/state.json

set -euo pipefail

SCRIPTS_DIR="${SCRIPTS_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts}"
WAYBAR_SH="${WAYBAR_SH:-$SCRIPTS_DIR/waybar.sh}"

CACHE_DIR="${CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/waybar}"
STATE_FILE="${STATE_FILE:-$CACHE_DIR/state.json}"

need() { command -v "$1" >/dev/null 2>&1 || { printf 'waybar_rotate: missing: %s\n' "$1" >&2; exit 127; }; }
need jq

[[ -x "$WAYBAR_SH" ]] || { printf 'waybar_rotate: missing executable: %s\n' "$WAYBAR_SH" >&2; exit 1; }
[[ -f "$STATE_FILE" ]] || "$WAYBAR_SH" dump-state >/dev/null 2>&1 || true

mon="$("$WAYBAR_SH" focused-monitor)"
[[ -n "$mon" ]] || { printf 'waybar_rotate: cannot determine focused monitor\n' >&2; exit 1; }

pos="$("$WAYBAR_SH" getpos-focused)"

# Ensure last_* keys exist without wiping anything
tmp="$(mktemp)"
jq --arg m "$mon" '
  .monitors[$m] = ((.monitors[$m] // {}) + {})
' "$STATE_FILE" > "$tmp"
mv "$tmp" "$STATE_FILE"

if [[ "$pos" == "left" || "$pos" == "right" ]]; then
  # going vertical -> horizontal
  tmp="$(mktemp)"
  jq --arg m "$mon" --arg v "$pos" '
    .monitors[$m].last_vertical = $v
  ' "$STATE_FILE" > "$tmp"
  mv "$tmp" "$STATE_FILE"

  target="$(jq -r --arg m "$mon" '.monitors[$m].last_horizontal // "top"' "$STATE_FILE")"
  "$WAYBAR_SH" setpos-focused "$target"
else
  # going horizontal -> vertical
  tmp="$(mktemp)"
  jq --arg m "$mon" --arg h "$pos" '
    .monitors[$m].last_horizontal = $h
  ' "$STATE_FILE" > "$tmp"
  mv "$tmp" "$STATE_FILE"

  target="$(jq -r --arg m "$mon" '.monitors[$m].last_vertical // "right"' "$STATE_FILE")"
  "$WAYBAR_SH" setpos-focused "$target"
fi
