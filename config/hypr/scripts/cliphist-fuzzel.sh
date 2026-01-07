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
FUZZEL_WIDTH_CHARS="${FUZZEL_WIDTH_CHARS:-110}" # fuzzel -w/--width is in characters :contentReference[oaicite:0]{index=0}
FUZZEL_LINES="${FUZZEL_LINES:-6}"               # fuzzel -l/--lines controls height :contentReference[oaicite:1]{index=1}
FUZZEL_LINE_HEIGHT="${FUZZEL_LINE_HEIGHT:-128px}" # bigger rows = bigger icons :contentReference[oaicite:2]{index=2}

# Hide the "60/60" match counter on the right (your config currently enables it)
SHOW_MATCH_COUNTER="${SHOW_MATCH_COUNTER:-0}"   # 0=hide, 1=show
# If we need to override match-counter without touching your real config, we use a tiny runtime config include.
USER_FUZZEL_CFG="${USER_FUZZEL_CFG:-${XDG_CONFIG_HOME:-$HOME/.config}/fuzzel/fuzzel.ini}"
OVERRIDE_CFG_PATH="${OVERRIDE_CFG_PATH:-}"

# toggle  = if already open, close and exit
# reopen  = if already open, close then open again
# off     = do not try to close existing instances
TOGGLE_MODE="${TOGGLE_MODE:-reopen}"

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

CACHE_FILE="${CACHE_FILE:-$RUNTIME_BASE/cliphist-fuzzel.fuzzel.cache}"
THUMB_PREFIX="${THUMB_PREFIX:-$RUNTIME_BASE/cliphist-fuzzel.thumb.}"
LOCK_PREFIX="${LOCK_PREFIX:-$RUNTIME_BASE/cliphist-fuzzel.lock.}"

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
log "toggle_mode=$TOGGLE_MODE cache_file=$CACHE_FILE"

strip_id_line() { sed -E 's/^[[:space:]]*[0-9]+\t//'; }
is_binary_row() { grep -Eiq '\[\[\s*binary' <<<"$1"; }
sha1_of() { printf '%s' "$1" | sha1sum | awk '{print $1}'; }

toggle_close_existing() {
  [[ "$TOGGLE_MODE" != "off" ]] || return 0
  (( SUP_CACHE == 1 )) || return 0

  local pids
  pids="$(pgrep -u "$USER" -af "fuzzel" | awk -v c="--cache=${CACHE_FILE}" 'index($0,c){print $1}')"
  [[ -n "${pids:-}" ]] || return 0

  log "closing existing fuzzel instance(s): $pids"
  # shellcheck disable=SC2086
  kill $pids 2>/dev/null || true

  if [[ "$TOGGLE_MODE" == "toggle" ]]; then
    exit 0
  fi

  sleep 0.06
}

make_thumb_png() {
  local entry="$1"
  command -v magick >/dev/null 2>&1 || return 1

  local hash out lock tmp
  hash="$(sha1_of "$entry")"
  out="${THUMB_PREFIX}${hash}.png"
  lock="${LOCK_PREFIX}${hash}"

  [[ -s "$out" ]] && { printf '%s' "$out"; return 0; }

  exec {lfd}>"$lock" || true
  if ! flock -w 0.2 "$lfd"; then
    [[ -s "$out" ]] && { printf '%s' "$out"; return 0; }
    return 1
  fi

  [[ -s "$out" ]] && { printf '%s' "$out"; return 0; }

  tmp="${out}.tmp.$$"
  rm -f -- "$tmp" 2>/dev/null || true

  if timeout "$DECODE_TIMEOUT" cliphist decode 2>/dev/null <<<"$entry" \
    | magick - -auto-orient -strip -thumbnail "${THUMB_SIZE}x${THUMB_SIZE}" "png:${tmp}" 2>/dev/null; then
    mv -f -- "$tmp" "$out"
    printf '%s' "$out"
    return 0
  fi

  rm -f -- "$tmp" 2>/dev/null || true
  return 1
}

mapfile -t RAW < <(cliphist list 2>/dev/null | head -n "$LIST_LIMIT" || true)
((${#RAW[@]} > 0)) || { log "cliphist list empty"; exit 0; }

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

# If your config enables match-counter, kill it for this invocation by using an override config that includes yours,
# then overrides match-counter=no. :contentReference[oaicite:3]{index=3}
FUZZEL_ARGS=(--dmenu --prompt "$PROMPT")
(( SUP_NORUNEMPTY == 1 )) && FUZZEL_ARGS+=(--no-run-if-empty)
(( SUP_NOSORT == 1 )) && FUZZEL_ARGS+=(--no-sort)
(( SUP_CACHE == 1 )) && FUZZEL_ARGS+=(--cache="$CACHE_FILE")
(( SUP_WIDTH == 1 )) && FUZZEL_ARGS+=(--width="$FUZZEL_WIDTH_CHARS")
(( SUP_LINES == 1 )) && FUZZEL_ARGS+=(--lines="$FUZZEL_LINES")
(( SUP_LINEHEIGHT == 1 )) && FUZZEL_ARGS+=(--line-height="$FUZZEL_LINE_HEIGHT")

if [[ "$SHOW_MATCH_COUNTER" == "1" ]]; then
  (( SUP_COUNTER == 1 )) && FUZZEL_ARGS+=(--counter) # shows match count :contentReference[oaicite:4]{index=4}
else
  if (( SUP_CONFIG == 1 )); then
    OVERRIDE_CFG_PATH="${OVERRIDE_CFG_PATH:-$RUNTIME_BASE/cliphist-fuzzel.override.ini}"
    {
      echo "[main]"
      if [[ -f "$USER_FUZZEL_CFG" ]]; then
        echo "include=$USER_FUZZEL_CFG"
      fi
      echo "match-counter=no"
    } > "$OVERRIDE_CFG_PATH"
    FUZZEL_ARGS+=(--config="$OVERRIDE_CFG_PATH")
  fi
fi

# Prefer --index so we can display labels but decode the real RAW entry
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

# Fallback if --index is missing: show raw entries (IDs visible)
set +e
CHOICE="$(printf '%s\n' "${RAW[@]}" | fuzzel "${FUZZEL_ARGS[@]}")"
rc=$?
set -e

log "fuzzel rc=$rc choice_len=${#CHOICE}"
[[ $rc -ne 0 ]] && exit 0
[[ -z "${CHOICE:-}" ]] && exit 0

cliphist decode <<<"$CHOICE" | wl-copy -n
