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
uid="$(id -u)"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/${uid}}"
PID_FILE="${RUNTIME_DIR}/waybar-global-idle-inhibitor.pid"

WHAT="${WAYBAR_IDLE_WHAT:-idle}"
WHO="${WAYBAR_IDLE_WHO:-waybar}"
WHY="${WAYBAR_IDLE_WHY:-Waybar global idle inhibitor}"
PROC_NAME="${WAYBAR_IDLE_PROC_NAME:-waybar-global-idle-inhibitor}"

mkdir -p "$RUNTIME_DIR"

read_pid_file() {
  [[ -f "$PID_FILE" ]] || return 1
  cat "$PID_FILE" 2>/dev/null || true
}

valid_pid() {
  local pid="${1:-}"
  [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null
}

matching_inhibitor_pids() {
  pgrep -u "$uid" -f "$PROC_NAME" 2>/dev/null || true
  pgrep -u "$uid" -f "systemd-inhibit.*${WHY}" 2>/dev/null || true
}

cleanup_dead_pid() {
  local pid
  pid="$(read_pid_file || true)"

  if [[ -z "$pid" ]] || ! valid_pid "$pid"; then
    rm -f "$PID_FILE"
  fi
}

systemd_inhibit_active() {
  command -v systemd-inhibit >/dev/null 2>&1 || return 1
  systemd-inhibit --list --no-pager 2>/dev/null | grep -Fq "$WHY"
}

is_active() {
  cleanup_dead_pid

  local pid
  pid="$(read_pid_file || true)"

  if valid_pid "$pid"; then
    return 0
  fi

  if matching_inhibitor_pids | grep -qE '^[0-9]+$'; then
    return 0
  fi

  if systemd_inhibit_active; then
    return 0
  fi

  return 1
}

signal_waybar() {
  pkill -RTMIN+"${SIGNAL}" -x waybar 2>/dev/null || true
}

kill_pid_and_group() {
  local pid="${1:-}"

  [[ "$pid" =~ ^[0-9]+$ ]] || return 0
  [[ "$pid" == "$$" ]] && return 0

  kill -- "-$pid" 2>/dev/null || true
  kill "$pid" 2>/dev/null || true
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
    --who="$WHO" \
    --why="$WHY" \
    --mode=block \
    bash -c "trap 'exit 0' TERM INT HUP; exec -a \"\$0\" sleep infinity" "$PROC_NAME" \
    >/dev/null 2>&1 &

  printf '%s\n' "$!" >"$PID_FILE"
}

stop_inhibitor() {
  cleanup_dead_pid

  local pid
  pid="$(read_pid_file || true)"
  kill_pid_and_group "$pid"

  while read -r pid; do
    kill_pid_and_group "$pid"
  done < <(matching_inhibitor_pids | sort -u)

  sleep 0.15

  while read -r pid; do
    [[ "$pid" =~ ^[0-9]+$ ]] || continue
    [[ "$pid" == "$$" ]] && continue

    kill -9 -- "-$pid" 2>/dev/null || true
    kill -9 "$pid" 2>/dev/null || true
  done < <(matching_inhibitor_pids | sort -u)

  rm -f "$PID_FILE"
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

  is-active)
    if is_active; then
      exit 0
    fi
    exit 1
    ;;

  status|"")
    ;;

  *)
    printf '{"text":"","tooltip":"Unknown idle inhibitor command: %s","class":["error"]}\n' "${1:-}"
    exit 1
    ;;
esac

if is_active; then
  printf '{"text":"","tooltip":"Idle inhibitor: activated\\nClick to deactivate","class":["activated"]}\n'
else
  printf '{"text":"","tooltip":"Idle inhibitor: deactivated\\nClick to activate","class":["deactivated"]}\n'
fi
