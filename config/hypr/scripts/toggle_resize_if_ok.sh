#!/usr/bin/env bash
# github.com/dillacorn/awtarchy/tree/main/config/hypr/scripts
# ~/.config/hypr/scripts/toggle_resize_if_ok.sh
#
# Behavior:
# - Toggle "resize" submap on/off with safety checks
# - Auto-exit resize if workspace changes
# - Always notify Waybar (signal RTMIN+12) so custom/submap updates

set -euo pipefail

SELF="$(readlink -f "$0")"
STATE_FILE="/tmp/hypr-resize.state"
WATCH_PID_FILE="/tmp/hypr-resize.wpid"

notify_waybar() {
  # Tell Waybar to refresh custom/submap ("signal": 12)
  pkill -RTMIN+12 waybar 2>/dev/null || true
}

reset_mode() {
  hyprctl dispatch submap reset >/dev/null 2>&1 || true

  if [[ -f "$WATCH_PID_FILE" ]]; then
    pid="$(cat "$WATCH_PID_FILE" 2>/dev/null || echo)"
    [[ -n "${pid:-}" ]] && kill "$pid" >/dev/null 2>&1 || true
    rm -f "$WATCH_PID_FILE"
  fi

  rm -f "$STATE_FILE"

  notify_waybar
}

# Explicit reset (used by your exit binds)
if [[ "${1:-}" == "reset" ]]; then
  reset_mode
  exit 0
fi

# If we believe we're already active, toggle OFF
if [[ -f "$STATE_FILE" ]]; then
  reset_mode
  exit 0
fi

# Require an active window
aw="$(hyprctl -j activewindow 2>/dev/null || echo null)"
[[ "$aw" == "null" || -z "$aw" ]] && exit 0

# Block if fullscreen (covers multiple Hyprland versions)
if printf '%s' "$aw" | jq -e '
  (.fullscreen == true)
  or ((.fullscreen? | numbers) > 0)
  or ((.fullscreenstate?.internal? // 0) > 0)
  or ((.fullscreenstate?.client?   // 0) > 0)
' >/dev/null; then
  exit 0
fi

# Workspace must have >1 window
ws_id="$(hyprctl -j activeworkspace | jq -r '.id')"
count="$(hyprctl -j clients | jq --argjson ws "$ws_id" '[.[] | select(.workspace.id == $ws)] | length')"
[[ "${count:-0}" -le 1 ]] && exit 0

# Enter resize submap
hyprctl dispatch submap resize >/dev/null 2>&1 || true

# Record current workspace
printf '%s\n' "$ws_id" > "$STATE_FILE"

# Spawn watcher: exit resize if workspace changes
(
  start_ws="$ws_id"
  while :; do
    cur_ws="$(hyprctl -j activeworkspace | jq -r '.id' 2>/dev/null || echo "")"
    if [[ -n "$cur_ws" && "$cur_ws" != "$start_ws" ]]; then
      "$SELF" reset
      break
    fi
    sleep 0.2
  done
) & echo $! > "$WATCH_PID_FILE"

notify_waybar
