#!/usr/bin/env bash
# ~/.config/hypr/scripts/waybar_restore_resume.sh
#
# hypridle on-resume/unlock:
# - If marker says "running", restore Waybar.
# - Otherwise do nothing.

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

any_managed_waybar_running() {
  local pidfile pid
  [[ -d "$PER_DIR" ]] || return 1
  shopt -s nullglob
  for pidfile in "$PER_DIR"/*.pid; do
    pid="$(tr -d ' \t\r\n' <"$pidfile" 2>/dev/null || true)"
    [[ -n "$pid" ]] && [[ "$pid" =~ ^[0-9]+$ ]] && pid_alive "$pid" && return 0
  done
  return 1
}

marker="$(cat "$IDLE_MARKER" 2>/dev/null || true)"
if [[ "$marker" == "running" ]]; then
  if any_managed_waybar_running; then
    rm -f "$IDLE_MARKER" 2>/dev/null || true
    exit 0
  fi

  "$WAYBAR_SH" start >/dev/null 2>&1 || true
  for _ in 1 2 3; do
    any_managed_waybar_running && break || true
    sleep 0.4
    "$WAYBAR_SH" start >/dev/null 2>&1 || true
  done

  any_managed_waybar_running && rm -f "$IDLE_MARKER" 2>/dev/null || true
fi
