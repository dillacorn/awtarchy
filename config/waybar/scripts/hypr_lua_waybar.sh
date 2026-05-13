#!/usr/bin/env bash
# ~/.config/waybar/scripts/hypr_lua_waybar.sh
# Waybar helpers for Hyprland 0.55 Lua dispatch.

set -euo pipefail

SUBMAP_FILE="${HYPR_SUBMAP_FILE:-/tmp/hypr-submap}"

have() { command -v "$1" >/dev/null 2>&1; }
need() { have "$1" || { printf 'missing command: %s\n' "$1" >&2; exit 1; }; }

json_string() {
  jq -Rn --arg s "$1" '$s'
}

json_array_from_csv() {
  local csv="${1:-}"
  if [[ -z "$csv" ]]; then
    printf '[]'
    return 0
  fi
  printf '%s' "$csv" | awk -F, '{
    printf "["
    for (i=1; i<=NF; i++) {
      gsub(/^[ \t]+|[ \t]+$/, "", $i)
      if ($i == "") continue
      if (n++) printf ","
      gsub(/\\/, "\\\\", $i)
      gsub(/\"/, "\\\"", $i)
      printf "\"%s\"", $i
    }
    printf "]"
  }'
}

json_module() {
  local text="$1" tooltip="${2:-}" class_csv="${3:-}"
  local text_json tooltip_json class_json
  text_json="$(json_string "$text")"
  tooltip_json="$(json_string "${tooltip:-$text}")"
  class_json="$(json_array_from_csv "$class_csv")"
  printf '{"text":%s,"tooltip":%s,"class":%s}\n' "$text_json" "$tooltip_json" "$class_json"
}

signal_waybar() {
  pkill -RTMIN+11 waybar 2>/dev/null || true
  pkill -RTMIN+12 waybar 2>/dev/null || true
}

lua_dispatch() {
  need hyprctl
  hyprctl dispatch "$1" >/dev/null 2>&1 || true
}

focused_ws_id() {
  need hyprctl
  need jq
  hyprctl -j monitors 2>/dev/null | jq -r '([.[] | select(.focused == true)][0].activeWorkspace.id // .[0].activeWorkspace.id // 0)'
}

workspace_exists() {
  local id="$1"
  need hyprctl
  need jq
  hyprctl -j workspaces 2>/dev/null | jq -e --argjson id "$id" 'any(.[]; .id == $id)' >/dev/null 2>&1
}

workspace_icon() {
  case "$1" in
    1) printf '1 󱾷' ;;
    2) printf '2 ' ;;
    3) printf '3 ' ;;
    4) printf '4 ' ;;
    5) printf '5 ' ;;
    6) printf '6 ' ;;
    7) printf '7 ' ;;
    8) printf '8 ' ;;
    9) printf '9 ' ;;
    10) printf '10 ' ;;
    *) printf '%s' "$1" ;;
  esac
}

submap_current() {
  local s=""
  s="$(hyprctl submap 2>/dev/null | tr -d '\r' | awk 'NF{print $1; exit}' || true)"
  case "$s" in
    ""|reset|default) printf '' ;;
    *) printf '%s' "$s" ;;
  esac
}

submap_write_file() {
  local name="$1"
  if [[ -z "$name" ]]; then
    : > "$SUBMAP_FILE"
  else
    printf '%s\n' "$name" > "$SUBMAP_FILE"
  fi
}

submap_notify() {
  local name="$1" state="$2"
  have notify-send || return 0
  if [[ -z "$name" ]]; then
    notify-send -a Hyprland -t 1000 'submap: OFF' >/dev/null 2>&1 || true
  else
    notify-send -a Hyprland -t 1000 "${name} mode: ${state}" >/dev/null 2>&1 || true
  fi
}

cmd="${1:-}"
case "$cmd" in
  ws-status)
    id="${2:?workspace id required}"
    active="$(focused_ws_id || printf 0)"
    text="$(workspace_icon "$id")"
    classes=()
    tooltip="Workspace $id"
    if [[ "$active" == "$id" ]]; then
      classes+=(active)
      tooltip="Workspace $id active"
    elif workspace_exists "$id"; then
      classes+=(occupied)
      tooltip="Workspace $id occupied"
    else
      classes+=(empty)
      tooltip="Workspace $id empty"
    fi
    IFS=,; json_module "$text" "$tooltip" "${classes[*]}"
    ;;

  ws-focus)
    id="${2:?workspace id required}"
    lua_dispatch "hl.dsp.focus({ workspace = ${id} })"
    signal_waybar
    ;;

  ws-move)
    id="${2:?workspace id required}"
    lua_dispatch "hl.dsp.window.move({ workspace = ${id}, follow = false })"
    signal_waybar
    ;;

  ws-next)
    lua_dispatch 'hl.dsp.focus({ workspace = "+1" })'
    signal_waybar
    ;;

  ws-prev)
    lua_dispatch 'hl.dsp.focus({ workspace = "-1" })'
    signal_waybar
    ;;

  ws-monitor)
    dir="${2:?monitor direction required}"
    lua_dispatch "hl.dsp.workspace.move({ monitor = \"${dir}\" })"
    signal_waybar
    ;;

  submap-status)
    s="$(submap_current)"
    if [[ -z "$s" ]]; then
      submap_write_file ""
      json_module "" "No active submap" "inactive"
    else
      submap_write_file "$s"
      json_module "$s" "Current submap: $s. Click to reset." "active,$s"
    fi
    ;;

  submap-set)
    name="${2:?submap name required}"
    lua_dispatch "hl.dsp.submap(\"${name}\")"
    submap_write_file "$name"
    submap_notify "$name" ON
    signal_waybar
    ;;

  submap-reset)
    lua_dispatch 'hl.dsp.submap("reset")'
    submap_write_file ""
    submap_notify "" OFF
    signal_waybar
    ;;

  submap-toggle)
    name="${2:?submap name required}"
    cur="$(submap_current)"
    if [[ "$cur" == "$name" ]]; then
      "$0" submap-reset
    else
      "$0" submap-set "$name"
    fi
    ;;

  *)
    cat >&2 <<'EOF'
Usage:
  hypr_lua_waybar.sh ws-status <1..10>
  hypr_lua_waybar.sh ws-focus <1..10>
  hypr_lua_waybar.sh ws-move <1..10>
  hypr_lua_waybar.sh ws-next|ws-prev
  hypr_lua_waybar.sh ws-monitor <l|r|u|d>
  hypr_lua_waybar.sh submap-status
  hypr_lua_waybar.sh submap-set <name>
  hypr_lua_waybar.sh submap-reset
  hypr_lua_waybar.sh submap-toggle <name>
EOF
    exit 2
    ;;
esac
