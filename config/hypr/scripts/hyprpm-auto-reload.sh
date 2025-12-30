#!/usr/bin/env bash
# ~/.config/hypr/scripts/hyprpm-auto-reload.sh
#
# Behavior:
# - If hyprpm missing: exit 0
# - Try: hyprpm reload
# - If reload fails: hyprpm update (wait) -> hyprpm reload
# - Rate-limit repeated update attempts with a TTL lock
# - Log to: ~/.cache/hyprpm-auto/hyprpm-auto-reload.log

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

mkdir -p "$LOG_DIR" 2>/dev/null || true

ts() { date +"%Y-%m-%d %H:%M:%S"; }

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

# If hyprpm is not installed, do nothing.
[[ -n "$HYPRPM" ]] || exit 0

# Avoid hammering update/reload repeatedly if something is broken.
if have_recent_lock; then
  exit 0
fi

# 1) Try reload
reload_out="$("$HYPRPM" reload 2>&1)"
reload_rc=$?
log_block "hyprpm reload" "$reload_rc" "$reload_out"

if [[ "$reload_rc" -eq 0 ]]; then
  exit 0
fi

# 2) Reload failed, try update then reload
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
