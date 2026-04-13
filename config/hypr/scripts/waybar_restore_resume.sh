#!/usr/bin/env bash
# ~/.config/hypr/scripts/waybar_restore_resume.sh
#
# hypridle on-resume/unlock:
# - If marker says "running", restore Waybar.
# - Otherwise do nothing.
#
# More tolerant on resume:
# - waits for Hyprland monitors to come back
# - treats either managed pidfiles OR a live waybar process as success
# - cleans stale pidfiles
# - retries over a longer window
# - logs failures for debugging

set -u -o pipefail

CONF="${XDG_CONFIG_HOME:-$HOME/.config}"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}"

SCRIPTS_DIR="${CONF}/hypr/scripts"
WAYBAR_SH="${WAYBAR_SH:-${SCRIPTS_DIR}/waybar.sh}"

uid="$(id -u)"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/${uid}}"
IDLE_MARKER="${IDLE_MARKER:-${RUNTIME_DIR}/waybar.idle_restore}"

PER_DIR="${PER_DIR:-${CACHE}/waybar/per-output}"
LOG_FILE="${LOG_FILE:-${CACHE}/waybar/restore_resume.log}"

mkdir -p "$RUNTIME_DIR" "$PER_DIR" "$(dirname "$LOG_FILE")" 2>/dev/null || true
[[ -x "$WAYBAR_SH" ]] || exit 0

log() {
  printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$LOG_FILE" 2>/dev/null || true
}

pid_alive() {
  [[ -n "${1:-}" ]] && [[ "$1" =~ ^[0-9]+$ ]] && kill -0 "$1" 2>/dev/null
}

cleanup_stale_pidfiles() {
  local pidfile pid
  [[ -d "$PER_DIR" ]] || return 0
  shopt -s nullglob
  for pidfile in "$PER_DIR"/*.pid; do
    pid="$(tr -d ' \t\r\n' <"$pidfile" 2>/dev/null || true)"
    if ! pid_alive "$pid"; then
      rm -f "$pidfile" 2>/dev/null || true
    fi
  done
}

any_managed_waybar_running() {
  local pidfile pid
  [[ -d "$PER_DIR" ]] || return 1
  shopt -s nullglob
  for pidfile in "$PER_DIR"/*.pid; do
    pid="$(tr -d ' \t\r\n' <"$pidfile" 2>/dev/null || true)"
    pid_alive "$pid" && return 0
  done
  return 1
}

any_waybar_running() {
  any_managed_waybar_running && return 0
  pgrep -u "$uid" -x waybar >/dev/null 2>&1
}

wait_for_hypr_ready() {
  local tries monitors
  command -v hyprctl >/dev/null 2>&1 || return 0

  tries=0
  while (( tries < 40 )); do
    monitors="$(hyprctl monitors -j 2>/dev/null || true)"
    [[ -n "$monitors" && "$monitors" != "[]" ]] && return 0
    sleep 0.25
    ((tries++))
  done

  return 1
}

marker="$(tr -d ' \t\r\n' <"$IDLE_MARKER" 2>/dev/null || true)"
[[ "$marker" == "running" ]] || exit 0

cleanup_stale_pidfiles

if any_waybar_running; then
  rm -f "$IDLE_MARKER" 2>/dev/null || true
  exit 0
fi

wait_for_hypr_ready || log "Hyprland monitors were not ready before restore attempts"

attempt=1
while (( attempt <= 10 )); do
  if any_waybar_running; then
    rm -f "$IDLE_MARKER" 2>/dev/null || true
    log "Waybar restore succeeded before attempt ${attempt}"
    exit 0
  fi

  log "Waybar restore attempt ${attempt}"
  "$WAYBAR_SH" start >>"$LOG_FILE" 2>&1 || true

  settle=0
  while (( settle < 8 )); do
    cleanup_stale_pidfiles
    if any_waybar_running; then
      rm -f "$IDLE_MARKER" 2>/dev/null || true
      log "Waybar restore succeeded on attempt ${attempt}"
      exit 0
    fi
    sleep 0.25
    ((settle++))
  done

  ((attempt++))
done

log "Waybar restore failed; marker kept for next retry"
exit 0
