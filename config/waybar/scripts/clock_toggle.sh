#!/usr/bin/env bash

# ~/.config/waybar/scripts/clock_toggle.sh
# Instance-scoped Waybar clock/date toggle.
#
# Scope priority:
#   1. WAYBAR_CLOCK_SCOPE, if explicitly set
#   2. nearest ancestor waybar PID
#   3. current parent PID fallback

set -euo pipefail
export LC_ALL=C

SIGNAL="${WAYBAR_CLOCK_SIGNAL:-12}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}"
mkdir -p "$STATE_DIR"

find_waybar_pid() {
  local pid="${1:-${PPID:-}}"
  local comm=""
  local ppid=""

  while [[ "$pid" =~ ^[0-9]+$ ]] && (( pid > 1 )); do
    if [[ -r "/proc/$pid/comm" ]]; then
      IFS= read -r comm < "/proc/$pid/comm" || comm=""
      if [[ "$comm" == "waybar" ]]; then
        printf '%s\n' "$pid"
        return 0
      fi
    fi

    if [[ ! -r "/proc/$pid/status" ]]; then
      break
    fi

    ppid="$(awk '/^PPid:/ {print $2; exit}' "/proc/$pid/status" 2>/dev/null || true)"
    [[ "$ppid" =~ ^[0-9]+$ ]] || break
    [[ "$ppid" == "$pid" ]] && break
    pid="$ppid"
  done

  return 1
}

safe_name() {
  tr -cs 'A-Za-z0-9._-' '_' | sed -e 's/^_//' -e 's/_$//'
}

waybar_pid="$(find_waybar_pid || true)"

if [[ -n "${WAYBAR_CLOCK_SCOPE:-}" ]]; then
  scope="$(printf '%s' "$WAYBAR_CLOCK_SCOPE" | safe_name)"
elif [[ -n "$waybar_pid" ]]; then
  scope="pid-$waybar_pid"
else
  scope="pid-${PPID:-global}"
fi

[[ -n "$scope" ]] || scope="global"
STATE_FILE="${STATE_DIR}/waybar-clock-mode.${scope}"

read_mode() {
  local mode="time"

  if [[ -f "$STATE_FILE" ]]; then
    mode="$(cat "$STATE_FILE" 2>/dev/null || printf 'time')"
  fi

  case "$mode" in
    time|date) printf '%s\n' "$mode" ;;
    *) printf 'time\n' ;;
  esac
}

write_mode() {
  printf '%s\n' "$1" > "$STATE_FILE"
}

signal_this_waybar() {
  if [[ -n "$waybar_pid" ]]; then
    kill "-RTMIN+${SIGNAL}" "$waybar_pid" 2>/dev/null || true
  elif [[ "${WAYBAR_CLOCK_SIGNAL_ALL:-0}" == "1" ]]; then
    pkill "-RTMIN+${SIGNAL}" waybar 2>/dev/null || true
  fi
}

if [[ "${1:-}" == "toggle" ]]; then
  current="$(read_mode)"

  if [[ "$current" == "time" ]]; then
    write_mode "date"
  else
    write_mode "time"
  fi

  signal_this_waybar
  exit 0
fi

mode="$(read_mode)"
now_24="$(date +'%H:%M')"
now_12="$(date +'%I:%M %p')"
full_date="$(date +'%A, %d, %Y')"

if [[ "$mode" == "time" ]]; then
  printf '{"text":" %s","tooltip":"%s\\n24h: %s\\n12h: %s","class":["time"]}\n' \
    "$now_24" "$full_date" "$now_24" "$now_12"
else
  md="$(date +'%m-%d')"
  printf '{"text":" %s","tooltip":"%s\\n24h: %s\\n12h: %s","class":["date"]}\n' \
    "$md" "$full_date" "$now_24" "$now_12"
fi
