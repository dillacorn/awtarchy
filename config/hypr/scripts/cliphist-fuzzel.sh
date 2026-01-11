#!/usr/bin/env bash
# FILE: ~/.config/hypr/scripts/cliphist-fuzzel.sh
#
# cliphist + fuzzel with image THUMBNAILS AS ICONS (not inline previews).
# Uses your existing fuzzel.ini as the base, then applies THIS script's overrides via a runtime config.
# Toggle: run again while open -> closes the clipboard fuzzel instance.
#
# Requires: cliphist, fuzzel, wl-copy, sha1sum, timeout, awk, sed, grep, head, pgrep, flock
# Optional: imagemagick ("magick") for thumbnail generation.

set -euo pipefail
exec </dev/null

# ──────────────────────────────────────────────────────────────────────────────
# EASY MODIFIERS (kept)
# ──────────────────────────────────────────────────────────────────────────────

PROMPT="${PROMPT:-Clipboard}"
LIST_LIMIT="${LIST_LIMIT:-60}"

# Bigger icon source image
THUMB_SIZE="${THUMB_SIZE:-512}"          # 256/320/384/512
THUMB_LIMIT="${THUMB_LIMIT:-30}"
DECODE_TIMEOUT="${DECODE_TIMEOUT:-0.70s}"

# Make the fuzzel window wider/taller in a controlled way (applied via runtime config)
FUZZEL_WIDTH_CHARS="${FUZZEL_WIDTH_CHARS:-110}"     # width in characters
FUZZEL_LINES="${FUZZEL_LINES:-6}"                   # height in rows
FUZZEL_LINE_HEIGHT="${FUZZEL_LINE_HEIGHT:-128px}"   # bigger rows = bigger icons

# Hide match counter
SHOW_MATCH_COUNTER="${SHOW_MATCH_COUNTER:-0}"       # 0=hide, 1=show

# Base config
USER_FUZZEL_CFG="${USER_FUZZEL_CFG:-${XDG_CONFIG_HOME:-$HOME/.config}/fuzzel/fuzzel.ini}"

# Waybar-aware anchoring (mirrors fuzzel_toggle.sh behavior)
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
SCRIPTS_DIR="${SCRIPTS_DIR:-$CONF_DIR/hypr/scripts}"
WAYBAR_SH="${WAYBAR_SH:-$SCRIPTS_DIR/waybar.sh}"

# toggle  = if already open (script-launched), close and exit; else open
# reopen  = if already open, close then open again
# off     = never close; always attempt open
TOGGLE_MODE="${TOGGLE_MODE:-toggle}"

# If any other fuzzel is open (launcher, etc), kill it so clipboard menu can open.
KILL_OTHER_FUZZEL="${KILL_OTHER_FUZZEL:-1}"   # 1=yes, 0=no

DEBUG="${DEBUG:-0}"

# ──────────────────────────────────────────────────────────────────────────────

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing dependency: $1" >&2; exit 1; }; }
log() { [[ "$DEBUG" == "1" ]] && printf '[cliphist-fuzzel] %s\n' "$*" >&2 || true; }

need cliphist
need fuzzel
need wl-copy
need sha1sum
need timeout
need awk
need sed
need grep
need head
need pgrep
need flock

RUNTIME_BASE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
if [[ ! -d "$RUNTIME_BASE" ]]; then
  echo "XDG_RUNTIME_DIR missing/not a directory: $RUNTIME_BASE" >&2
  exit 1
fi

RUNTIME_CFG="${RUNTIME_CFG:-$RUNTIME_BASE/cliphist-fuzzel.runtime.ini}"
CACHE_FILE="${CACHE_FILE:-$RUNTIME_BASE/cliphist-fuzzel.fuzzel.cache}"
THUMB_PREFIX="${THUMB_PREFIX:-$RUNTIME_BASE/cliphist-fuzzel.thumb.}"
LOCK_PREFIX="${LOCK_PREFIX:-$RUNTIME_BASE/cliphist-fuzzel.lock.}"
SCRIPT_LOCK="${SCRIPT_LOCK:-$RUNTIME_BASE/cliphist-fuzzel.script.lock}"

strip_id_line() {
  sed -E 's/^[0-9]+\t//'
}

is_binary_row() {
  local s="${1:-}"
  grep -qiE '(\[image\]|\[binary\])' <<<"$s"
}

make_thumb_png() {
  local raw="$1" tmp lock key png

  command -v magick >/dev/null 2>&1 || return 1

  key="$(printf '%s' "$raw" | sha1sum | awk '{print $1}')"
  png="${THUMB_PREFIX}${key}.png"
  lock="${LOCK_PREFIX}${key}.lock"

  [[ -f "$png" ]] && { printf '%s' "$png"; return 0; }

  exec 9>"$lock"
  flock -n 9 || { [[ -f "$png" ]] && { printf '%s' "$png"; return 0; }; return 1; }

  [[ -f "$png" ]] && { printf '%s' "$png"; return 0; }

  tmp="${RUNTIME_BASE}/cliphist-fuzzel.decode.${key}.tmp"
  rm -f -- "$tmp" 2>/dev/null || true

  if timeout "$DECODE_TIMEOUT" cliphist decode <<<"$raw" >"$tmp" 2>/dev/null; then
    if [[ -s "$tmp" ]]; then
      if magick "$tmp" -thumbnail "${THUMB_SIZE}x${THUMB_SIZE}>" "png:$png" >/dev/null 2>&1; then
        rm -f -- "$tmp" 2>/dev/null || true
        printf '%s' "$png"
        return 0
      fi
    fi
  fi

  rm -f -- "$tmp" 2>/dev/null || true
  return 1
}

user_anchor_opt_in() {
  local f="$USER_FUZZEL_CFG"
  [[ -f "$f" ]] || return 1
  awk '
    BEGIN{in_main=0}
    /^[[:space:]]*\[main\][[:space:]]*$/ {in_main=1; next}
    /^[[:space:]]*\[/ {in_main=0}
    in_main {
      if ($0 ~ /^[[:space:]]*[#;]/) next
      if ($0 ~ /^[[:space:]]*anchor[[:space:]]*=/) { found=1; exit }
    }
    END{ exit(found?0:1) }
  ' "$f"
}

waybar_enabled_focused() {
  # Prefer per-monitor signal if your waybar.sh provides it.
  if [[ -x "$WAYBAR_SH" ]]; then
    local v
    v="$("$WAYBAR_SH" getenabled-focused 2>/dev/null || true)"
    [[ "$v" == "true" ]] && return 0
    [[ "$v" == "false" ]] && return 1
  fi
  # Fallback: only override when waybar is actually running.
  pgrep -x waybar >/dev/null 2>&1
}

bar_pos_focused() {
  if [[ -x "$WAYBAR_SH" ]]; then
    "$WAYBAR_SH" getpos-focused 2>/dev/null || echo top
  else
    echo top
  fi
}

compute_anchor() {
  local pos="${1:-top}"
  case "$pos" in
    top|bottom|left|right) echo "$pos" ;;
    *) echo top ;;
  esac
}

kill_fuzzel_pids() {
  local pids="${1:-}"
  [[ -n "$pids" ]] || return 0

  log "killing fuzzel pid(s): $pids"
  # shellcheck disable=SC2086
  kill $pids 2>/dev/null || true

  local tries=0
  while pgrep -u "$UID" -x fuzzel >/dev/null 2>&1; do
    tries=$((tries + 1))
    [[ $tries -ge 12 ]] && break
    sleep 0.05
  done

  if pgrep -u "$UID" -x fuzzel >/dev/null 2>&1; then
    log "fuzzel still alive after TERM; sending KILL"
    # shellcheck disable=SC2086
    kill -9 $pids 2>/dev/null || true
    sleep 0.05
  fi

  # If no fuzzel is running, clean stale lock(s) so new instance can start.
  if ! pgrep -u "$UID" -x fuzzel >/dev/null 2>&1; then
    rm -f -- "$RUNTIME_BASE"/fuzzel-*.lock 2>/dev/null || true
  fi
}

ours_pids() {
  (pgrep -u "$UID" -x fuzzel -a 2>/dev/null || true) \
    | awk -v m="$RUNTIME_CFG" 'index($0,m){print $1}'
}

other_pids() {
  (pgrep -u "$UID" -x fuzzel -a 2>/dev/null || true) \
    | awk -v m="$RUNTIME_CFG" '!index($0,m){print $1}'
}

close_ours_and_maybe_exit() {
  local pids
  pids="$(ours_pids || true)"
  [[ -n "${pids:-}" ]] || return 1

  kill_fuzzel_pids "$pids"

  if [[ "$TOGGLE_MODE" == "toggle" ]]; then
    exit 0
  fi
  return 0
}

# Lock behavior that still allows "toggle to close":
# - If another instance is already running and holding the lock:
#     - toggle: close ours and exit
#     - reopen: close ours, wait briefly for lock to clear, then proceed
#     - off: exit
exec 8>"$SCRIPT_LOCK"
if ! flock -n 8; then
  if [[ "$TOGGLE_MODE" == "toggle" ]]; then
    close_ours_and_maybe_exit || exit 0
    exit 0
  fi

  if [[ "$TOGGLE_MODE" == "reopen" ]]; then
    close_ours_and_maybe_exit || true
    for _ in {1..80}; do
      flock -n 8 && break
      sleep 0.025
    done
    flock -n 8 || exit 0
  else
    exit 0
  fi
fi

# If ours is already open in this same instance, honor toggle/reopen immediately.
if close_ours_and_maybe_exit; then
  # reopen continues
  :
fi

# If opening, optionally kill other fuzzel instances first to avoid "invisible lock" situations.
if [[ "$KILL_OTHER_FUZZEL" == "1" ]]; then
  opids="$(other_pids || true)"
  [[ -n "${opids:-}" ]] && kill_fuzzel_pids "$opids"
fi

mapfile -t RAW < <(cliphist list 2>/dev/null | head -n "$LIST_LIMIT" || true)
((${#RAW[@]} > 0)) || exit 0

menu_stream() {
  local made=0 raw label icon
  for raw in "${RAW[@]}"; do
    label="$(printf '%s' "$raw" | strip_id_line)"
    if is_binary_row "$raw" && (( made < THUMB_LIMIT )); then
      if icon="$(make_thumb_png "$raw" 2>/dev/null)"; then
        printf '%s\0icon\x1f%s\n' "$label" "$icon"
        made=$((made + 1))
        continue
      fi
    fi
    printf '%s\n' "$label"
  done
}

ANCHOR_OVERRIDE=""
if waybar_enabled_focused && user_anchor_opt_in; then
  ANCHOR_OVERRIDE="$(compute_anchor "$(bar_pos_focused)")"
fi
log "anchor_override=${ANCHOR_OVERRIDE:-<none>}"

# Build runtime config:
# - Start with your fuzzel.ini content (so ALL your settings apply)
# - Append override [main] and [dmenu] sections at the end (so overrides win)
{
  if [[ -f "$USER_FUZZEL_CFG" ]]; then
    cat "$USER_FUZZEL_CFG"
    echo
  fi

  echo "[main]"
  echo "width=$FUZZEL_WIDTH_CHARS"
  echo "lines=$FUZZEL_LINES"
  echo "line-height=$FUZZEL_LINE_HEIGHT"
  if [[ "$SHOW_MATCH_COUNTER" == "1" ]]; then
    echo "match-counter=yes"
  else
    echo "match-counter=no"
  fi
  [[ -n "$ANCHOR_OVERRIDE" ]] && echo "anchor=$ANCHOR_OVERRIDE"
  echo

  echo "[dmenu]"
  echo "mode=index"
  echo "prompt=$PROMPT"
  echo "exit-immediately-if-empty=yes"
  echo "cache=$CACHE_FILE"
  echo "sort-result=no"
} > "$RUNTIME_CFG"

set +e
IDX="$(menu_stream | fuzzel --dmenu --config "$RUNTIME_CFG")"
rc=$?
set -e

[[ $rc -ne 0 ]] && exit 0
[[ "${IDX:-}" =~ ^[0-9]+$ ]] || exit 0
(( IDX >= 0 && IDX < ${#RAW[@]} )) || exit 0

cliphist decode <<<"${RAW[$IDX]}" | wl-copy -n
