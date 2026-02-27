#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# ~/.config/hypr/scripts/wallpicker.sh
# Terminal wallpaper picker for Hyprland using SIXEL thumbnails.
# Optimized for alacritty-graphics / SIXEL-capable terminals.
#
# QoL changes:
# - SPACE is the advertised apply key (Enter still works silently if your terminal sends it)
# - Reduced flicker via partial redraw on navigation within the same page
# - f = find (search prompt)
# - R = refresh (rescans and clears active find filter)
# - d = cycle swww transition duration
# - p = cycle swww transition fps
# - count line renamed to total/shown
# - startup never restores previous find filter

# Arch deps (repo): 
#    sudo pacman -S --needed imagemagick libsixel swww jq xdg-utils   # libsixel provides img2sixel
# Optional backend (repo): sudo pacman -S --needed hyprpaper

APP_NAME="wallpicker"
APP_ID="wallpicker"

DEFAULT_WALL_DIR="${HOME}/Pictures/wallpapers"
WALL_DIR="${DEFAULT_WALL_DIR}"
RECURSIVE=1

BACKEND="swww"                  # swww | hyprpaper
DISPLAY_TARGET="All displays"   # All displays | output name

# swww settings (key-adjustable, auto-saved)
SWWW_RESIZE="crop"              # crop | fit | stretch | no
SWWW_TRANSITION_TYPE="grow"     # fade | grow | outer | any | random
SWWW_TRANSITION_DURATION="0.8"  # key: d
SWWW_TRANSITION_FPS="30"        # key: p
SWWW_FILTER="Lanczos3"          # key: i (interpolation filter)

# hyprpaper setting (key: P)
HYPERPAPER_MODE="cover"         # cover | contain | center

# UI sizing (cells) and pixel estimate for thumbnail generation
: "${WALLPICKER_CHAR_PX_W:=8}"
: "${WALLPICKER_CHAR_PX_H:=16}"
: "${WALLPICKER_THUMB_CH_W:=24}"
: "${WALLPICKER_THUMB_CH_H:=6}"
: "${WALLPICKER_CELL_W:=10}"
: "${WALLPICKER_CELL_H:=0}"
: "${WALLPICKER_GAP_W:=1}"
: "${WALLPICKER_GAP_H:=0}"
: "${WALLPICKER_ALT_SCREEN:=0}"
: "${WALLPICKER_NO_SIXEL:=0}"
: "${WALLPICKER_DEBUG:=0}"
: "${WALLPICKER_INPUT_POLL_S:=0.20}"  # seconds; enables resize refresh without keypress
: "${WALLPICKER_RESIZE_RESCAN:=0}"   # 1=run full refresh_action on resize (clears find + rescans)
: "${WALLPICKER_FORCE_ENCODER:=}"  # chafa|img2sixel|magick|kitty
: "${WALLPICKER_PREWARM_VISIBLE_PAGE:=0}"  # 0=off (faster startup), 1=warm visible page before draw
: "${WALLPICKER_SORT_SCAN:=1}"           # 1=stable sort, 0=faster unsorted scan

THUMB_CH_W="${WALLPICKER_THUMB_CH_W}"
THUMB_CH_H="${WALLPICKER_THUMB_CH_H}"
CELL_W="${WALLPICKER_CELL_W}"
CELL_H="${WALLPICKER_CELL_H}"
GAP_W="${WALLPICKER_GAP_W}"
GAP_H="${WALLPICKER_GAP_H}"
CHAR_PX_W="${WALLPICKER_CHAR_PX_W}"
CHAR_PX_H="${WALLPICKER_CHAR_PX_H}"

THUMB_PX_W=$(( THUMB_CH_W * CHAR_PX_W ))
THUMB_PX_H=$(( THUMB_CH_H * CHAR_PX_H ))

# Geometry safety: cell must fully contain preview + spacer + filename + number row.
# Prevents SIXEL tiles from overlapping/corrupting when scrolling or redrawing.
if (( CELL_W < THUMB_CH_W )); then
  CELL_W=$THUMB_CH_W
fi
if (( CELL_H < THUMB_CH_H + 4 )); then
  CELL_H=$(( THUMB_CH_H + 4 ))
fi
if (( GAP_W < 1 )); then GAP_W=1; fi
if (( GAP_H < 0 )); then GAP_H=0; fi
THUMB_STYLE_VERSION="sixel-grid-v4-qol-chafa-cells-mousefix2-midgrid-geom-bump-rowspacefix-165556"
TOP_LINES=4
BOTTOM_LINES=2
CONFIG_DIR="${HOME}/.config/${APP_ID}"
CACHE_DIR="${HOME}/.cache/${APP_ID}"
THUMB_CACHE_DIR="${CACHE_DIR}/thumbs"
STATE_FILE="${CONFIG_DIR}/state.conf"
BACKEND_STATE_FILE="${CONFIG_DIR}/backend_state.tsv"

DEBUG_LOG="${CACHE_DIR}/debug.log"
KITTY_ERR_LOG="${CACHE_DIR}/kitty.err.log"

mkdir -p "${CONFIG_DIR}" "${THUMB_CACHE_DIR}" "${CACHE_DIR}"

# ---------- state ----------
declare -a ALL_FILES=()
declare -a FILES=()
declare -a DISPLAY_CHOICES=()
declare -a TARGET_OUTPUTS=()
declare -a SWWW_DURATION_OPTIONS=(0.0 0.2 0.4 0.8 1.2 2.0 3.0 4.0)
declare -a SWWW_FPS_OPTIONS=(15 24 30 45 60 90)

FILTER_QUERY=""                 # runtime only (not persisted)
STATUS_MSG="Starting..."
SEL=0
RUNNING=1
UI_ACTIVE=0
HYPERPAPER_JUST_STARTED=0

RESUME_LAST=0               # --resume (start where you last were)
START_AT=""                 # --start-at N (1-based)
LAST_SEL=0                  # persisted selection index
LAST_FOCUS=""              # persisted last focused wallpaper path
LAST_APPLIED=""            # persisted last applied wallpaper path


GRID_COLS=1
GRID_ROWS=1
PAGE_SIZE=1

TERM_COLS_LAST=0
TERM_LINES_LAST=0
RESIZE_PENDING=0

SIXEL_ENCODER=""
SIXEL_ENCODER_LABEL=""
PREVIEW_MODE="sixel"              # sixel | kitty | disabled
TTY_STTY_SAVED=""
LAST_ENCODER_ERR=""

NEED_FULL_REDRAW=1
LOADING_SPINNER_IDX=0
LAST_GRID_COLS=0
LAST_GRID_ROWS=0

declare -A HASH_CACHE=()

BACKEND_STATE_BACKEND=""
declare -A BACKEND_STATE_MAP=()

# ---------- helpers ----------
msg() { STATUS_MSG="$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

backend_state_read() {
  BACKEND_STATE_BACKEND=""
  BACKEND_STATE_MAP=()
  [[ -f "$BACKEND_STATE_FILE" ]] || return 0
  local k v
  while IFS=$'\t' read -r k v; do
    [[ -z "${k:-}" ]] && continue
    if [[ "$k" == "backend" ]]; then
      BACKEND_STATE_BACKEND="$v"
      continue
    fi
    BACKEND_STATE_MAP["$k"]="$v"
  done < "$BACKEND_STATE_FILE"
  return 0
}

backend_state_write() {
  local backend="$1" tmp
  mkdir -p -- "$CONFIG_DIR"
  tmp="${BACKEND_STATE_FILE}.tmp.$$"
  {
    printf 'backend\t%s\n' "$backend"
    for k in "${!BACKEND_STATE_MAP[@]}"; do
      printf '%s\t%s\n' "$k" "${BACKEND_STATE_MAP[$k]}"
    done | LC_ALL=C sort
  } > "$tmp"
  mv -f -- "$tmp" "$BACKEND_STATE_FILE"
}

backend_state_set_outputs() {
  local backend="$1" img="$2"; shift 2
  backend_state_read
  local out
  for out in "$@"; do
    BACKEND_STATE_MAP["$out"]="$img"
  done
  backend_state_write "$backend"
}

backend_state_set_backend_only() {
  local backend="$1"
  backend_state_read
  backend_state_write "$backend"
}

is_hyprpaper_running() {
  if have pgrep; then
    pgrep -x hyprpaper >/dev/null 2>&1
  elif have pidof; then
    pidof hyprpaper >/dev/null 2>&1
  else
    ps -C hyprpaper >/dev/null 2>&1
  fi
}

kill_hyprpaper_if_running() {
  is_hyprpaper_running || return 0
  if have pkill; then
    pkill -x hyprpaper >/dev/null 2>&1 || true
  elif have killall; then
    killall hyprpaper >/dev/null 2>&1 || true
  fi
  return 0
}

takeover_hyprpaper_to_swww() {
  # Kill hyprpaper and reapply the last-known per-output wallpapers via swww.
  backend_state_read
  [[ "$BACKEND_STATE_BACKEND" == "hyprpaper" ]] || { kill_hyprpaper_if_running; return 0; }
  ensure_swww_daemon || { kill_hyprpaper_if_running; return 0; }
  kill_hyprpaper_if_running

  local out img
  for out in "${!BACKEND_STATE_MAP[@]}"; do
    img="${BACKEND_STATE_MAP[$out]}"
    [[ -n "$img" && -f "$img" ]] || continue
    run_quiet_hup_safe swww img \
      --outputs "$out" \
      --resize "$SWWW_RESIZE" \
      --transition-type "$SWWW_TRANSITION_TYPE" \
      --transition-duration "$SWWW_TRANSITION_DURATION" \
      --transition-fps "$SWWW_TRANSITION_FPS" \
      --filter "$SWWW_FILTER" \
      -- "$img" || true
  done
  backend_state_set_backend_only "swww" || true
  return 0
}

debug() {
  if [[ "${WALLPICKER_DEBUG}" == "1" ]]; then
    printf 'wallpicker(debug): %s\n' "$*" >&2
  fi
  return 0
}

is_kitty_term() {
  [[ -n "${KITTY_WINDOW_ID:-}" ]] && return 0
  [[ "${TERM:-}" == "xterm-kitty" ]] && return 0
  [[ "${TERM:-}" == *kitty* ]] && return 0
  return 1
}

kitty_icat_help_has() {
  local needle="$1"
  have kitty || return 1
  kitty +kitten icat --help 2>/dev/null | grep -q -- "$needle"
}


kitty_passthrough_mode() {
  # kitty supports: detect|none|tmux (your version errors on 'auto')
  kitty_icat_help_has -- "--passthrough" || { printf ''; return 0; }
  if [[ -n "${TMUX:-}" ]]; then
    printf 'tmux'
  else
    printf 'detect'
  fi
  return 0
}
kitty_clear_images() {
  command -v kitty >/dev/null 2>&1 || return 0
  : >"$KITTY_ERR_LOG" 2>/dev/null || true

  local pm
  pm="$(kitty_passthrough_mode)"

  # Critical: --stdin=no prevents icat from treating non-tty stdin as an image.
  # Never redirect stdout (it carries the graphics protocol output).
  if [[ -n "$pm" ]]; then
    kitty +kitten icat --stdin=no --passthrough "$pm" --clear 2>>"$KITTY_ERR_LOG" || true
  else
    kitty +kitten icat --stdin=no --clear 2>>"$KITTY_ERR_LOG" || true
  fi
  return 0
}
kitty_draw_png_at() {
  local png="$1" col_1b="${2:-1}" row_1b="${3:-1}" left top place pm
  command -v kitty >/dev/null 2>&1 || return 1
  [[ -n "${png:-}" ]] || return 1

  # If caller accidentally passed a multi-line string (png + six), keep only the first line.
  png="${png%%$'\n'*}"
  png="${png%%$'\r'*}"

  [[ -s "$png" ]] || return 1
  kitty_icat_help_has -- "--place" || { LAST_ENCODER_ERR="kitty icat missing --place"; return 1; }

  left=$(( col_1b - 1 ))
  top=$(( row_1b - 1 ))
  place="${THUMB_CH_W}x${THUMB_CH_H}@${left}x${top}"

  : >"$KITTY_ERR_LOG" 2>/dev/null || true
  pm="$(kitty_passthrough_mode)"

  # Critical: --stdin=no. Do not redirect stdout.
  if [[ -n "$pm" ]]; then
    kitty +kitten icat --stdin=no --passthrough "$pm" --place "$place" --scale-up -- "$png" 2>>"$KITTY_ERR_LOG" && return 0
  else
    kitty +kitten icat --stdin=no --place "$place" --scale-up -- "$png" 2>>"$KITTY_ERR_LOG" && return 0
  fi

  LAST_ENCODER_ERR="$(tail -n 1 "$KITTY_ERR_LOG" 2>/dev/null | tr -d '\r' | head -c 200)"
  [[ -n "$LAST_ENCODER_ERR" ]] || LAST_ENCODER_ERR="kitty icat failed"
  return 1
}





run_quiet_hup_safe() {
  # Let apply commands survive terminal/window close (SIGHUP) during fast external toggles.
  if have nohup; then
    nohup "$@" </dev/null >/dev/null 2>&1
  else
    "$@" </dev/null >/dev/null 2>&1
  fi
}

hyprpaper_ctl() {
  # Usage: hyprpaper_ctl <seconds> <hyprpaper-subcmd...>
  local sec="$1"
  shift

  if have timeout; then
    timeout -k 0.25s "${sec}s" hyprctl hyprpaper "$@" </dev/null >/dev/null 2>&1
    return $?
  fi

  hyprctl hyprpaper "$@" </dev/null >/dev/null 2>&1 &
  local pid=$!

  (
    sleep "$sec"
    kill -TERM "$pid" 2>/dev/null || true
    sleep 0.25
    kill -KILL "$pid" 2>/dev/null || true
  ) &
  local killer=$!

  wait "$pid" 2>/dev/null
  local rc=$?
  kill "$killer" 2>/dev/null || true
  wait "$killer" 2>/dev/null || true
  return "$rc"
}


run_with_timeout() {
  # Usage: run_with_timeout <seconds> <cmd...>
  local sec="$1"
  shift
  if have timeout; then
    timeout "${sec}s" "$@"
    return $?
  fi

  "$@" &
  local pid=$!
  local killer

  (
    sleep "$sec"
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      sleep 0.5
      kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null || true
    fi
  ) &
  killer=$!

  wait "$pid" 2>/dev/null
  local rc=$?

  kill "$killer" 2>/dev/null || true
  wait "$killer" 2>/dev/null || true
  return "$rc"
}

hyprctl_quiet() {
  # Usage: hyprctl_quiet <seconds> <hyprctl args...>
  local sec="$1"
  shift
  run_with_timeout "$sec" hyprctl "$@" </dev/null >/dev/null 2>&1
}

restart_hyprpaper() {
  if have pkill; then pkill -x hyprpaper >/dev/null 2>&1 || true; fi
  if have killall; then killall hyprpaper >/dev/null 2>&1 || true; fi
  (nohup hyprpaper >/dev/null 2>&1 &) || true
}


update_focus_state() {
  if (( ${#FILES[@]} == 0 )); then
    LAST_SEL=0
    LAST_FOCUS=""
    return 0
  fi
  SEL="$(clamp_int "$SEL" 0 "$(( ${#FILES[@]} - 1 ))")"
  LAST_SEL="$SEL"
  LAST_FOCUS="${FILES[$SEL]}"
  return 0
}

_find_idx_by_path_or_unique_base() {
  local target="$1" base i match=-1 hits=0
  [[ -n "$target" ]] || return 1

  for i in "${!FILES[@]}"; do
    [[ "${FILES[$i]}" == "$target" ]] || continue
    printf '%d' "$i"
    return 0
  done

  base="$(basename -- "$target")"
  for i in "${!FILES[@]}"; do
    [[ "$(basename -- "${FILES[$i]}")" == "$base" ]] || continue
    match="$i"
    hits=$(( hits + 1 ))
  done

  (( hits == 1 )) || return 1
  printf '%d' "$match"
  return 0
}

resume_focus_last() {
  local idx

  if (( ${#FILES[@]} == 0 )); then
    return 1
  fi

  idx="$(_find_idx_by_path_or_unique_base "${LAST_FOCUS:-}" 2>/dev/null || true)"
  if [[ -n "$idx" ]]; then
    SEL="$idx"

  update_focus_state || true
    return 0
  fi

  idx="$(_find_idx_by_path_or_unique_base "${LAST_APPLIED:-}" 2>/dev/null || true)"
  if [[ -n "$idx" ]]; then
    SEL="$idx"
    return 0
  fi

  if [[ "${LAST_SEL:-0}" =~ ^[0-9]+$ ]]; then
    SEL="$(clamp_int "$LAST_SEL" 0 "$(( ${#FILES[@]} - 1 ))")"
    return 0
  fi

  return 1
}


die() {
  printf 'wallpicker.sh: %s\n' "$*" >&2
  exit 1
}

term_cols() { tput cols 2>/dev/null || printf '120'; }
term_lines() { tput lines 2>/dev/null || printf '40'; }

detect_term_resize() {
  local cols lines
  cols="$(term_cols)"
  lines="$(term_lines)"
  if (( cols != TERM_COLS_LAST || lines != TERM_LINES_LAST )); then
    TERM_COLS_LAST="$cols"
    TERM_LINES_LAST="$lines"
    RESIZE_PENDING=1
    NEED_FULL_REDRAW=1
  fi
  return 0
}

preflight_tty_checks() {
  [[ -t 0 && -t 1 ]] || die "Run this script in an interactive terminal."
  have tput || die "Missing tput (ncurses)"
  tput cols >/dev/null 2>&1 || die "TERM/terminfo invalid (TERM=${TERM:-unset})"
  tput lines >/dev/null 2>&1 || die "TERM/terminfo invalid (TERM=${TERM:-unset})"
}

clamp_int() {
  local v="$1" min="$2" max="$3"
  if (( v < min )); then
    printf '%d' "$min"
  elif (( v > max )); then
    printf '%d' "$max"
  else
    printf '%d' "$v"
  fi
}

sanitize_text() {
  local s="$1"
  s="${s//$'\n'/ }"
  s="${s//$'\r'/ }"
  s="${s//$'\t'/ }"
  printf '%s' "$s"
}

normalize_query() {
  local s
  s="$(sanitize_text "$1")"
  # trim leading/trailing whitespace
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

pad_trunc() {
  local s="$1" w="$2"
  s="$(sanitize_text "$s")"
  printf '%-*.*s' "$w" "$w" "$s"
}

short_path() {
  local p="$1" max="${2:-80}"
  p="${p/#$HOME/~}"
  if (( ${#p} <= max )); then
    printf '%s' "$p"
  else
    printf '...%s' "${p: -$((max-3))}"
  fi
}

hash_for_file() {
  local p="$1" mtime size cache_key hash
  mtime="$(stat -c '%Y' -- "$p" 2>/dev/null || printf '0')"
  size="$(stat -c '%s' -- "$p" 2>/dev/null || printf '0')"
  cache_key="${p}"$'\x1f'"${mtime}"$'\x1f'"${size}"$'\x1f'"${THUMB_STYLE_VERSION}"$'\x1f'"${THUMB_PX_W}x${THUMB_PX_H}"

  if [[ -n "${HASH_CACHE[$cache_key]:-}" ]]; then
    printf '%s' "${HASH_CACHE[$cache_key]}"
    return 0
  fi

  hash="$(
    printf '%s\0%s\0%s\0%s\0%sx%s\0' \
      "$p" "$mtime" "$size" "$THUMB_STYLE_VERSION" "$THUMB_PX_W" "$THUMB_PX_H" |
    sha256sum | awk '{print $1}'
  )"
  HASH_CACHE["$cache_key"]="$hash"
  printf '%s' "$hash"
}
thumb_png_path() { printf '%s/%s.png' "$THUMB_CACHE_DIR" "$(hash_for_file "$1")"; }
thumb_six_path() { printf '%s/%s.six' "$THUMB_CACHE_DIR" "$(hash_for_file "$1")"; }

step_duration_cycle() {
  local i next
  for i in "${!SWWW_DURATION_OPTIONS[@]}"; do
    if [[ "${SWWW_DURATION_OPTIONS[$i]}" == "$SWWW_TRANSITION_DURATION" ]]; then
      next=$(( (i + 1) % ${#SWWW_DURATION_OPTIONS[@]} ))
      SWWW_TRANSITION_DURATION="${SWWW_DURATION_OPTIONS[$next]}"
      return 0
    fi
  done
  SWWW_TRANSITION_DURATION="${SWWW_DURATION_OPTIONS[0]}"
}

step_fps_cycle() {
  local i next
  for i in "${!SWWW_FPS_OPTIONS[@]}"; do
    if [[ "${SWWW_FPS_OPTIONS[$i]}" == "$SWWW_TRANSITION_FPS" ]]; then
      next=$(( (i + 1) % ${#SWWW_FPS_OPTIONS[@]} ))
      SWWW_TRANSITION_FPS="${SWWW_FPS_OPTIONS[$next]}"
      return 0
    fi
  done
  SWWW_TRANSITION_FPS="${SWWW_FPS_OPTIONS[0]}"
}

drain_pending_keys() {
  local _junk _i=0 _max="${1:-256}"
  while (( _i < _max )) && IFS= read -rsn1 -t 0.001 _junk; do
    _i=$(( _i + 1 ))
  done
  return 0
}

# ---------- encoder detection / thumbs ----------
detect_sixel_encoder() {
  if [[ "${WALLPICKER_NO_SIXEL}" == "1" ]]; then
    SIXEL_ENCODER=""
    SIXEL_ENCODER_LABEL="disabled"
    PREVIEW_MODE="disabled"
    return 0
  fi

  if is_kitty_term && kitty_icat_help_has -- "--place"; then
    SIXEL_ENCODER="kitty"
    SIXEL_ENCODER_LABEL="kitty(icat)"
    PREVIEW_MODE="kitty"
    return 0
  fi

  PREVIEW_MODE="sixel"

  if [[ -n "${WALLPICKER_FORCE_ENCODER}" ]]; then
    case "${WALLPICKER_FORCE_ENCODER}" in
      chafa)
        if have chafa; then
          SIXEL_ENCODER="chafa"
          SIXEL_ENCODER_LABEL="chafa"
          return 0
        fi
        ;;
      img2sixel)
        if have img2sixel; then
          SIXEL_ENCODER="img2sixel"
          SIXEL_ENCODER_LABEL="img2sixel(-7)"
          return 0
        fi
        ;;
      magick)
        if have magick && magick -list format 2>/dev/null | grep -qiE '^[[:space:]]*SIXEL'; then
          SIXEL_ENCODER="magick"
          SIXEL_ENCODER_LABEL="magick(SIXEL)"
          return 0
        fi
        ;;
    esac
  fi

  if have img2sixel; then
    SIXEL_ENCODER="img2sixel"
    SIXEL_ENCODER_LABEL="img2sixel(-7)"
    return 0
  fi

  if have chafa; then
    SIXEL_ENCODER="chafa"
    SIXEL_ENCODER_LABEL="chafa"
    return 0
  fi

  if have magick && magick -list format 2>/dev/null | grep -qiE '^[[:space:]]*SIXEL'; then
    SIXEL_ENCODER="magick"
    SIXEL_ENCODER_LABEL="magick(SIXEL)"
    return 0
  fi

  SIXEL_ENCODER=""
  SIXEL_ENCODER_LABEL="none"
  PREVIEW_MODE="disabled"
  return 1
}



print_requirements_help() {
  cat >&2 <<'REQEOF'
wallpicker.sh requirements (Arch Linux)

Required:
  hyprland (hyprctl)
  imagemagick (magick)
  ncurses (tput)
  one preview encoder unless WALLPICKER_NO_SIXEL=1:
    chafa (recommended)
    libsixel (img2sixel)
    OR ImageMagick built with SIXEL

Backends:
  swww      (backend=swww)
  hyprpaper (backend=hyprpaper)

Optional:
  jq        (better monitor detection)
  xdg-utils (open wallpaper folder)
REQEOF
}

check_runtime_requirements() {
  local missing=0 c item
  local -a core_cmds=(find sort sha256sum stat sed grep awk basename dirname tput)
  local -a missing_cmds=()

  for c in "${core_cmds[@]}"; do
    if ! have "$c"; then
      missing_cmds+=("$c")
      missing=1
    fi
  done

  if ! have hyprctl; then
    missing_cmds+=("hyprctl (package: hyprland)")
    missing=1
  fi

  case "$BACKEND" in
    swww)
      if ! have swww; then missing_cmds+=("swww (package: swww)"); missing=1; fi
      ;;
    hyprpaper)
      if ! have hyprpaper; then missing_cmds+=("hyprpaper (package: hyprpaper)"); missing=1; fi
      ;;
    *)
      missing_cmds+=("invalid backend '$BACKEND'")
      missing=1
      ;;
  esac

  if ! have magick; then
    missing_cmds+=("magick (package: imagemagick)")
    missing=1
  fi

  if [[ "${WALLPICKER_NO_SIXEL}" != "1" ]]; then
    if ! detect_sixel_encoder; then
      missing_cmds+=("no preview encoder found (install chafa or libsixel)")
      missing=1
    fi
  else
    detect_sixel_encoder || true
  fi

  if (( missing )); then
    echo "wallpicker.sh cannot start. Missing requirements:" >&2
    for item in "${missing_cmds[@]}"; do echo "  - $item" >&2; done
    echo >&2
    print_requirements_help
    return 1
  fi

  if ! have jq; then echo "WARN: jq not found (monitor detection less reliable)." >&2; fi
  if ! have xdg-open; then echo "WARN: xdg-open not found ('o' key disabled)." >&2; fi
  return 0
}

generate_thumb_png() {
  local src="$1" dst="$2" tmp ext src_decode
  tmp="${dst}.tmp.$$"

  mkdir -p -- "$(dirname -- "$dst")"

  ext="${src##*.}"
  ext="${ext,,}"

  # Animated formats can be slow or fail when ImageMagick tries to process all frames.
  # Force frame 0 for preview thumbnails.
  case "$ext" in
    gif|webp|avif)
      src_decode="${src}[0]"
      ;;
    *)
      src_decode="$src"
      ;;
  esac

  if magick "$src_decode"       -auto-orient       -thumbnail "${THUMB_PX_W}x${THUMB_PX_H}"       -background black       -alpha background       -gravity center       -extent "${THUMB_PX_W}x${THUMB_PX_H}"       "PNG:${tmp}" >/dev/null 2>&1; then
    mv -f -- "$tmp" "$dst"
    return 0
  fi

  rm -f -- "$tmp"

  # Final fallback path: try original source (and then explicit [0] if not already used).
  if [[ "$src_decode" != "$src" ]]; then
    if magick "$src"         -auto-orient         -thumbnail "${THUMB_PX_W}x${THUMB_PX_H}"         -background black         -alpha background         -gravity center         -extent "${THUMB_PX_W}x${THUMB_PX_H}"         "PNG:${tmp}" >/dev/null 2>&1; then
      mv -f -- "$tmp" "$dst"
      return 0
    fi
    rm -f -- "$tmp"
  else
    if magick "${src}[0]"         -auto-orient         -thumbnail "${THUMB_PX_W}x${THUMB_PX_H}"         -background black         -alpha background         -gravity center         -extent "${THUMB_PX_W}x${THUMB_PX_H}"         "PNG:${tmp}" >/dev/null 2>&1; then
      mv -f -- "$tmp" "$dst"
      return 0
    fi
    rm -f -- "$tmp"
  fi

  LAST_ENCODER_ERR="thumb png failed: $(basename -- "$src")"
  return 1
}

encode_sixel_from_png() {
  local png="$1"
  local out_file="${2:-}"

  case "$SIXEL_ENCODER" in
    chafa)
      # chafa --size is in columns x rows (cell units), not pixels.
      chafa \
        -f sixels \
        --size "${THUMB_CH_W}x${THUMB_CH_H}" \
        --stretch \
        -- "$png"
      ;;
    img2sixel)
      # Some builds produce empty stdout. Prefer -o when caller passes file path.
      if [[ -n "$out_file" ]]; then
        img2sixel -7 -w "${THUMB_PX_W}" -h "${THUMB_PX_H}" -o "$out_file" "$png"
      else
        img2sixel -7 -w "${THUMB_PX_W}" -h "${THUMB_PX_H}" "$png"
      fi
      ;;
    magick)
      magick "$png" sixel:-
      ;;
    *)
      return 1
      ;;
  esac
}

ensure_thumb_assets() {
  local src="$1" png six tmp
  local primary_encoder primary_label
  local try_encoder
  local -a tries=()
  local ok=0

  png="$(thumb_png_path "$src")"
  six="$(thumb_six_path "$src")"

  if [[ ! -s "$png" ]]; then
    generate_thumb_png "$src" "$png" || return 1
  fi

  if [[ "${WALLPICKER_NO_SIXEL}" == "1" ]]; then
    printf '%s\n\n' "$png"
    return 0
  fi

  if [[ "${PREVIEW_MODE}" == "kitty" ]]; then
    printf '%s\n\n' "$png"
    return 0
  fi

  if [[ ! -s "$six" ]]; then
    detect_sixel_encoder || return 1

    primary_encoder="$SIXEL_ENCODER"
    primary_label="$SIXEL_ENCODER_LABEL"

    # Try current encoder first, then known alternates (unique only).
    tries=()
    [[ -n "$primary_encoder" ]] && tries+=("$primary_encoder")

    for try_encoder in chafa img2sixel magick; do
      case "$try_encoder" in
        chafa) have chafa || continue ;;
        img2sixel) have img2sixel || continue ;;
        magick)
          have magick || continue
          magick -list format 2>/dev/null | grep -qiE '^[[:space:]]*SIXEL' || continue
          ;;
      esac

      if [[ " ${tries[*]} " != *" $try_encoder "* ]]; then
        tries+=("$try_encoder")
      fi
    done

    for try_encoder in "${tries[@]}"; do
      SIXEL_ENCODER="$try_encoder"
      case "$try_encoder" in
        chafa) SIXEL_ENCODER_LABEL="chafa" ;;
        img2sixel) SIXEL_ENCODER_LABEL="img2sixel(-7)" ;;
        magick) SIXEL_ENCODER_LABEL="magick(SIXEL)" ;;
      esac

      tmp="${six}.tmp.$$"
      rm -f -- "$tmp"

      case "$SIXEL_ENCODER" in
        img2sixel)
          if encode_sixel_from_png "$png" "$tmp" >>"$DEBUG_LOG" 2>&1 && [[ -s "$tmp" ]]; then
            mv -f -- "$tmp" "$six"
            ok=1
          else
            rm -f -- "$tmp"
          fi
          ;;
        *)
          if encode_sixel_from_png "$png" >"$tmp" 2>>"$DEBUG_LOG" && [[ -s "$tmp" ]]; then
            mv -f -- "$tmp" "$six"
            ok=1
          else
            rm -f -- "$tmp"
          fi
          ;;
      esac

      if (( ok == 1 )); then
        if [[ "$try_encoder" != "$primary_encoder" ]]; then
          msg "Preview encoder fallback: ${primary_label} -> ${SIXEL_ENCODER_LABEL}"
        fi
        LAST_ENCODER_ERR=""
        break
      fi
    done

    if (( ok == 0 )); then
      SIXEL_ENCODER="$primary_encoder"
      SIXEL_ENCODER_LABEL="$primary_label"
      LAST_ENCODER_ERR="all preview encoders failed: $(basename -- "$src")"
      return 1
    fi
  fi

  printf '%s\n%s\n' "$png" "$six"
  return 0
}

# ---------- monitor / backend ----------
refresh_display_choices() {
  local cur="$DISPLAY_TARGET" name item found=0
  local -A seen=()
  DISPLAY_CHOICES=("All displays")
  seen["All displays"]=1

  if have hyprctl && have jq; then
    while IFS= read -r name; do
      [[ -n "$name" ]] || continue
      if [[ -z "${seen[$name]:-}" ]]; then
        DISPLAY_CHOICES+=("$name")
        seen["$name"]=1
      fi
    done < <(hyprctl -j monitors 2>/dev/null | jq -r '.[].name // empty' 2>/dev/null || true)
  fi

  if (( ${#DISPLAY_CHOICES[@]} == 1 )) && have swww; then
    while IFS= read -r name; do
      [[ -n "$name" ]] || continue
      if [[ -z "${seen[$name]:-}" ]]; then
        DISPLAY_CHOICES+=("$name")
        seen["$name"]=1
      fi
    done < <(swww query 2>/dev/null | sed -n 's/^\([^:]*\):.*/\1/p' || true)
  fi

  for item in "${DISPLAY_CHOICES[@]}"; do
    if [[ "$item" == "$cur" ]]; then
      found=1
      break
    fi
  done
  if (( found == 1 )); then
    DISPLAY_TARGET="$cur"
  else
    DISPLAY_TARGET="All displays"
  fi
}

resolve_target_outputs() {
  local item
  TARGET_OUTPUTS=()
  if [[ "$DISPLAY_TARGET" != "All displays" ]]; then
    TARGET_OUTPUTS=("$DISPLAY_TARGET")
    return 0
  fi
  for item in "${DISPLAY_CHOICES[@]}"; do
    [[ "$item" == "All displays" ]] && continue
    TARGET_OUTPUTS+=("$item")
  done
}

ensure_swww_daemon() {
  local i
  if ! have swww; then msg "swww not installed"; return 1; fi
  if swww query >/dev/null 2>&1; then return 0; fi
  if ! have swww-daemon; then msg "swww-daemon not installed"; return 1; fi
  (nohup swww-daemon >/dev/null 2>&1 &) || true
  for i in {1..20}; do
    if swww query >/dev/null 2>&1; then return 0; fi
    sleep 0.2
  done
  msg "swww-daemon did not become ready"
  return 1
}

ensure_hyprpaper_running() {
  local i
  if ! have hyprpaper; then msg "hyprpaper not installed"; return 1; fi
  if is_hyprpaper_running; then
    HYPERPAPER_JUST_STARTED=0
    return 0
  fi
  HYPERPAPER_JUST_STARTED=1
  (nohup hyprpaper >/dev/null 2>&1 &) || true
  for i in {1..40}; do
    is_hyprpaper_running && return 0
    sleep 0.1
  done
  msg "hyprpaper did not start"
  return 1
}

apply_with_swww() {
  local img="$1" outputs_csv

  # If hyprpaper is running, it will sit on top of swww. Kill it before applying.
  kill_hyprpaper_if_running

  resolve_target_outputs
  if (( ${#TARGET_OUTPUTS[@]} == 0 )); then msg "No outputs detected"; return 1; fi
  ensure_swww_daemon || return 1

  outputs_csv="$(IFS=,; printf '%s' "${TARGET_OUTPUTS[*]}")"
  if run_quiet_hup_safe swww img \
      --outputs "$outputs_csv" \
      --resize "$SWWW_RESIZE" \
      --transition-type "$SWWW_TRANSITION_TYPE" \
      --transition-duration "$SWWW_TRANSITION_DURATION" \
      --transition-fps "$SWWW_TRANSITION_FPS" \
      --filter "$SWWW_FILTER" \
      -- "$img"; then
    backend_state_set_outputs "swww" "$img" "${TARGET_OUTPUTS[@]}" || true
    msg "Applied via swww -> $(basename -- "$img")"
    return 0
  fi
  msg "swww apply failed"
  return 1
}

apply_with_hyprpaper() {
  local img="$1" out arg ext t

  ext="${img##*.}"; ext="${ext,,}"
  if [[ "$ext" == "gif" ]]; then
    msg "hyprpaper: GIF not supported"
    return 1
  fi

  resolve_target_outputs
  if (( ${#TARGET_OUTPUTS[@]} == 0 )); then msg "No outputs detected"; return 1; fi
  ensure_hyprpaper_running || return 1

  t="${HYPERPAPER_TIMEOUT:-3}"
  local max_tries try ok ctl_t t_fast

  # hyprpaper can take a moment to accept hyprctl requests right after launch.
  # When switching to hyprpaper backend, retry quickly so the first click applies.
  t_fast="${HYPERPAPER_STARTUP_TIMEOUT:-0.4}"
  max_tries=1
  if (( HYPERPAPER_JUST_STARTED == 1 )); then
    max_tries=8
  fi

  for out in "${TARGET_OUTPUTS[@]}"; do
    ok=0
    try=0
    while (( try < max_tries )); do
      ctl_t="$t"
      if (( HYPERPAPER_JUST_STARTED == 1 && try < max_tries - 1 )); then
        ctl_t="$t_fast"
      fi
      # hyprpaper expects: "mon, path, fit_mode" (note spaces after commas)
      arg="${out}, ${img}, ${HYPERPAPER_MODE}"
      if hyprpaper_ctl "$ctl_t" wallpaper "$arg"; then
        ok=1
        break
      fi
      arg="${out}, ${img}"
      if hyprpaper_ctl "$ctl_t" wallpaper "$arg"; then
        ok=1
        break
      fi
      (( try++ ))
      sleep 0.1
    done

    if (( ok == 0 )); then
      msg "hyprpaper apply failed on ${out}"
      return 1
    fi
  done

  HYPERPAPER_JUST_STARTED=0

  backend_state_set_outputs "hyprpaper" "$img" "${TARGET_OUTPUTS[@]}" || true
  msg "Applied via hyprpaper -> $(basename -- "$img")"
  return 0
}

apply_selected() {
  local img rc
  if (( ${#FILES[@]} == 0 )); then msg "No wallpapers to apply"; return 1; fi

  update_focus_state || true
  img="${FILES[$SEL]}"

  rc=1
  case "$BACKEND" in
    swww) apply_with_swww "$img"; rc=$? ;;
    hyprpaper) apply_with_hyprpaper "$img"; rc=$? ;;
    *) msg "Invalid backend: $BACKEND"; return 1 ;;
  esac

  if (( rc == 0 )); then
    LAST_APPLIED="$img"
    update_focus_state || true
    save_state || true
  fi

  return "$rc"
}


resume_focus_last_applied() {
  local target base i match=-1 hits=0
  target="${LAST_APPLIED:-}"
  [[ -n "$target" ]] || return 1

  # Exact path match
  for i in "${!FILES[@]}"; do
    [[ "${FILES[$i]}" == "$target" ]] || continue
    SEL="$i"
    return 0
  done

  # Fallback: unique basename match
  base="$(basename -- "$target")"
  for i in "${!FILES[@]}"; do
    [[ "$(basename -- "${FILES[$i]}")" == "$base" ]] || continue
    match="$i"
    hits=$(( hits + 1 ))
  done

  if (( hits == 1 )); then
    SEL="$match"
    return 0
  fi

  return 1
}

# ---------- persistence ----------
save_state() {
  mkdir -p -- "$CONFIG_DIR"
  {
    printf 'WALL_DIR=%q\n' "$WALL_DIR"
    printf 'RECURSIVE=%q\n' "$RECURSIVE"
    printf 'BACKEND=%q\n' "$BACKEND"
    printf 'DISPLAY_TARGET=%q\n' "$DISPLAY_TARGET"
    printf 'SWWW_RESIZE=%q\n' "$SWWW_RESIZE"
    printf 'SWWW_TRANSITION_TYPE=%q\n' "$SWWW_TRANSITION_TYPE"
    printf 'SWWW_TRANSITION_DURATION=%q\n' "$SWWW_TRANSITION_DURATION"
    printf 'SWWW_TRANSITION_FPS=%q\n' "$SWWW_TRANSITION_FPS"
    printf 'SWWW_FILTER=%q\n' "$SWWW_FILTER"
    printf 'HYPERPAPER_MODE=%q\n' "$HYPERPAPER_MODE"
    printf 'LAST_SEL=%q\n' "${LAST_SEL:-0}"
    printf 'LAST_FOCUS=%q\n' "${LAST_FOCUS:-}"
    printf 'LAST_APPLIED=%q\n' "${LAST_APPLIED:-}"
  } > "${STATE_FILE}.tmp.$$"
  mv -f -- "${STATE_FILE}.tmp.$$" "$STATE_FILE"
}

load_state() {
  if [[ -f "$STATE_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$STATE_FILE" || true
  fi

  [[ -d "$WALL_DIR" ]] || WALL_DIR="$DEFAULT_WALL_DIR"
  [[ "$RECURSIVE" =~ ^[01]$ ]] || RECURSIVE=1
  [[ "$BACKEND" == "swww" || "$BACKEND" == "hyprpaper" ]] || BACKEND="swww"

  # QoL: never restore previous filter on startup
  FILTER_QUERY=""

  [[ "${LAST_SEL:-0}" =~ ^[0-9]+$ ]] || LAST_SEL=0
  : "${LAST_FOCUS:=}"
  : "${LAST_APPLIED:=}"

  # scrub broken older state that may have literal wrapping quotes
  HYPERPAPER_MODE="${HYPERPAPER_MODE%\"}"; HYPERPAPER_MODE="${HYPERPAPER_MODE#\"}"
  LAST_FOCUS="${LAST_FOCUS%\"}"; LAST_FOCUS="${LAST_FOCUS#\"}"
  LAST_APPLIED="${LAST_APPLIED%\"}"; LAST_APPLIED="${LAST_APPLIED#\"}"
}

# ---------- scan / filter ----------
scan_wallpapers() {
  local -a find_cmd=()
  ALL_FILES=()
  HASH_CACHE=()

  if [[ ! -d "$WALL_DIR" ]]; then
    msg "Folder not found: $WALL_DIR"
    FILES=()
    SEL=0
    return 1
  fi

  find_cmd=(find "$WALL_DIR")
  if (( RECURSIVE == 1 )); then
    find_cmd+=(-type f)
  else
    find_cmd+=(-maxdepth 1 -type f)
  fi

  find_cmd+=(
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o
       -iname '*.bmp' -o -iname '*.gif' -o -iname '*.tif' -o -iname '*.tiff' -o
       -iname '*.avif' -o -iname '*.jxl' \)
    -print0
  )

  if (( WALLPICKER_SORT_SCAN == 1 )); then
    if mapfile -d '' -t ALL_FILES < <("${find_cmd[@]}" 2>/dev/null | sort -z); then :; else ALL_FILES=(); fi
  else
    if mapfile -d '' -t ALL_FILES < <("${find_cmd[@]}" 2>/dev/null); then :; else ALL_FILES=(); fi
  fi

  refresh_display_choices
  build_filtered
  msg "Found ${#ALL_FILES[@]} wallpapers"
  return 0
}

build_filtered() {
  local q p b d
  FILES=()
  q="$(normalize_query "$FILTER_QUERY")"
  q="${q,,}"
  if [[ -z "$q" ]]; then
    FILES=("${ALL_FILES[@]}")
  else
    for p in "${ALL_FILES[@]}"; do
      b="$(basename -- "$p")"
      d="$(dirname -- "$p")"
      if [[ "${b,,}" == *"$q"* || "${d,,}" == *"$q"* ]]; then
        FILES+=("$p")
      fi
    done
  fi

  if (( ${#FILES[@]} == 0 )); then
    SEL=0
    return 0
  fi

  SEL="$(clamp_int "$SEL" 0 "$(( ${#FILES[@]} - 1 ))")"
}

refresh_action() {
  # QoL: refresh clears active find filter and rebuilds full list
  FILTER_QUERY=""
  scan_wallpapers || true
  if (( RESUME_LAST == 1 )); then
    if [[ -n "${START_AT}" ]]; then
      SEL=$(( START_AT - 1 ))
    else
      resume_focus_last || true
    fi
    update_focus_state || true
  fi
  if (( ${#FILES[@]} > 0 )); then
    SEL="$(clamp_int "$SEL" 0 "$(( ${#FILES[@]} - 1 ))")"
  else
    SEL=0
  fi
  save_state
  NEED_FULL_REDRAW=1
  msg "Refreshed list"
}

# ---------- terminal / UI ----------
tty_raw_on() {
  if [[ -z "$TTY_STTY_SAVED" ]]; then
    TTY_STTY_SAVED="$(stty -g 2>/dev/null || true)"
  fi
  stty -echo -icanon time 0 min 1 2>/dev/null || true
}

tty_raw_off() {
  if [[ -n "$TTY_STTY_SAVED" ]]; then
    stty "$TTY_STTY_SAVED" 2>/dev/null || true
  else
    stty sane 2>/dev/null || true
  fi
}

sixel_mode_enter() { printf '\e[?80l'; }
sixel_mode_leave() { printf '\e[?80h'; }

ui_enter() {
  if [[ "${WALLPICKER_ALT_SCREEN}" == "1" ]]; then printf '\e[?1049h'; fi
  printf '\e[?25l'
  printf '\e[2J\e[H'
  if [[ "${PREVIEW_MODE}" == "sixel" ]]; then sixel_mode_enter; fi
  if [[ "${PREVIEW_MODE}" == "kitty" ]]; then kitty_clear_images; fi
  mouse_enable
  tty_raw_on
  UI_ACTIVE=1
}

ui_leave() {
  if (( UI_ACTIVE == 0 )); then return 0; fi
  tty_raw_off
  mouse_disable
  if [[ "${PREVIEW_MODE}" == "kitty" ]]; then kitty_clear_images; fi
  if [[ "${PREVIEW_MODE}" == "sixel" ]]; then sixel_mode_leave; fi
  printf '\e[0m'
  printf '\e[?25h'
  if [[ "${WALLPICKER_ALT_SCREEN}" == "1" ]]; then printf '\e[?1049l'; fi
  UI_ACTIVE=0
  return 0
}

ui_clear() { printf '\e[2J\e[H'; }
ui_goto() { printf '\e[%d;%dH' "$1" "$2"; }
ui_color_reset() { printf '\e[0m'; }
ui_dim() { printf '\e[2m'; }
ui_rev() { printf '\e[7m'; }
ui_bold() { printf '\e[1m'; }
ui_clear_line() { printf '\e[2K'; }

loading_spinner_char() {
  local chars="|/-\\"
  local idx=$(( LOADING_SPINNER_IDX % 4 ))
  printf '%s' "${chars:idx:1}"
  LOADING_SPINNER_IDX=$(( (LOADING_SPINNER_IDX + 1) % 4 ))
}

draw_loading_screen() {
  local title="${1:-Loading...}" detail="${2:-Please wait...}"
  local cols lines mid row2 row3 width
  cols="$(term_cols)"
  lines="$(term_lines)"

  ui_clear

  mid=$(( lines / 2 ))
  (( mid < 3 )) && mid=3
  row2=$(( mid - 1 ))
  row3=$mid

  width=$(( cols - 4 ))
  (( width < 1 )) && width=1

  ui_goto "$row2" 3; ui_clear_line; ui_bold
  printf '%-*.*s' "$width" "$width" "$(sanitize_text "$title")"
  ui_color_reset

  ui_goto "$row3" 3; ui_clear_line; ui_dim
  printf '%-*.*s' "$width" "$width" "$(sanitize_text "$detail")"
  ui_color_reset
}

draw_page_cache_progress() {
  local done="$1" total="$2" cols row1 row2 width spin pct barw fill empty bar
  cols="$(term_cols)"
  width=$(( cols - 4 ))
  (( width < 1 )) && width=1

  if (( total > 0 )); then
    pct=$(( done * 100 / total ))
  else
    pct=100
  fi

  spin="$(loading_spinner_char)"
  msg "Caching previews for page... ${done}/${total} (${pct}%)"
  draw_status_bars

  row1=$(( TOP_LINES + 2 ))
  row2=$(( TOP_LINES + 3 ))

  ui_goto "$row1" 3; ui_clear_line; ui_dim
  printf '%-*.*s' "$width" "$width" " ${spin} Loading previews for visible page... ${done}/${total} (${pct}%) "
  ui_color_reset

  barw=$(( cols - 10 ))
  (( barw < 10 )) && barw=10
  fill=$(( barw * pct / 100 ))
  (( fill < 0 )) && fill=0
  (( fill > barw )) && fill=barw
  empty=$(( barw - fill ))

  printf -v bar '%*s' "$fill" ''
  bar="${bar// /#}"
  if (( empty > 0 )); then
    local rest
    printf -v rest '%*s' "$empty" ''
    bar+="${rest// /-}"
  fi

  ui_goto "$row2" 3; ui_clear_line; ui_dim
  printf '[%s]' "$bar"
  ui_color_reset
}

calc_grid() {
  local cols lines usable_w usable_h step_w step_h
  cols="$(term_cols)"
  lines="$(term_lines)"

  usable_w=$(( cols - 2 ))
  usable_h=$(( lines - TOP_LINES - BOTTOM_LINES ))
  (( usable_w < 1 )) && usable_w=1
  (( usable_h < 1 )) && usable_h=1

  step_w=$(( CELL_W + GAP_W ))
  step_h=$(( CELL_H + GAP_H ))
  (( step_w < 1 )) && step_w=1
  (( step_h < 1 )) && step_h=1

  GRID_COLS=$(( usable_w / step_w ))
  GRID_ROWS=$(( usable_h / step_h ))
  (( GRID_COLS < 1 )) && GRID_COLS=1
  (( GRID_ROWS < 1 )) && GRID_ROWS=1

  PAGE_SIZE=$(( GRID_COLS * GRID_ROWS ))
  (( PAGE_SIZE < 1 )) && PAGE_SIZE=1

  return 0
}

page_start_for_sel() {
  if (( PAGE_SIZE < 1 )); then
    printf '0'
  else
    printf '%d' $(( (SEL / PAGE_SIZE) * PAGE_SIZE ))
  fi
}

render_tile_x() { printf '%d' $(( 1 + $1 * (CELL_W + GAP_W) )); }
render_tile_y() { printf '%d' $(( TOP_LINES + 1 + $1 * (CELL_H + GAP_H) )); }

draw_status_bars() {
  local cols selected_idx status_tail
  cols="$(term_cols)"
  if (( ${#FILES[@]} > 0 )); then selected_idx=$(( SEL + 1 )); else selected_idx=0; fi

  ui_goto 1 1; ui_clear_line; ui_bold
  printf '%-*.*s' "$cols" "$cols"     " ${APP_NAME} backend=${BACKEND} display=${DISPLAY_TARGET} encoder=${SIXEL_ENCODER_LABEL} "
  ui_color_reset

  ui_goto 2 1; ui_clear_line
  printf '%-*.*s' "$cols" "$cols"     " dir=$(short_path "$WALL_DIR" 68) recursive=${RECURSIVE} find='$(sanitize_text "$FILTER_QUERY")' "

  ui_goto 3 1; ui_clear_line; ui_dim
  printf '%-*.*s' "$cols" "$cols"     " swww: resize=${SWWW_RESIZE} trans=${SWWW_TRANSITION_TYPE} dur=${SWWW_TRANSITION_DURATION}s fps=${SWWW_TRANSITION_FPS} interp=${SWWW_FILTER} | hyprpaper: ${HYPERPAPER_MODE} "
  ui_color_reset

  status_tail="$(sanitize_text "$STATUS_MSG")"
  if [[ -n "$LAST_ENCODER_ERR" && ( "${WALLPICKER_DEBUG}" == "1" || "${PREVIEW_MODE}" == "kitty" ) ]]; then
    status_tail+=" | encerr=$(sanitize_text "$LAST_ENCODER_ERR")"
  fi

  ui_goto 4 1; ui_clear_line; ui_dim
  printf '%-*.*s' "$cols" "$cols"     " selected=${selected_idx} status=${status_tail} "
  ui_color_reset
}

draw_empty_grid() {
  local cols lines width mid row
  cols="$(term_cols)"
  lines="$(term_lines)"
  width=$(( cols - 4 )); (( width < 1 )) && width=1
  mid=$(( (TOP_LINES + lines - BOTTOM_LINES) / 2 ))

  ui_goto "$mid" 3; ui_clear_line; ui_dim
  printf '%-*.*s' "$width" "$width" "No wallpapers found. Press R to refresh or q to quit."
  ui_color_reset

  row=$(( lines - 2 ))
  ui_goto "$row" 1; ui_clear_line; ui_dim
  printf '%-*.*s' "$cols" "$cols" "keys: q quit | R refresh | f find | b backend | m display | o open dir"
  ui_color_reset
}

clear_tile_region() {
  local gr="$1" gc="$2" x y r
  x="$(render_tile_x "$gc")"
  y="$(render_tile_y "$gr")"
  for (( r = 0; r < CELL_H; r++ )); do
    ui_goto $(( y + r )) "$x"
    printf '%-*s' "$CELL_W" ''
  done
}

draw_tile() {
  local abs_idx="$1" page_start="$2"
  local rel gr gc x y p assets png six base name_line idx_line label_row1 label_row2
  local -a thumb_paths=()

  rel=$(( abs_idx - page_start ))
  gr=$(( rel / GRID_COLS ))
  gc=$(( rel % GRID_COLS ))
  x="$(render_tile_x "$gc")"
  y="$(render_tile_y "$gr")"

  p="${FILES[$abs_idx]}"
  base="$(basename -- "$p")"
  name_line="$(pad_trunc "$(printf '%02d. %s' "$((abs_idx + 1))" "$base")" "$CELL_W")"
  idx_line="$(pad_trunc "[$((abs_idx + 1))]" "$CELL_W")"

  # Put labels directly under the preview area.
  label_row1=$(( y + THUMB_CH_H ))
  label_row2=$(( y + THUMB_CH_H + 1 ))

  clear_tile_region "$gr" "$gc"

  assets=""
  six=""
  if assets="$(ensure_thumb_assets "$p" 2>>"$DEBUG_LOG")"; then
    mapfile -t thumb_paths <<< "$assets"
    png="${thumb_paths[0]:-}"
    six="${thumb_paths[1]:-}"
  fi

  ui_goto "$y" "$x"
  if [[ "${WALLPICKER_NO_SIXEL}" == "1" ]]; then
    ui_dim
    printf '%-*.*s' "$THUMB_CH_W" "$THUMB_CH_W" "[preview disabled]"
    ui_color_reset
  elif [[ "${PREVIEW_MODE}" == "kitty" ]]; then
    if [[ -n "${png:-}" && -s "${png:-}" ]]; then
      kitty_draw_png_at "$png" "$x" "$y" || {
        ui_dim
        printf '%-*.*s' "$THUMB_CH_W" "$THUMB_CH_W" "[no preview]"
        ui_color_reset
      }
    else
      ui_dim
      printf '%-*.*s' "$THUMB_CH_W" "$THUMB_CH_W" "[no preview]"
      ui_color_reset
    fi
  elif [[ -n "$six" && -s "$six" ]]; then
    cat -- "$six" 2>/dev/null || true
  else
    ui_dim
    printf '%-*.*s' "$THUMB_CH_W" "$THUMB_CH_W" "[no preview]"
    ui_color_reset
  fi

  ui_goto "$label_row1" "$x"
  if (( abs_idx == SEL )); then
    ui_rev
    printf '%-*.*s' "$CELL_W" "$CELL_W" "$name_line"
    ui_color_reset
  else
    printf '%-*.*s' "$CELL_W" "$CELL_W" "$name_line"
  fi

  ui_goto "$label_row2" "$x"
  ui_dim
  printf '%-*.*s' "$CELL_W" "$CELL_W" "$idx_line"
  ui_color_reset
}

draw_help() {
  local cols lines row1 row2
  cols="$(term_cols)"
  lines="$(term_lines)"
  row1=$(( lines - 2 ))
  row2=$(( lines - 1 ))

  ui_goto "$row1" 1; ui_clear_line; ui_dim
  printf '%-*.*s' "$cols" "$cols"     " arrows/hjkl move | wheel scroll | mouse click apply | SPACE apply | r random | f find | c clear | R refresh "
  ui_color_reset

  ui_goto "$row2" 1; ui_clear_line; ui_dim
  printf '%-*.*s' "$cols" "$cols"     " q quit | D dir | n recurse | b backend | m display | z resize | t trans | d dur | p fps | i interp "
  ui_color_reset
}

draw_full_ui() {
  local page_start page_end last i
  calc_grid
  if [[ "${PREVIEW_MODE}" == "kitty" ]]; then kitty_clear_images; fi

  if [[ \"${PREVIEW_MODE}\" == \"kitty\" ]]; then kitty_clear_images; fi
  ui_clear
  draw_status_bars

  if (( ${#FILES[@]} == 0 )); then
    draw_empty_grid
    draw_help
    LAST_GRID_COLS=$GRID_COLS
    LAST_GRID_ROWS=$GRID_ROWS
    NEED_FULL_REDRAW=0
    return 0
  fi

  page_start="$(page_start_for_sel)"
  page_end=$(( page_start + PAGE_SIZE - 1 ))
  last=$(( ${#FILES[@]} - 1 ))
  (( page_end > last )) && page_end=$last


  # Pre-generate previews for visible page to reduce per-tile lag/flicker (especially GIFs).
  # Disabled by default for faster startup; enable with WALLPICKER_PREWARM_VISIBLE_PAGE=1.
  if (( WALLPICKER_PREWARM_VISIBLE_PAGE == 1 )); then
    local pre_i pre_file pre_png pre_six need_gen warm_total warm_done
    warm_total=0
    warm_done=0

    for (( pre_i = page_start; pre_i <= page_end; pre_i++ )); do
      pre_file="${FILES[$pre_i]}"
      pre_png="$(thumb_png_path "$pre_file")"
      if [[ "${WALLPICKER_NO_SIXEL}" == "1" ]]; then
        if [[ ! -s "$pre_png" ]]; then
          warm_total=$(( warm_total + 1 ))
        fi
      else
        pre_six="$(thumb_six_path "$pre_file")"
        if [[ ! -s "$pre_png" || ! -s "$pre_six" ]]; then
          warm_total=$(( warm_total + 1 ))
        fi
      fi
    done

    if (( warm_total > 0 )); then
      draw_page_cache_progress 0 "$warm_total"
    fi

    for (( pre_i = page_start; pre_i <= page_end; pre_i++ )); do
      need_gen=0
      pre_file="${FILES[$pre_i]}"
      pre_png="$(thumb_png_path "$pre_file")"

      if [[ "${WALLPICKER_NO_SIXEL}" == "1" ]]; then
        [[ -s "$pre_png" ]] || need_gen=1
      else
        pre_six="$(thumb_six_path "$pre_file")"
        [[ -s "$pre_png" && -s "$pre_six" ]] || need_gen=1
      fi

      if (( need_gen == 1 )); then
        ensure_thumb_assets "$pre_file" >/dev/null 2>&1 || true
        warm_done=$(( warm_done + 1 ))
        draw_page_cache_progress "$warm_done" "$warm_total"
      fi
    done

    if (( warm_total > 0 )); then
      # Progress bar/status overlay writes text into the grid area.
      # Fully clear and redraw headers before thumbnails to prevent leftover # artifacts.
      ui_clear
      draw_status_bars
    fi

  fi

  msg "Found ${#ALL_FILES[@]} wallpapers"

  for (( i = page_start; i <= page_end; i++ )); do
    draw_tile "$i" "$page_start"
  done

  draw_help
  LAST_GRID_COLS=$GRID_COLS
  LAST_GRID_ROWS=$GRID_ROWS
  NEED_FULL_REDRAW=0
}

redraw_after_navigation() {
  local prev_sel="$1" prev_page new_page
  calc_grid

  new_page="$(page_start_for_sel)"
  prev_page=$(( (prev_sel / PAGE_SIZE) * PAGE_SIZE ))

  if (( GRID_COLS != LAST_GRID_COLS || GRID_ROWS != LAST_GRID_ROWS )); then
    NEED_FULL_REDRAW=1
    draw_full_ui
    return 0
  fi

  if (( new_page != prev_page )); then
    NEED_FULL_REDRAW=1
    draw_full_ui
    return 0
  fi

  draw_status_bars
  if (( ${#FILES[@]} > 0 )); then
    if (( prev_sel >= 0 && prev_sel < ${#FILES[@]} )); then
      draw_tile "$prev_sel" "$new_page"
    fi
    if (( SEL >= 0 && SEL < ${#FILES[@]} && SEL != prev_sel )); then
      draw_tile "$SEL" "$new_page"
    fi
  fi

  draw_help
  LAST_GRID_COLS=$GRID_COLS
  LAST_GRID_ROWS=$GRID_ROWS
  NEED_FULL_REDRAW=0
}

# ---------- mouse ----------
mouse_enable() {
  [[ "${WALLPICKER_MOUSE:-1}" == "1" ]] || return 0
  # X10 click + SGR extended coordinates (works in modern terminals)
  printf '\e[?1000h'
  printf '\e[?1006h'
  return 0
}

mouse_disable() {
  # Disable mouse reporting even if not enabled (safe)
  printf '\e[?1006l'
  printf '\e[?1000l'
  return 0
}

mouse_tile_index_at() {
  local row="$1" col="$2"
  local x0 y0 relx rely step_w step_h gc gr offx offy idx page_start

  if (( ${#FILES[@]} == 0 )); then
    return 1
  fi

  # Ensure grid geometry is current.
  calc_grid

  x0="$(render_tile_x 0)"
  y0="$(render_tile_y 0)"

  relx=$(( col - x0 ))
  rely=$(( row - y0 ))
  (( relx < 0 || rely < 0 )) && return 1

  step_w=$(( CELL_W + GAP_W ))
  step_h=$(( CELL_H + GAP_H ))
  (( step_w < 1 )) && step_w=1
  (( step_h < 1 )) && step_h=1

  gc=$(( relx / step_w ))
  gr=$(( rely / step_h ))
  offx=$(( relx % step_w ))
  offy=$(( rely % step_h ))

  (( gc < 0 || gc >= GRID_COLS )) && return 1
  (( gr < 0 || gr >= GRID_ROWS )) && return 1

  # Clickable horizontal region = preview/label width only.
  (( offx >= THUMB_CH_W )) && return 1

  # Clickable vertical region = preview + 2 label rows.
  (( offy > THUMB_CH_H + 2 )) && return 1

  page_start="$(page_start_for_sel)"
  idx=$(( page_start + gr * GRID_COLS + gc ))
  (( idx < 0 || idx >= ${#FILES[@]} )) && return 1

  printf '%d' "$idx"
  return 0
}

handle_mouse_event() {
  local seq="$1"
  local code x y kind btn prev_sel idx
  local re=$'^\e\[<([0-9]+);([0-9]+);([0-9]+)([Mm])$'

  [[ "${WALLPICKER_MOUSE:-1}" == "1" ]] || return 1
  [[ "$seq" =~ $re ]] || return 1

  code="${BASH_REMATCH[1]}"
  x="${BASH_REMATCH[2]}"
  y="${BASH_REMATCH[3]}"
  kind="${BASH_REMATCH[4]}"

  # Ignore releases; treat as handled so they do not spam key debug.
  [[ "$kind" == "M" ]] || return 0

  # Wheel support optional (default on; set WALLPICKER_MOUSE_WHEEL=0 to disable).
  if (( (code & 64) != 0 )); then
    if [[ "${WALLPICKER_MOUSE_WHEEL:-1}" != "1" ]]; then
      return 0
    fi

    prev_sel="$SEL"
    case "$code" in
      64) move_sel_grid 0 -1 ;;
      65) move_sel_grid 0 1 ;;
      *) return 0 ;;
    esac

    if (( SEL != prev_sel )); then
      redraw_after_navigation "$prev_sel"
    else
      draw_status_bars
    fi
    return 0
  fi

  # Ignore drag/motion reports
  if (( (code & 32) != 0 )); then
    return 0
  fi

  # Left click only
  btn=$(( code & 3 ))
  (( btn == 0 )) || return 0

  idx="$(mouse_tile_index_at "$y" "$x" || true)"
  [[ -n "$idx" ]] || return 0

  prev_sel="$SEL"
  SEL="$idx"

  # Mouse click apply QoL:
  # - avoid full redraw flash on same-page clicks
  # - show status feedback first
  if (( SEL != prev_sel )); then
    redraw_after_navigation "$prev_sel"
  else
    msg "Applying selected wallpaper..."
    draw_status_bars
  fi

  apply_selected || true
  drain_pending_keys 256 || true
  draw_status_bars
  return 0
}

# ---------- input ----------
read_key() {
  local key c1 c2 rest ch i
  if ! IFS= read -rsn1 -t "${WALLPICKER_INPUT_POLL_S}" key; then
    return 1
  fi

  if [[ "$key" != $'\x1b' ]]; then
    printf '%s' "$key"
    return 0
  fi

  # Read a little more after ESC to classify CSI/mouse safely.
  rest=""
  if ! IFS= read -rsn1 -t 0.03 c1; then
    # Bare ESC
    printf '%s' "$key"
    return 0
  fi
  rest+="$c1"

  if [[ "$c1" != "[" ]]; then
    # Not CSI; return whatever arrived.
    printf '%s' "$key$rest"
    return 0
  fi

  if ! IFS= read -rsn1 -t 0.03 c2; then
    # Incomplete CSI, drop it (prevents parser lockups on partial mouse seq).
    return 0
  fi
  rest+="$c2"

  # SGR mouse sequence: ESC [ < Cb ; Cx ; Cy (M|m)
  if [[ "$c2" == "<" ]]; then
    for (( i = 0; i < 96; i++ )); do
      if ! IFS= read -rsn1 -t 0.03 ch; then
        # Incomplete mouse sequence: drop it.
        return 0
      fi
      rest+="$ch"
      if [[ "$ch" == "M" || "$ch" == "m" ]]; then
        printf '%s' "$key$rest"
        return 0
      fi
    done
    # Too long / malformed mouse sequence: drop it.
    return 0
  fi

  # Generic CSI key sequence: collect a small tail.
  for (( i = 0; i < 12; i++ )); do
    if ! IFS= read -rsn1 -t 0.005 ch; then
      break
    fi
    rest+="$ch"
    case "$ch" in
      '~'|A|B|C|D|H|F|P|Q|R|S) break ;;
    esac
  done

  printf '%s' "$key$rest"
  return 0
}

prompt_line() {
  local prompt="$1" current="${2:-}" input lines
  lines="$(term_lines)"

  tty_raw_off
  printf '\e[?25h' >&2
  ui_goto "$lines" 1 >&2
  ui_clear_line >&2
  printf '%s' "$prompt" >&2
  IFS= read -r input || input="$current"
  input="${input//$'\r'/}"
  input="${input#"${input%%[![:space:]]*}"}"
  input="${input%"${input##*[![:space:]]}"}"
  printf '\e[?25l' >&2
  tty_raw_on
  printf '%s' "$input"
}

move_sel_delta() {
  local delta="$1"
  if (( ${#FILES[@]} == 0 )); then return 0; fi
  SEL=$(( SEL + delta ))
  SEL="$(clamp_int "$SEL" 0 "$(( ${#FILES[@]} - 1 ))")"
  update_focus_state || true
}

move_sel_grid() {
  local dx="$1" dy="$2" new
  if (( ${#FILES[@]} == 0 )); then return 0; fi
  new=$(( SEL + dx + dy * GRID_COLS ))
  SEL="$(clamp_int "$new" 0 "$(( ${#FILES[@]} - 1 ))")"
  update_focus_state || true
}

cycle_backend() {
  local prev="$BACKEND"
  if [[ "$BACKEND" == "swww" ]]; then BACKEND="hyprpaper"; else BACKEND="swww"; fi
  save_state

  if [[ "$prev" == "hyprpaper" && "$BACKEND" == "swww" ]]; then
    takeover_hyprpaper_to_swww
  fi

  msg "Backend: $BACKEND"
  NEED_FULL_REDRAW=1
}

cycle_display() {
  local i next
  (( ${#DISPLAY_CHOICES[@]} == 0 )) && refresh_display_choices
  for i in "${!DISPLAY_CHOICES[@]}"; do
    if [[ "${DISPLAY_CHOICES[$i]}" == "$DISPLAY_TARGET" ]]; then
      next=$(( (i + 1) % ${#DISPLAY_CHOICES[@]} ))
      DISPLAY_TARGET="${DISPLAY_CHOICES[$next]}"
      save_state
      msg "Display: $DISPLAY_TARGET"
      NEED_FULL_REDRAW=1
      return 0
    fi
  done
  DISPLAY_TARGET="All displays"
  save_state
  msg "Display: $DISPLAY_TARGET"
  NEED_FULL_REDRAW=1
}

cycle_swww_resize() {
  case "$SWWW_RESIZE" in
    crop) SWWW_RESIZE="fit" ;;
    fit) SWWW_RESIZE="stretch" ;;
    stretch) SWWW_RESIZE="no" ;;
    no) SWWW_RESIZE="crop" ;;
    *) SWWW_RESIZE="crop" ;;
  esac
  save_state
  msg "swww resize: $SWWW_RESIZE"
  draw_status_bars
}

cycle_swww_transition() {
  case "$SWWW_TRANSITION_TYPE" in
    fade) SWWW_TRANSITION_TYPE="grow" ;;
    grow) SWWW_TRANSITION_TYPE="outer" ;;
    outer) SWWW_TRANSITION_TYPE="any" ;;
    any) SWWW_TRANSITION_TYPE="random" ;;
    random) SWWW_TRANSITION_TYPE="fade" ;;
    *) SWWW_TRANSITION_TYPE="grow" ;;
  esac
  save_state
  msg "swww transition: $SWWW_TRANSITION_TYPE"
  draw_status_bars
}

cycle_swww_duration() {
  step_duration_cycle
  save_state
  msg "swww duration: ${SWWW_TRANSITION_DURATION}s"
  draw_status_bars
}

cycle_swww_fps() {
  step_fps_cycle
  save_state
  msg "swww fps: ${SWWW_TRANSITION_FPS}"
  draw_status_bars
}

cycle_swww_interp() {
  case "$SWWW_FILTER" in
    Lanczos3) SWWW_FILTER="Nearest" ;;
    Nearest) SWWW_FILTER="Bilinear" ;;
    Bilinear) SWWW_FILTER="CatmullRom" ;;
    CatmullRom) SWWW_FILTER="Mitchell" ;;
    Mitchell) SWWW_FILTER="Lanczos3" ;;
    *) SWWW_FILTER="Lanczos3" ;;
  esac
  save_state
  msg "swww interp: $SWWW_FILTER"
  draw_status_bars
}

cycle_hyprpaper_mode() {
  case "$HYPERPAPER_MODE" in
    cover) HYPERPAPER_MODE="contain" ;;
    contain) HYPERPAPER_MODE="center" ;;
    center) HYPERPAPER_MODE="cover" ;;
    *) HYPERPAPER_MODE="cover" ;;
  esac
  save_state
  msg "hyprpaper mode: $HYPERPAPER_MODE"
  draw_status_bars
}

random_apply() {
  if (( ${#FILES[@]} == 0 )); then msg "No wallpapers"; return 0; fi
  SEL=$(( RANDOM % ${#FILES[@]} ))
  apply_selected || true
  drain_pending_keys   # avoid key-repeat spamming heavy wallpaper transitions
}

open_dir() {
  if have xdg-open; then
    (nohup xdg-open "$WALL_DIR" >/dev/null 2>&1 &) || true
    msg "Opened directory"
  else
    msg "xdg-open not found"
  fi
  draw_status_bars
}

do_find_prompt() {
  local v
  v="$(prompt_line "Find (empty clears): " "$FILTER_QUERY")"
  FILTER_QUERY="$(normalize_query "$v")"
  build_filtered
  if (( ${#FILES[@]} > 0 )); then SEL=0; fi
  msg "Find updated"
  NEED_FULL_REDRAW=1
}

clear_find() {
  FILTER_QUERY=""
  build_filtered
  if (( ${#FILES[@]} > 0 )); then SEL=0; fi
  msg "Find cleared"
  NEED_FULL_REDRAW=1
}

purge_preview_cache() {
  find "$THUMB_CACHE_DIR" -maxdepth 1 -type f \( -name '*.six' -o -name '*.png' \) -delete 2>/dev/null || true
  msg "Cleared preview cache"
  NEED_FULL_REDRAW=1
}

do_dir_prompt() {
  local v
  v="$(prompt_line "Wallpaper directory: " "$WALL_DIR")"

  # trim leading/trailing whitespace
  v="${v#"${v%%[![:space:]]*}"}"
  v="${v%"${v##*[![:space:]]}"}"

  if [[ -z "$v" ]]; then
    msg "Directory unchanged"
    draw_status_bars
    return 0
  fi

  case "$v" in
    "~") v="$HOME" ;;
    \~/*) v="$HOME/${v#~/}" ;;
  esac

  if [[ ! -d "$v" ]]; then
    msg "Not a directory: $(sanitize_text "$v")"
    draw_status_bars
    return 0
  fi

  WALL_DIR="$v"
  FILTER_QUERY=""
  SEL=0
  scan_wallpapers || true
  save_state
  NEED_FULL_REDRAW=1
  msg "Directory: $(short_path "$WALL_DIR" 70)"
  return 0
}

toggle_recursive() {
  if (( RECURSIVE )); then
    RECURSIVE=0
  else
    RECURSIVE=1
  fi

  FILTER_QUERY=""
  SEL=0
  scan_wallpapers || true
  save_state
  NEED_FULL_REDRAW=1
  msg "Recursive: ${RECURSIVE}"
  return 0
}

# ---------- traps ----------
cleanup() {
  update_focus_state || true
  save_state || true
  ui_leave || true
  if [[ "${CLEAR_ON_EXIT:-0}" == "1" ]]; then
    printf '\e[2J\e[H'
  fi
}
trap cleanup EXIT INT TERM HUP

on_winch() {
  RESIZE_PENDING=1
  NEED_FULL_REDRAW=1
}
trap on_winch WINCH

err_trap() {
  local line="$1"
  local rc=$?
  (( rc != 0 )) || return 0
  tty_raw_off
  printf '\nwallpicker.sh crashed at line %s (exit %s)\n' "$line" "$rc" >&2
}
trap 'err_trap "$LINENO"' ERR

# ---------- args ----------
usage() {
  cat <<'USAGEEOF'
Usage: wallpicker.sh [options]

Options:
  -d, --dir PATH          Wallpaper directory (default: ~/Pictures/wallpapers)
  -n, --non-recursive     Disable recursive scanning
  -r, --recursive         Enable recursive scanning
  -b, --backend NAME      swww | hyprpaper
  -o, --output NAME       Target display name or "All displays"
  --no-sixel              Disable image previews (UI only)
  --alt-screen            Use alternate screen buffer
  --force-encoder NAME    chafa | img2sixel | magick | kitty
  -h, --help              Show help
  --resume                Start at last saved selection
  --start-at N            Start at selection index N (1-based)

USAGEEOF
}

parse_args() {
  while (($#)); do
    case "$1" in
      -d|--dir)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        WALL_DIR="$2"
        shift 2
        ;;
      -n|--non-recursive)
        RECURSIVE=0
        shift
        ;;
      -r|--recursive)
        RECURSIVE=1
        shift
        ;;
      -b|--backend)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        BACKEND="$2"
        shift 2
        ;;
      -o|--output)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        DISPLAY_TARGET="$2"
        shift 2
        ;;
      --no-sixel)
        WALLPICKER_NO_SIXEL=1
        shift
        ;;
      --alt-screen)
        WALLPICKER_ALT_SCREEN=1
        shift
        ;;
      --force-encoder)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        WALLPICKER_FORCE_ENCODER="$2"
        shift 2
        ;;
      --resume)
        RESUME_LAST=1
        shift
        ;;
      --start-at)
        [[ $# -ge 2 ]] || die "Missing value for $1"
        [[ "$2" =~ ^[0-9]+$ ]] || die "--start-at expects an integer (1-based)"
        START_AT="$2"
        RESUME_LAST=1
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
  done
}

# ---------- main ----------
main() {
  local key prev_sel moved

  : > "$DEBUG_LOG"
  load_state
  parse_args "$@"

  [[ "$BACKEND" == "swww" || "$BACKEND" == "hyprpaper" ]] || BACKEND="swww"

  # Start position policy (default: start at 1st item)
  if [[ -n "${START_AT}" ]]; then
    # user supplies 1-based index
    SEL=$(( START_AT - 1 ))
  elif (( RESUME_LAST == 1 )); then
    SEL="${LAST_SEL:-0}"
  else
    SEL=0
  fi

  preflight_tty_checks
  check_runtime_requirements || exit 1

  ui_enter
  draw_loading_screen "wallpicker" "Scanning wallpapers and loading state..."
  scan_wallpapers || true
  save_state
  draw_loading_screen "wallpicker" "Preparing first page..."
  debug "term=${TERM:-unset} encoder=${SIXEL_ENCODER_LABEL} files=${#FILES[@]}"
  NEED_FULL_REDRAW=1

  TERM_COLS_LAST="$(term_cols)"
  TERM_LINES_LAST="$(term_lines)"

  while (( RUNNING == 1 )); do
    detect_term_resize || true
    if (( RESIZE_PENDING == 1 )); then
      RESIZE_PENDING=0
      if [[ "${WALLPICKER_RESIZE_RESCAN}" == "1" ]]; then
        refresh_action
      else
        NEED_FULL_REDRAW=1
      fi
    fi

    if (( NEED_FULL_REDRAW == 1 )); then
      draw_full_ui
    fi

    key="$(read_key || true)"
    [[ -n "${key:-}" ]] || continue

    if handle_mouse_event "$key"; then
      continue
    fi

    prev_sel="$SEL"
    moved=0

    case "$key" in
      q|Q)
        CLEAR_ON_EXIT=1
        RUNNING=0
        ;;
      ' ')
        apply_selected || true
        drain_pending_keys
        draw_status_bars
        ;;
      $'\n'|$'\r')
        # Keep support but do not advertise it because terminal may not emit it reliably.
        apply_selected || true
        drain_pending_keys
        draw_status_bars
        ;;
      $'\e[A'|k)
        move_sel_grid 0 -1
        moved=1
        ;;
      $'\e[B'|j)
        move_sel_grid 0 1
        moved=1
        ;;
      $'\e[C'|l)
        move_sel_delta 1
        moved=1
        ;;
      $'\e[D'|h)
        move_sel_delta -1
        moved=1
        ;;
      r)
        random_apply
        NEED_FULL_REDRAW=1
        ;;
      f)
        do_find_prompt
        ;;
      c)
        clear_find
        ;;
      R)
        refresh_action
        ;;
      D)
        do_dir_prompt
        ;;
      n)
        toggle_recursive
        ;;
      b)
        cycle_backend
        ;;
      m)
        refresh_display_choices
        cycle_display
        ;;
      z)
        cycle_swww_resize
        ;;
      t)
        cycle_swww_transition
        ;;
      d)
        cycle_swww_duration
        ;;
      p)
        cycle_swww_fps
        ;;
      i)
        cycle_swww_interp
        ;;
      P)
        cycle_hyprpaper_mode
        ;;
      o)
        open_dir
        ;;
      x)
        purge_preview_cache
        ;;
      *)
        msg "Key: $(printf '%q' "$key")"
        draw_status_bars
        ;;
    esac

    if (( moved == 1 )); then
      if (( SEL != prev_sel )); then
        redraw_after_navigation "$prev_sel"
      else
        draw_status_bars
      fi
    fi
  done

  return 0
}

main "$@"
