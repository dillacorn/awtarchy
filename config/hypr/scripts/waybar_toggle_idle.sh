#!/usr/bin/env bash
# ~/.config/hypr/scripts/waybar_toggle_idle.sh
#
# hypridle on-timeout:
# - Refuse to stop Waybar while the global idle inhibitor is active.
# - Serialize stop/restore transitions to prevent timeout/resume races.
# - Preserve the restore marker across duplicate timeout invocations.

set -euo pipefail

CONF="${XDG_CONFIG_HOME:-$HOME/.config}"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}"

SCRIPTS_DIR="${CONF}/hypr/scripts"
WAYBAR_SH="${WAYBAR_SH:-${SCRIPTS_DIR}/waybar.sh}"
INHIBITOR_SH="${INHIBITOR_SH:-${CONF}/waybar/scripts/idle_inhibitor_global.sh}"

uid="$(id -u)"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/${uid}}"
IDLE_MARKER="${IDLE_MARKER:-${RUNTIME_DIR}/waybar.idle_restore}"
TRANSITION_LOCK="${TRANSITION_LOCK:-${RUNTIME_DIR}/waybar.idle_transition.lock}"

PER_DIR="${PER_DIR:-${CACHE}/waybar/per-output}"

[[ -x "$WAYBAR_SH" ]] || exit 0
mkdir -p "$RUNTIME_DIR" "$PER_DIR" 2>/dev/null || true

if command -v flock >/dev/null 2>&1; then
  exec 9>"$TRANSITION_LOCK"
  flock -x 9
fi

# Hypridle should honor this itself, but this guard prevents Waybar loss if
# Hypridle misfires, has stale state, or more than one daemon is running.
if [[ -x "$INHIBITOR_SH" ]] && "$INHIBITOR_SH" is-active >/dev/null 2>&1; then
  exit 0
fi

pid_alive() {
  [[ "${1:-}" =~ ^[0-9]+$ ]] && kill -0 "$1" 2>/dev/null
}

pid_comm() {
  tr -d '\n' </proc/"$1"/comm 2>/dev/null || true
}

pid_is_waybar() {
  local pid="${1:-}"
  pid_alive "$pid" && [[ "$(pid_comm "$pid")" == "waybar" ]]
}

cleanup_pidfiles() {
  local pidfile pid
  shopt -s nullglob
  for pidfile in "$PER_DIR"/*.pid; do
    pid="$(tr -d ' \t\r\n' <"$pidfile" 2>/dev/null || true)"
    if ! pid_is_waybar "$pid"; then
      rm -f "$pidfile" 2>/dev/null || true
    fi
  done
}

waybar_pids() {
  local pidfile pid
  declare -A seen=()

  shopt -s nullglob
  for pidfile in "$PER_DIR"/*.pid; do
    pid="$(tr -d ' \t\r\n' <"$pidfile" 2>/dev/null || true)"
    if pid_is_waybar "$pid" && [[ -z "${seen[$pid]:-}" ]]; then
      seen["$pid"]=1
      printf '%s\n' "$pid"
    fi
  done

  while read -r pid; do
    if pid_is_waybar "$pid" && [[ -z "${seen[$pid]:-}" ]]; then
      seen["$pid"]=1
      printf '%s\n' "$pid"
    fi
  done < <(pgrep -u "$uid" -x waybar 2>/dev/null || true)
}

terminate_waybars() {
  local pid
  local -a pids=("$@")

  for pid in "${pids[@]}"; do
    pid_is_waybar "$pid" && kill "$pid" 2>/dev/null || true
  done

  for _ in {1..20}; do
    local any_alive=0
    for pid in "${pids[@]}"; do
      if pid_is_waybar "$pid"; then
        any_alive=1
        break
      fi
    done
    (( any_alive == 0 )) && return 0
    sleep 0.05
  done

  for pid in "${pids[@]}"; do
    pid_is_waybar "$pid" && kill -9 "$pid" 2>/dev/null || true
  done
}

cleanup_pidfiles
mapfile -t pids < <(waybar_pids)

# Duplicate timeout calls must not erase an existing restore request.
(( ${#pids[@]} > 0 )) || exit 0

marker_tmp="${IDLE_MARKER}.tmp.$$"
printf 'running\n' >"$marker_tmp"
mv -f "$marker_tmp" "$IDLE_MARKER"

"$WAYBAR_SH" stop >/dev/null 2>&1 || true
terminate_waybars "${pids[@]}"
cleanup_pidfiles
