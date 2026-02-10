#!/usr/bin/env bash
# ~/.config/hypr/scripts/waybar_toggle_idle.sh
#
# hypridle on-timeout:
# - If managed waybar is running, stop it and write an idle marker
# - If not running, do nothing and clear marker

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
proc_comm() { tr -d '\n' </proc/"$1"/comm 2>/dev/null || true; }

# Only kill if PID is waybar AND it was launched with our per-output config (-c <cfg>)
pid_is_our_waybar() {
  local pid="$1" cfg="$2"
  pid_alive "$pid" || return 1
  [[ "$(proc_comm "$pid")" == "waybar" ]] || return 1
  tr '\0' ' ' </proc/"$pid"/cmdline 2>/dev/null | grep -Fq -- " -c $cfg " || return 1
  return 0
}

manager_running() {
  [[ "$("$WAYBAR_SH" status 2>/dev/null || true)" == "running" ]]
}

hard_stop_managed_waybar() {
  local pidfile pid cfg
  [[ -d "$PER_DIR" ]] || return 0

  shopt -s nullglob
  for pidfile in "$PER_DIR"/*.pid; do
    pid="$(tr -d ' \t\r\n' <"$pidfile" 2>/dev/null || true)"
    cfg="${pidfile%.pid}.json"

    if [[ -n "$pid" ]] && [[ -f "$cfg" ]] && pid_is_our_waybar "$pid" "$cfg"; then
      kill "$pid" 2>/dev/null || true
      sleep 0.05
      pid_alive "$pid" && kill -9 "$pid" 2>/dev/null || true
    fi

    rm -f "$pidfile" 2>/dev/null || true
  done
}

if manager_running; then
  printf 'running\n' >"$IDLE_MARKER"
  "$WAYBAR_SH" stop || true
  hard_stop_managed_waybar
else
  rm -f "$IDLE_MARKER" 2>/dev/null || true
fi
