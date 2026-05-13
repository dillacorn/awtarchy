#!/usr/bin/env bash
# ~/.config/hypr/scripts/hyprpm-auto-reload.sh
#
# Safe default for Hyprland Lua/plugin migration:
# - Does NOT run hyprpm reload by default.
# - Live hyprpm reload can hot-unload/reload compositor plugins and may crash Hyprland.
# - To intentionally allow the old behavior, set:
#     HYPRPM_AUTO_LIVE_RELOAD=1
#
# Log: ~/.cache/hyprpm-auto/hyprpm-auto-reload.log

set -u
set -o pipefail

HYPRPM="$(command -v hyprpm || true)"
HYPRCTL="$(command -v hyprctl || true)"

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}"
LOG_DIR="$CACHE_DIR/hyprpm-auto"
LOG_FILE="$LOG_DIR/hyprpm-auto-reload.log"

LOCK_TTL_SECONDS="${HYPRPM_AUTO_LOCK_TTL_SECONDS:-600}"
LOCK_FILE="/tmp/hyprpm-auto-reload.lock"

RELOAD_TIMEOUT_SECONDS="${HYPRPM_RELOAD_TIMEOUT_SECONDS:-20}"
UPDATE_TIMEOUT_SECONDS="${HYPRPM_UPDATE_TIMEOUT_SECONDS:-600}"
LIVE_RELOAD="${HYPRPM_AUTO_LIVE_RELOAD:-0}"
UPDATE_ON_FAILURE="${HYPRPM_AUTO_UPDATE_ON_FAILURE:-1}"

mkdir -p "$LOG_DIR" 2>/dev/null || true

ts() { date +"%Y-%m-%d %H:%M:%S"; }

log_line() {
  printf '[%s] %s\n' "$(ts)" "$*" >>"$LOG_FILE"
}

notify() {
  local msg="$1"
  [[ -n "$HYPRCTL" ]] || return 0
  "$HYPRCTL" notify -1 9000 "rgb(ffcc00)" "$msg" >/dev/null 2>&1 || true
}

have_recent_lock() {
  [[ -f "$LOCK_FILE" ]] || return 1
  local now lock_ts age
  now="$(date +%s)"
  lock_ts="$(cat "$LOCK_FILE" 2>/dev/null || echo 0)"
  age=$(( now - lock_ts ))
  (( age >= 0 && age < LOCK_TTL_SECONDS ))
}

touch_lock() {
  date +%s >"$LOCK_FILE" 2>/dev/null || true
}

run_maybe_timeout() {
  local secs="$1"; shift
  if command -v timeout >/dev/null 2>&1; then
    timeout --preserve-status -k 5 "${secs}s" "$@"
  else
    "$@"
  fi
}

log_block() {
  local label="$1" rc="$2" out="$3"
  {
    echo "[$(ts)] $label (rc=$rc)"
    [[ -n "$out" ]] && echo "$out"
    echo
  } >>"$LOG_FILE"
}

[[ -n "$HYPRPM" ]] || exit 0

if have_recent_lock; then
  exit 0
fi

if [[ "$LIVE_RELOAD" != "1" ]]; then
  log_line "Skipped hyprpm reload. Set HYPRPM_AUTO_LIVE_RELOAD=1 to allow live plugin reload."
  exit 0
fi

log_line "HYPRPM_AUTO_LIVE_RELOAD=1 set. Running live hyprpm reload."

reload_out="$(run_maybe_timeout "$RELOAD_TIMEOUT_SECONDS" "$HYPRPM" reload 2>&1)"
reload_rc=$?
log_block "hyprpm reload" "$reload_rc" "$reload_out"

if [[ "$reload_rc" -eq 0 ]]; then
  exit 0
fi

if [[ "$UPDATE_ON_FAILURE" != "1" ]]; then
  notify "hyprpm reload failed. Auto update disabled. See log: $LOG_FILE"
  exit 0
fi

touch_lock
notify "hyprpm reload failed. Running hyprpm update, then reload."

update_out="$(run_maybe_timeout "$UPDATE_TIMEOUT_SECONDS" "$HYPRPM" update 2>&1)"
update_rc=$?
log_block "hyprpm update" "$update_rc" "$update_out"

if [[ "$update_rc" -ne 0 ]]; then
  notify "hyprpm update failed. See log: $LOG_FILE"
  exit 0
fi

reload2_out="$(run_maybe_timeout "$RELOAD_TIMEOUT_SECONDS" "$HYPRPM" reload 2>&1)"
reload2_rc=$?
log_block "hyprpm reload after update" "$reload2_rc" "$reload2_out"

if [[ "$reload2_rc" -ne 0 ]]; then
  notify "hyprpm reload still failing after update. See log: $LOG_FILE"
  exit 0
fi

notify "hyprpm updated and reloaded."
exit 0
