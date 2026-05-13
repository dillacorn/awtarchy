#!/usr/bin/env bash

# ~/.config/waybar/scripts/idle_inhibitor_global.sh
# Global idle inhibitor for all Waybar instances.
#
# Requires:
#   systemd-inhibit
#
# Hypridle must not ignore systemd idle inhibitors:
#   general {
#     ignore_systemd_inhibit = false
#   }

set -euo pipefail
export LC_ALL=C

SIGNAL="${WAYBAR_IDLE_SIGNAL:-13}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
PID_FILE="${RUNTIME_DIR}/waybar-global-idle-inhibitor.pid"
WHAT="${WAYBAR_IDLE_WHAT:-idle}"

mkdir -p "$STATE_DIR"

cleanup_dead_pid() {
  if [[ -f "$PID_FILE" ]]; then
    local pid
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"

    if [[ ! "$pid" =~ ^[0-9]+$ ]] || ! kill -0 "$pid" 2>/dev/null; then
      rm -f "$PID_FILE"
    fi
  fi
}

is_active() {
  cleanup_dead_pid

  if [[ -f "$PID_FILE" ]]; then
    local pid
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null
  else
    return 1
  fi
}

signal_waybar() {
  pkill "-RTMIN+${SIGNAL}" waybar 2>/dev/null || true
}

start_inhibitor() {
  if ! command -v systemd-inhibit >/dev/null 2>&1; then
    printf '{"text":"","tooltip":"systemd-inhibit not found","class":["error"]}\n'
    exit 1
  fi

  if is_active; then
    return 0
  fi

  setsid systemd-inhibit \
    --what="$WHAT" \
    --who="waybar" \
    --why="Waybar global idle inhibitor" \
    --mode=block \
    sleep infinity >/dev/null 2>&1 &

  printf '%s\n' "$!" > "$PID_FILE"
}

stop_inhibitor() {
  cleanup_dead_pid

  if [[ -f "$PID_FILE" ]]; then
    local pid
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"

    if [[ "$pid" =~ ^[0-9]+$ ]]; then
      kill -- "-$pid" 2>/dev/null || kill "$pid" 2>/dev/null || true
    fi

    rm -f "$PID_FILE"
  fi
}

case "${1:-status}" in
  toggle)
    if is_active; then
      stop_inhibitor
    else
      start_inhibitor
    fi

    signal_waybar
    exit 0
    ;;

  on)
    start_inhibitor
    signal_waybar
    exit 0
    ;;

  off)
    stop_inhibitor
    signal_waybar
    exit 0
    ;;

  status|"")
    ;;
esac

if is_active; then
  printf '{"text":"","tooltip":"Idle inhibitor: activated\\nClick to deactivate","class":["activated"]}\n'
else
  printf '{"text":"","tooltip":"Idle inhibitor: deactivated\\nClick to activate","class":["deactivated"]}\n'
fi
