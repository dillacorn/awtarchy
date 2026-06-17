#!/usr/bin/env bash
# ~/.config/hypr/scripts/waybar_restore_resume.sh
#
# hypridle on-resume/unlock:
# - Restore Waybar only when the idle timeout marked it for restoration.
# - Serialize against the timeout stop script.
# - Require Waybar to remain alive before clearing the restore marker.

set -u -o pipefail

CONF="${XDG_CONFIG_HOME:-$HOME/.config}"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}"

SCRIPTS_DIR="${CONF}/hypr/scripts"
WAYBAR_SH="${WAYBAR_SH:-${SCRIPTS_DIR}/waybar.sh}"

uid="$(id -u)"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/${uid}}"
IDLE_MARKER="${IDLE_MARKER:-${RUNTIME_DIR}/waybar.idle_restore}"
TRANSITION_LOCK="${TRANSITION_LOCK:-${RUNTIME_DIR}/waybar.idle_transition.lock}"

PER_DIR="${PER_DIR:-${CACHE}/waybar/per-output}"
LOG_FILE="${LOG_FILE:-${CACHE}/waybar/restore_resume.log}"

mkdir -p "$RUNTIME_DIR" "$PER_DIR" "$(dirname "$LOG_FILE")" 2>/dev/null || true
[[ -x "$WAYBAR_SH" ]] || exit 0

if command -v flock >/dev/null 2>&1; then
  exec 9>"$TRANSITION_LOCK"
  flock -x 9
fi

log() {
  printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$LOG_FILE" 2>/dev/null || true
}

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

cleanup_stale_pidfiles() {
  local pidfile pid
  [[ -d "$PER_DIR" ]] || return 0
  shopt -s nullglob
  for pidfile in "$PER_DIR"/*.pid; do
    pid="$(tr -d ' \t\r\n' <"$pidfile" 2>/dev/null || true)"
    if ! pid_is_waybar "$pid"; then
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
    pid_is_waybar "$pid" && return 0
  done
  return 1
}

any_waybar_running() {
  any_managed_waybar_running && return 0
  pgrep -u "$uid" -x waybar >/dev/null 2>&1
}

waybar_running_stable() {
  any_waybar_running || return 1
  sleep 0.35
  cleanup_stale_pidfiles
  any_waybar_running
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
wait_for_hypr_ready || log "Hyprland monitors were not ready before restore attempts"

if waybar_running_stable; then
  rm -f "$IDLE_MARKER" 2>/dev/null || true
  log "Waybar was already running and stable on resume"
  exit 0
fi

attempt=1
while (( attempt <= 10 )); do
  log "Waybar restore attempt ${attempt}"
  "$WAYBAR_SH" start 9>&- >>"$LOG_FILE" 2>&1 || true

  settle=0
  while (( settle < 16 )); do
    cleanup_stale_pidfiles
    if waybar_running_stable; then
      rm -f "$IDLE_MARKER" 2>/dev/null || true
      log "Waybar restore succeeded on attempt ${attempt}"
      exit 0
    fi
    sleep 0.25
    ((settle++))
  done

  ((attempt++))
done

log "Waybar restore failed; marker kept for next resume/unlock retry"
exit 0
