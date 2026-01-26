#!/usr/bin/env bash
# ~/.config/hypr/scripts/waybar_restore_resume.sh
#
# Called by hypridle on-resume/unlock:
# - Only restores if idle previously stopped it (marker file says "running").
# - ALWAYS runs "start" (idempotent) so missing monitors get relaunched.
# - Retries because monitors frequently come back in stages after sleep.

set -euo pipefail

CONF="${XDG_CONFIG_HOME:-$HOME/.config}"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}"

SCRIPTS_DIR="${CONF}/hypr/scripts"
WAYBAR_SH="${WAYBAR_SH:-${SCRIPTS_DIR}/waybar.sh}"

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
IDLE_MARKER="${IDLE_MARKER:-${RUNTIME_DIR}/waybar.idle_restore}"

PER_DIR="${PER_DIR:-${CACHE}/waybar/per-output}"

[[ -x "$WAYBAR_SH" ]] || { printf 'waybar_restore_resume: missing executable: %s\n' "$WAYBAR_SH" >&2; exit 1; }

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

wait_for_monitors_stable() {
  # After sleep, Hyprland may report 1 monitor, then 2, then 3, etc.
  # This waits until the count stays stable for a short moment.
  local last="-1" stable="0" len

  for ((t=0; t<120; t++)); do
    len="$(hyprctl monitors -j 2>/dev/null | jq 'length' 2>/dev/null || echo 0)"

    if [[ "$len" -ge 1 ]]; then
      if [[ "$len" == "$last" ]]; then
        stable=$((stable + 1))
      else
        stable="0"
      fi
      last="$len"

      # ~0.5s stable
      if [[ "$stable" -ge 5 ]]; then
        return 0
      fi
    fi

    sleep 0.1
  done

  return 0
}

if [[ "$(cat "$IDLE_MARKER" 2>/dev/null || true)" == "running" ]]; then
  wait_for_monitors_stable

  # Start is safe to call repeatedly:
  # - already-running monitors are skipped by PID checks
  # - missing monitors get spawned
  "$WAYBAR_SH" start || true
  sleep 0.25
  "$WAYBAR_SH" start || true
  sleep 0.25
  "$WAYBAR_SH" start || true

  # Only clear the marker once we actually see managed waybar alive.
  if any_managed_waybar_running; then
    rm -f "$IDLE_MARKER" 2>/dev/null || true
  fi
fi
