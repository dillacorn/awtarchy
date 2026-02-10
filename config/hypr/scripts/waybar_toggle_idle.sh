#!/usr/bin/env bash
# ~/.config/hypr/scripts/waybar_toggle_idle.sh
#
# hypridle on-timeout:
# - If any managed Waybar is running: stop all and mark for restore.
# - If none are running: clear marker.

set -euo pipefail

CONF="${XDG_CONFIG_HOME:-$HOME/.config}"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}"

SCRIPTS_DIR="${CONF}/hypr/scripts"
WAYBAR_SH="${WAYBAR_SH:-${SCRIPTS_DIR}/waybar.sh}"

uid="$(id -u)"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/${uid}}"
IDLE_MARKER="${IDLE_MARKER:-${RUNTIME_DIR}/waybar.idle_restore}"

PER_DIR="${PER_DIR:-${CACHE}/waybar/per-output}"

[[ -x "$WAYBAR_SH" ]] || exit 0
mkdir -p "$RUNTIME_DIR" "$PER_DIR" 2>/dev/null || true

pid_alive() { [[ -n "${1:-}" ]] && kill -0 "$1" 2>/dev/null; }
pid_comm() { tr -d '\n' </proc/"$1"/comm 2>/dev/null || true; }

cleanup_pidfiles() {
  local pidfile pid
  shopt -s nullglob
  for pidfile in "$PER_DIR"/*.pid; do
    pid="$(tr -d ' \t\r\n' <"$pidfile" 2>/dev/null || true)"
    if [[ -z "$pid" ]] || ! [[ "$pid" =~ ^[0-9]+$ ]] || ! pid_alive "$pid" || [[ "$(pid_comm "$pid")" != "waybar" ]]; then
      rm -f "$pidfile" 2>/dev/null || true
    fi
  done
}

any_managed_waybar_running() {
  local pidfile pid
  shopt -s nullglob
  for pidfile in "$PER_DIR"/*.pid; do
    pid="$(tr -d ' \t\r\n' <"$pidfile" 2>/dev/null || true)"
    [[ -n "$pid" ]] && [[ "$pid" =~ ^[0-9]+$ ]] && pid_alive "$pid" && [[ "$(pid_comm "$pid")" == "waybar" ]] && return 0
  done
  return 1
}

hard_kill_managed_waybar() {
  local pidfile pid
  shopt -s nullglob
  for pidfile in "$PER_DIR"/*.pid; do
    pid="$(tr -d ' \t\r\n' <"$pidfile" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && [[ "$pid" =~ ^[0-9]+$ ]] && pid_alive "$pid" && [[ "$(pid_comm "$pid")" == "waybar" ]]; then
      kill "$pid" 2>/dev/null || true
      sleep 0.05
      pid_alive "$pid" && kill -9 "$pid" 2>/dev/null || true
    fi
    rm -f "$pidfile" 2>/dev/null || true
  done
}

cleanup_pidfiles

if any_managed_waybar_running; then
  printf 'running\n' >"$IDLE_MARKER"
  "$WAYBAR_SH" stop >/dev/null 2>&1 || true
  hard_kill_managed_waybar
else
  rm -f "$IDLE_MARKER" 2>/dev/null || true
fi
