#!/usr/bin/env bash
# FILE: ~/.config/hypr/scripts/cliphist-fuzzel.sh
#
# cliphist + fuzzel with image THUMBNAILS AS ICONS (not inline previews).
# No directory creation. Writes only files directly into $XDG_RUNTIME_DIR.
#
# Requires: cliphist, fuzzel, wl-copy, sha1sum, timeout, awk, sed, grep, head, pgrep, flock
# Optional: imagemagick ("magick") for thumbnail generation.

set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# EASY MODIFIERS
# ──────────────────────────────────────────────────────────────────────────────

PROMPT="${PROMPT:-Clipboard}"
LIST_LIMIT="${LIST_LIMIT:-60}"

# Bigger icon source image
THUMB_SIZE="${THUMB_SIZE:-512}"          # 256/320/384/512
THUMB_LIMIT="${THUMB_LIMIT:-30}"
DECODE_TIMEOUT="${DECODE_TIMEOUT:-0.70s}"

# Make the fuzzel window wider/taller in a controlled way
FUZZEL_WIDTH_CHARS="${FUZZEL_WIDTH_CHARS:-110}"     # width in characters
FUZZEL_LINES="${FUZZEL_LINES:-6}"                   # height in rows
FUZZEL_LINE_HEIGHT="${FUZZEL_LINE_HEIGHT:-128px}"   # bigger rows = bigger icons

# Hide match counter (without touching your real config)
SHOW_MATCH_COUNTER="${SHOW_MATCH_COUNTER:-0}"       # 0=hide, 1=show
USER_FUZZEL_CFG="${USER_FUZZEL_CFG:-${XDG_CONFIG_HOME:-$HOME/.config}/fuzzel/fuzzel.ini}"

# Waybar-aware anchoring (uses per-monitor waybar.sh state if available)
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
SCRIPTS_DIR="${SCRIPTS_DIR:-$CONF_DIR/hypr/scripts}"
WAYBAR_SH="${WAYBAR_SH:-$SCRIPTS_DIR/waybar.sh}"

# toggle  = if already open (script-launched), close and exit; else open
# reopen  = if already open, close then open again
# off     = never close existing; always open
TOGGLE_MODE="${TOGGLE_MODE:-toggle}"

DEBUG="${DEBUG:-0}"

# ──────────────────────────────────────────────────────────────────────────────

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing dependency: $1" >&2; exit 1; }; }
log() { [[ "$DEBUG" == "1" ]] && printf '[cliphist-fuzzel] %s\n' "$*" >&2 || true; }

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
  [[ -x "$WAYBAR_SH" ]] || return 1
  [[ "$("$WAYBAR_SH" getenabled-focused 2>/dev/null || true)" == "true" ]]
}

bar_pos_focused() {
  [[ -x "$WAYBAR_SH" ]] || return 1
  "$WAYBAR_SH" getpos-focused 2>/dev/null
}

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

CACHE_FILE="${CACHE_FILE:-$RUNTIME_BASE/cliphist-fuzzel.fuzzel.cache}"
THUMB_PREFIX="${THUMB_PREFIX:-$RUNTIME_BASE/cliphist-fuzzel.thumb.}"
LOCK_PREFIX="${LOCK_PREFIX:-$RUNTIME_BASE/cliphist-fuzzel.lock.}"
OVERRIDE_CFG_PATH="${OVERRIDE_CFG_PATH:-$RUNTIME_BASE/cliphist-fuzzel.override.ini}"

HELP="$(fuzzel --help 2>&1 || true)"
supports() { grep -q -- "$1" <<<"$HELP"; }

SUP_INDEX=0
SUP_NOSORT=0
SUP_NORUNEMPTY=0
SUP_CACHE=0
SUP_WIDTH=0
SUP_LINES=0
SUP_LINEHEIGHT=0
SUP_CONFIG=0
SUP_COUNTER=0

supports '--index' && SUP_INDEX=1
supports '--no-sort' && SUP_NOSORT=1
supports '--no-run-if-empty' && SUP_NORUNEMPTY=1
supports '--cache' && SUP_CACHE=1
supports '--width' && SUP_WIDTH=1
supports '--lines' && SUP_LINES=1
supports '--line-height' && SUP_LINEHEIGHT=1
supports '--config' && SUP_CONFIG=1
supports '--counter' && SUP_COUNTER=1

log "fuzzel flags: index=$SUP_INDEX no-sort=$SUP_NOSORT no-run-if-empty=$SUP_NORUNEMPTY cache=$SUP_CACHE width=$SUP_WIDTH lines=$SUP_LINES line-height=$SUP_LINEHEIGHT config=$SUP_CONFIG counter=$SUP_COUNTER"
log "toggle_mode=$TOGGLE_MODE cache_file=$CACHE_FILE override_cfg=$OVERRIDE_CFG_PATH"

strip_id_line() {
  # cliphist lines are like:
  #   <id>\t<content>
  # preserve the content but remove leading "<id>\t"
  sed -E 's/^[0-9]+\t//'
}

is_binary_row() {
  # heuristic: if it contains "[image]" or "[binary]" (cliphist formats vary by version)
  grep -qiE '(\[image\]|\[binary\])'
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

toggle_close_existing() {
  [[ "$TOGGLE_MODE" == "off" ]] && return 0

  local out pids
  out="$(pgrep -u "$UID" -x fuzzel -a 2>/dev/null || true)"
  pids="$(awk -v c="--cache=${CACHE_FILE}" 'index($0,c){print $1}' <<<"$out")"

  [[ -n "${pids:-}" ]] || return 0

  log "closing existing fuzzel instance(s): $pids"
  # shellcheck disable=SC2086
  kill $pids 2>/dev/null || true

  if [[ "$TOGGLE_MODE" == "toggle" ]]; then
    exit 0
  fi

  sleep 0.06
}

mapfile -t RAW < <(cliphist list 2>/dev/null | head -n "$LIST_LIMIT" || true)
((${#RAW[@]} > 0)) || { log "cliphist list empty"; exit 0; }

# Toggle before launching.
toggle_close_existing

menu_stream_for_index() {
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

FUZZEL_ARGS=(--dmenu --prompt "$PROMPT")
(( SUP_NORUNEMPTY == 1 )) && FUZZEL_ARGS+=(--no-run-if-empty)
(( SUP_NOSORT == 1 )) && FUZZEL_ARGS+=(--no-sort)
(( SUP_CACHE == 1 )) && FUZZEL_ARGS+=(--cache="$CACHE_FILE")
(( SUP_WIDTH == 1 )) && FUZZEL_ARGS+=(--width="$FUZZEL_WIDTH_CHARS")
(( SUP_LINES == 1 )) && FUZZEL_ARGS+=(--lines="$FUZZEL_LINES")
(( SUP_LINEHEIGHT == 1 )) && FUZZEL_ARGS+=(--line-height="$FUZZEL_LINE_HEIGHT")

# Anchor override: only when user has active anchor= in fuzzel.ini AND waybar is enabled on focused monitor.
ANCHOR_OVERRIDE=""
if user_anchor_opt_in && waybar_enabled_focused; then
  pos="$(bar_pos_focused 2>/dev/null || true)"
  case "$pos" in top|bottom|left|right) ANCHOR_OVERRIDE="$pos" ;; esac
fi
log "anchor_override=${ANCHOR_OVERRIDE:-<none>}"

if (( SUP_CONFIG == 1 )); then
  {
    echo "[main]"
    [[ -f "$USER_FUZZEL_CFG" ]] && echo "include=$USER_FUZZEL_CFG"
    if [[ "$SHOW_MATCH_COUNTER" == "1" ]]; then
      echo "match-counter=yes"
    else
      echo "match-counter=no"
    fi
    [[ -n "$ANCHOR_OVERRIDE" ]] && echo "anchor=$ANCHOR_OVERRIDE"
  } > "$OVERRIDE_CFG_PATH"
  FUZZEL_ARGS+=(--config="$OVERRIDE_CFG_PATH")
else
  if [[ "$SHOW_MATCH_COUNTER" == "1" ]]; then
    (( SUP_COUNTER == 1 )) && FUZZEL_ARGS+=(--counter)
  fi
fi

if (( SUP_INDEX == 1 )); then
  set +e
  IDX="$(menu_stream_for_index | fuzzel "${FUZZEL_ARGS[@]}" --index)"
  rc=$?
  set -e

  log "fuzzel rc=$rc idx='${IDX:-}'"
  [[ $rc -ne 0 ]] && exit 0
  [[ "${IDX:-}" =~ ^[0-9]+$ ]] || exit 0
  (( IDX >= 0 && IDX < ${#RAW[@]} )) || exit 0

  cliphist decode <<<"${RAW[$IDX]}" | wl-copy -n
  exit 0
fi

set +e
CHOICE="$(printf '%s\n' "${RAW[@]}" | fuzzel "${FUZZEL_ARGS[@]}")"
rc=$?
set -e

log "fuzzel rc=$rc choice_len=${#CHOICE}"
[[ $rc -ne 0 ]] && exit 0
[[ -z "${CHOICE:-}" ]] && exit 0

cliphist decode <<<"$CHOICE" | wl-copy -n
