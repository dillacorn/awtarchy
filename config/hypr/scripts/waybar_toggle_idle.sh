#!/usr/bin/env bash
# ~/.config/hypr/scripts/waybar_toggle_idle.sh
#
# Called by hypridle on-timeout:
# - If ANY managed waybar instance is running, stop ALL of them and write an idle marker.
# - If none are running, do nothing and clear the marker (prevents unwanted restore).

set -euo pipefail

CONF="${XDG_CONFIG_HOME:-$HOME/.config}"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}"

SCRIPTS_DIR="${CONF}/hypr/scripts"
WAYBAR_SH="${WAYBAR_SH:-${SCRIPTS_DIR}/waybar.sh}"

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
IDLE_MARKER="${IDLE_MARKER:-${RUNTIME_DIR}/waybar.idle_restore}"

PER_DIR="${PER_DIR:-${CACHE}/waybar/per-output}"

[[ -x "$WAYBAR_SH" ]] || { printf 'waybar_toggle_idle: missing executable: %s\n' "$WAYBAR_SH" >&2; exit 1; }

pid_alive() { [[ -n "${1:-}" ]] && kill -0 "$1" 2>/dev/null; }

any_managed_waybar_running() {
  local pidfile pid
  [[ -d "$PER_DIR" ]] || return 1

  shopt -s nullglob
  for pidfile in "$PER_DIR"/*.pid; do
    pid="$(tr -d ' \t\r\n' <"$pidfile" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && pid_alive "$pid"; then
      return 0
    fi
  done
  return 1
}

hard_stop_managed_waybar() {
  local pidfile pid
  [[ -d "$PER_DIR" ]] || return 0

  shopt -s nullglob
  for pidfile in "$PER_DIR"/*.pid; do
    pid="$(tr -d ' \t\r\n' <"$pidfile" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && pid_alive "$pid"; then
      kill "$pid" 2>/dev/null || true
      sleep 0.05
      pid_alive "$pid" && kill -9 "$pid" 2>/dev/null || true
    fi
    rm -f "$pidfile" 2>/dev/null || true
  done
}

if any_managed_waybar_running; then
  printf 'running\n' >"$IDLE_MARKER"

  # Stop via manager first (cleans state for visible monitors)
  "$WAYBAR_SH" stop || true

  # Then hard-stop anything left over (covers sleep/output enumeration weirdness)
  hard_stop_managed_waybar

else
  rm -f "$IDLE_MARKER" 2>/dev/null || true
fi
