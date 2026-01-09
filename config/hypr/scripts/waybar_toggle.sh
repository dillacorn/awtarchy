#!/usr/bin/env bash
# Toggle Waybar and keep /tmp/waybar.state updated.
# Also updates fuzzel.ini [main] anchor=:
# - when stopping Waybar  -> center
# - when starting Waybar  -> top or bottom (based on Waybar config "position")
#
# Respects user choice: if fuzzel.ini is missing OR anchor= is removed/commented-out in [main],
# this script will NOT add it back.

set -euo pipefail

STATE_FILE="${STATE_FILE:-/tmp/waybar.state}"
WAYBAR_BIN="${WAYBAR_BIN:-waybar}"

WAYBAR_CFG="${WAYBAR_CFG:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar/config}"
WAYBAR_CFG_FALLBACK="${WAYBAR_CFG_FALLBACK:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar/config.jsonc}"

FUZZEL_INI="${FUZZEL_INI:-${XDG_CONFIG_HOME:-$HOME/.config}/fuzzel/fuzzel.ini}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "waybar_toggle: missing: $1" >&2; exit 127; }; }

pick_waybar_cfg() {
  if [[ -f "$WAYBAR_CFG" ]]; then
    printf '%s\n' "$WAYBAR_CFG"
  elif [[ -f "$WAYBAR_CFG_FALLBACK" ]]; then
    printf '%s\n' "$WAYBAR_CFG_FALLBACK"
  else
    printf '%s\n' ""
  fi
}

waybar_position() {
  local cfg="$1"
  [[ -n "$cfg" && -f "$cfg" ]] || { printf '%s\n' "unknown"; return 0; }

  if grep -qE '"position"[[:space:]]*:[[:space:]]*"top"' "$cfg"; then
    printf '%s\n' "top"
  elif grep -qE '"position"[[:space:]]*:[[:space:]]*"bottom"' "$cfg"; then
    printf '%s\n' "bottom"
  else
    printf '%s\n' "unknown"
  fi
}

has_active_fuzzel_anchor_in_main() {
  local ini="$1"
  awk '
    BEGIN { inmain=0; found=0 }
    /^\[main\]$/ { inmain=1; next }
    /^\[/        { inmain=0; next }
    {
      if (inmain &&
          $0 ~ /^[[:space:]]*anchor[[:space:]]*=/ &&
          $0 !~ /^[[:space:]]*[#;]/) { found=1; exit }
    }
    END { exit(found ? 0 : 1) }
  ' "$ini"
}

set_fuzzel_anchor_if_present() {
  need awk
  local a="$1"
  local ini="$FUZZEL_INI"

  [[ -f "$ini" ]] || return 0
  has_active_fuzzel_anchor_in_main "$ini" || return 0

  awk -v a="$a" '
    BEGIN { inmain=0 }
    /^\[main\]$/ { inmain=1; print; next }
    /^\[/        { inmain=0; print; next }
    {
      if (inmain &&
          $0 ~ /^[[:space:]]*anchor[[:space:]]*=/ &&
          $0 !~ /^[[:space:]]*[#;]/) {
        sub(/^[[:space:]]*anchor[[:space:]]*=.*/, "anchor=" a)
        print
        next
      }
      print
    }
  ' "$ini" >"$ini.tmp" && mv "$ini.tmp" "$ini"
}

stop_waybar() {
  need pkill
  need pgrep

  pkill -x waybar 2>/dev/null || true

  # wait up to ~0.5s
  for _ in {1..20}; do
    pgrep -x waybar >/dev/null 2>&1 || return 0
    sleep 0.025
  done

  # force if still alive
  pkill -KILL -x waybar 2>/dev/null || true
}

start_waybar() {
  need nohup
  nohup "$WAYBAR_BIN" >/dev/null 2>&1 &
}

if pgrep -x waybar >/dev/null 2>&1; then
  stop_waybar
  echo "waybar_not_running" >"$STATE_FILE"
  set_fuzzel_anchor_if_present "center"
  exit 0
fi

# starting waybar
start_waybar
echo "waybar_running" >"$STATE_FILE"

cfg="$(pick_waybar_cfg)"
pos="$(waybar_position "$cfg")"
case "$pos" in
  top)    set_fuzzel_anchor_if_present "top" ;;
  bottom) set_fuzzel_anchor_if_present "bottom" ;;
  *)      : ;;
esac
