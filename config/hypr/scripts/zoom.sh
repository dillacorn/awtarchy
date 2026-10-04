#!/usr/bin/env bash
# github.com/dillacorn/awtarchy/tree/main/config/hypr/scripts
# ~/.config/hypr/scripts/zoom.sh
# 
# Hyprland zoom helper with easy customization

set -euo pipefail

# ===== Defaults (override via env or ~/.config/hypr/zoom.conf) =====
# Stepping mode: multiplicative ("mul") or additive ("add")
ZOOM_MODE="${ZOOM_MODE:-mul}"
# Normal step (mul: percent like "10%"; add: absolute "0.10" or percent-of-current "10%")
ZOOM_STEP="${ZOOM_STEP:-10%}"
# Fast step used by "++" and "--"
ZOOM_FAST_STEP="${ZOOM_FAST_STEP:-25%}"
# Min and max factors
ZOOM_MIN="${ZOOM_MIN:-1.0}"
ZOOM_MAX="${ZOOM_MAX:-6.0}"
# Reset target
DEFAULT_FACTOR="${DEFAULT_FACTOR:-1.0}"
# Print precision
PRECISION="${PRECISION:-3}"

# Notifications master switch and per-action toggles
# Defaults: zoom off, rigid on, reset off
NOTIFY_ENABLED="${NOTIFY_ENABLED:-true}"
NOTIFY_ZOOM="${NOTIFY_ZOOM:-false}"
NOTIFY_RIGID="${NOTIFY_RIGID:-true}"
NOTIFY_RESET="${NOTIFY_RESET:-false}"

# Logging
LOG_ENABLE="${LOG_ENABLE:-true}"

# Optional per-user config
CFG="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/zoom.conf"
# shellcheck source=/dev/null
[ -f "$CFG" ] && . "$CFG"

# ===== Binaries =====
HC="$(command -v hyprctl || echo /usr/bin/hyprctl)"
JQ="$(command -v jq || echo /usr/bin/jq)"
AWK="$(command -v awk || echo /usr/bin/awk)"
NOTIFY_BIN="$(command -v notify-send || true)"

# ===== Log =====
LOG="${XDG_STATE_HOME:-$HOME/.local/state}/hypr-zoom.log"
mkdir -p "$(dirname "$LOG")"
log() { [ "$LOG_ENABLE" = "true" ] || return 0; printf '%s %s\n' "$(date +'%F %T')" "$*" >>"$LOG" || true; }

# ===== Hyprland option keys =====
if "$HC" getoption 'cursor:zoom_factor' -j >/dev/null 2>&1; then
  KEY_FACTOR='cursor:zoom_factor'
  KEY_RIGID='cursor:zoom_rigid'
elif "$HC" getoption 'misc:cursor_zoom_factor' -j >/dev/null 2>&1; then
  KEY_FACTOR='misc:cursor_zoom_factor'
  KEY_RIGID='misc:cursor_zoom_rigid'
else
  echo "Zoom options not found"; exit 1
fi

# ===== Helpers =====
notify() {
  # $1: kind (zoom|rigid|reset), $2: message
  local kind="$1" msg="$2"
  [ -n "$NOTIFY_BIN" ] || return 0
  [ "$NOTIFY_ENABLED" = "true" ] || return 0
  case "$kind" in
    zoom)  [ "$NOTIFY_ZOOM"  = "true" ] || return 0 ;;
    rigid) [ "$NOTIFY_RIGID" = "true" ] || return 0 ;;
    reset) [ "$NOTIFY_RESET" = "true" ] || return 0 ;;
    *) return 0 ;;
  esac
  "$NOTIFY_BIN" -a "Hypr Zoom" "$msg" || true
}

get_factor() {
  "$HC" getoption "$KEY_FACTOR" -j | "$JQ" -r '.float // .int // 1'
}

set_runtime_config() {
  local key="$1" value="$2" expr

  case "$key" in
    cursor:zoom_factor|cursor.zoom_factor)
      expr="hl.config({ cursor = { zoom_factor = ${value} } })"
      ;;
    cursor:zoom_rigid|cursor.zoom_rigid)
      expr="hl.config({ cursor = { zoom_rigid = ${value} } })"
      ;;
    misc:cursor_zoom_factor|misc.cursor_zoom_factor)
      expr="hl.config({ misc = { cursor_zoom_factor = ${value} } })"
      ;;
    misc:cursor_zoom_rigid|misc.cursor_zoom_rigid)
      expr="hl.config({ misc = { cursor_zoom_rigid = ${value} } })"
      ;;
    *)
      printf 'Unsupported Hyprland zoom option: %s\n' "$key" >&2
      return 1
      ;;
  esac

  "$HC" -q eval "$expr"
}

set_factor() {
  local v="$1"
  set_runtime_config "$KEY_FACTOR" "$v" >/dev/null || true
}

get_rigid() {
  "$HC" getoption "$KEY_RIGID" -j 2>/dev/null \
    | "$JQ" -r '
        if .bool? != null then (if .bool then "true" else "false" end)
        elif .int?  != null then (if .int == 1 then "true" else "false" end)
        else "false" end
      ' || echo "false"
}

set_rigid_to() {
  local key="$1" target="$2" state

  [[ "$target" == "true" || "$target" == "false" ]] || return 1
  set_runtime_config "$key" "$target" >/dev/null || return 1
  sleep 0.02
  state="$(get_rigid)"
  [ "$state" = "$target" ]
}

is_percent() { case "$1" in *%) return 0;; *) return 1;; esac; }

strip_percent() {
  # remove a single trailing % if present
  local s="$1"
  s="${s%\%}"
  printf '%s' "$s"
}

clamp() {
  local val="$1" min="$2" max="$3"
  "$AWK" -v v="$val" -v lo="$min" -v hi="$max" 'BEGIN{ if(v<lo)v=lo; if(v>hi)v=hi; print v }'
}

round_to() {
  local val="$1" prec="$2"
  "$AWK" -v v="$val" -v p="$prec" 'BEGIN{ printf "%.*f", p, v }'
}

normalize_percent() {
  # Input: "10%", "0.1", or "10"
  # Output: numeric percent w/o % (e.g. 10 or 12.500000)
  local s="$1"
  if is_percent "$s"; then
    strip_percent "$s"
    return
  fi
  "$AWK" -v s="$s" 'BEGIN{
    if (s ~ /^[0-9]*\.?[0-9]+$/) {
      val = s + 0
      if (val <= 1) printf "%.6f", val * 100.0;
      else          printf "%.6f", val;
    } else {
      printf "10";
    }
  }'
}

next_value() {
  # Args: current step mode direction min max precision
  local cur="$1" step="$2" mode="$3" dir="$4" min="$5" max="$6" prec="$7"

  local step_s="$step"
  local pct abs new
  if [ "$mode" = "mul" ]; then
    pct="$(normalize_percent "$step_s")"
    new="$("$AWK" -v c="$cur" -v p="$pct" -v d="$dir" 'BEGIN{
      p/=100.0;
      if(d>0) printf "%.12f", c*(1.0+p);
      else    printf "%.12f", c/(1.0+p);
    }')"
  else
    if is_percent "$step_s"; then
      pct="$(normalize_percent "$step_s")"
      new="$("$AWK" -v c="$cur" -v p="$pct" -v d="$dir" 'BEGIN{
        p/=100.0;
        if(d>0) printf "%.12f", c + c*p;
        else    printf "%.12f", c - c*p;
      }')"
    else
      abs="$step_s"
      new="$("$AWK" -v c="$cur" -v a="$abs" -v d="$dir" 'BEGIN{
        if(d>0) printf "%.12f", c + a;
        else    printf "%.12f", c - a;
      }')"
    fi
  fi
  new="$(clamp "$new" "$min" "$max")"
  round_to "$new" "$prec"
}

apply_step() {
  # Args: direction(1|-1) step_str mode min max precision
  local dir="$1" step_s="$2" mode="$3" min="$4" max="$5" prec="$6"
  local cur new
  cur="$(get_factor)"
  new="$(next_value "$cur" "$step_s" "$mode" "$dir" "$min" "$max" "$prec")"
  set_factor "$new"
  printf 'zoom_factor: %s -> %s\n' "$(round_to "$cur" "$prec")" "$new"
  log "factor ${cur} -> ${new} (mode=$mode step=$step_s dir=$dir)"
  notify zoom "zoom: $new"
}

# ===== One-shot overrides from extra tokens =====
# Tokens:
#   step:12%   mode:add   bounds:1:6   round:2
#   notify:on|off  notify:zoom:on|off  notify:rigid:on|off  notify:reset:on|off
TEMP_MODE=""
TEMP_STEP=""
TEMP_MIN=""
TEMP_MAX=""
TEMP_PREC=""
TEMP_NOTIFY=""
TEMP_NZ=""
TEMP_NR=""
TEMP_NRES=""

parse_token() {
  case "$1" in
    mode:mul) TEMP_MODE="mul" ;;
    mode:add) TEMP_MODE="add" ;;
    step:*)   TEMP_STEP="${1#step:}" ;;
    bounds:*)
      local v="${1#bounds:}"; TEMP_MIN="${v%%:*}"; TEMP_MAX="${v##*:}"
      ;;
    round:*)  TEMP_PREC="${1#round:}" ;;
    notify:on)  TEMP_NOTIFY="true" ;;
    notify:off) TEMP_NOTIFY="false" ;;
    notify:zoom:on)   TEMP_NZ="true" ;;
    notify:zoom:off)  TEMP_NZ="false" ;;
    notify:rigid:on)  TEMP_NR="true" ;;
    notify:rigid:off) TEMP_NR="false" ;;
    notify:reset:on)  TEMP_NRES="true" ;;
    notify:reset:off) TEMP_NRES="false" ;;
    *) return 1 ;;
  esac
}

# ===== Dispatch =====
arg="${1:-+}"
shift || true
while [ $# -gt 0 ]; do parse_token "$1" || true; shift || true; done

MODE="${TEMP_MODE:-$ZOOM_MODE}"
STEP_NORM="${TEMP_STEP:-$ZOOM_STEP}"
STEP_FAST="${TEMP_STEP:-$ZOOM_FAST_STEP}"
MIN="${TEMP_MIN:-$ZOOM_MIN}"
MAX="${TEMP_MAX:-$ZOOM_MAX}"
PREC="${TEMP_PREC:-$PRECISION}"
NOTIFY_ENABLED="${TEMP_NOTIFY:-$NOTIFY_ENABLED}"
NOTIFY_ZOOM="${TEMP_NZ:-$NOTIFY_ZOOM}"
NOTIFY_RIGID="${TEMP_NR:-$NOTIFY_RIGID}"
NOTIFY_RESET="${TEMP_NRES:-$NOTIFY_RESET}"

case "$arg" in
  +)  apply_step  1 "$STEP_NORM" "$MODE" "$MIN" "$MAX" "$PREC" ;;
  -)  apply_step -1 "$STEP_NORM" "$MODE" "$MIN" "$MAX" "$PREC" ;;
  ++) apply_step  1 "$STEP_FAST" "$MODE" "$MIN" "$MAX" "$PREC" ;;
  --) apply_step -1 "$STEP_FAST" "$MODE" "$MIN" "$MAX" "$PREC" ;;
  +[0-9]*)
      n="${arg#+}"; i=0
      while [ "$i" -lt "$n" ]; do apply_step 1 "$STEP_NORM" "$MODE" "$MIN" "$MAX" "$PREC" >/dev/null; i=$((i+1)); done
      cur="$(get_factor)"; printf 'zoom_factor: %s\n' "$(round_to "$cur" "$PREC")"; notify zoom "zoom: $(round_to "$cur" "$PREC")";;
  -[0-9]*)
      n="${arg#-}"; i=0
      while [ "$i" -lt "$n" ]; do apply_step -1 "$STEP_NORM" "$MODE" "$MIN" "$MAX" "$PREC" >/dev/null; i=$((i+1)); done
      cur="$(get_factor)"; printf 'zoom_factor: %s\n' "$(round_to "$cur" "$PREC")"; notify zoom "zoom: $(round_to "$cur" "$PREC")";;
  set:*)
      target="${arg#set:}"
      target="$(round_to "$(clamp "$target" "$MIN" "$MAX")" "$PREC")"
      set_factor "$target"
      printf 'zoom_factor: %s\n' "$target"
      log "factor -> ${target} (set)"
      notify zoom "zoom: $target"
      ;;
  reset)
      target="$(round_to "$(clamp "$DEFAULT_FACTOR" "$MIN" "$MAX")" "$PREC")"
      set_factor "$target"
      printf 'zoom_factor: %s\n' "$target"
      log "factor -> ${target} (reset)"
      notify reset "zoom: $target"
      ;;
  rigid)
      before="$(get_rigid)"
      to=$([ "$before" = "true" ] && echo false || echo true)
      set_rigid_to "$KEY_RIGID" "$to" || true
      after="$(get_rigid)"
      printf 'zoom_rigid: %s -> %s\n' "$before" "$after"
      log "rigid ${before} -> ${after}"
      notify rigid "rigid: $after"
      ;;
  rigid:on)
      set_rigid_to "$KEY_RIGID" true || true
      after="$(get_rigid)"; printf 'zoom_rigid: %s\n' "$after"
      log "rigid -> ${after}"
      notify rigid "rigid: $after"
      ;;
  rigid:off)
      set_rigid_to "$KEY_RIGID" false || true
      after="$(get_rigid)"; printf 'zoom_rigid: %s\n' "$after"
      log "rigid -> ${after}"
      notify rigid "rigid: $after"
      ;;
  status)
      printf 'KEY_FACTOR=%s\n' "$KEY_FACTOR"
      printf 'KEY_RIGID=%s\n'  "$KEY_RIGID"
      printf 'zoom_factor=%s\n' "$(get_factor)"
      printf 'zoom_rigid=%s\n'  "$(get_rigid)"
      printf 'mode=%s\n'        "$MODE"
      printf 'step=%s\n'        "$STEP_NORM"
      printf 'fast_step=%s\n'   "$STEP_FAST"
      printf 'bounds=%s:%s\n'   "$MIN" "$MAX"
      printf 'precision=%s\n'   "$PREC"
      printf 'notify_enabled=%s\n' "$NOTIFY_ENABLED"
      printf 'notify_zoom=%s\n'   "$NOTIFY_ZOOM"
      printf 'notify_rigid=%s\n'  "$NOTIFY_RIGID"
      printf 'notify_reset=%s\n'  "$NOTIFY_RESET"
      ;;
  status:json)
      # shellcheck disable=SC2016
      "$JQ" -n \
        --arg key_factor "$KEY_FACTOR" \
        --arg key_rigid "$KEY_RIGID" \
        --argjson zoom_factor "$(get_factor)" \
        --arg zoom_rigid "$(get_rigid)" \
        --arg mode "$MODE" \
        --arg step "$STEP_NORM" \
        --arg fast_step "$STEP_FAST" \
        --argjson min "$MIN" \
        --argjson max "$MAX" \
        --argjson precision "$PREC" \
        --argjson notify_enabled "$( [ "$NOTIFY_ENABLED" = "true" ] && echo true || echo false )" \
        --argjson notify_zoom    "$( [ "$NOTIFY_ZOOM"  = "true" ] && echo true || echo false )" \
        --argjson notify_rigid   "$( [ "$NOTIFY_RIGID" = "true" ] && echo true || echo false )" \
        --argjson notify_reset   "$( [ "$NOTIFY_RESET" = "true" ] && echo true || echo false )" \
        '{key_factor:$key_factor,key_rigid:$key_rigid,zoom_factor:$zoom_factor,zoom_rigid:$zoom_rigid,mode:$mode,step:$step,fast_step:$fast_step,min:$min,max:$max,precision:$precision,notify:{enabled:$notify_enabled,zoom:$notify_zoom,rigid:$notify_rigid,reset:$notify_reset}}'
      ;;
  *)
      cat <<'USAGE'
Usage:
  zoom.sh {+|-|++|--|+N|-N|set:X|step:X|mode:mul|mode:add|bounds:a:b|round:N|reset|rigid|rigid:on|rigid:off|status|status:json}
Optional one-shot flags:
  notify:on|off
  notify:zoom:on|off  notify:rigid:on|off  notify:reset:on|off

Examples:
  zoom.sh +                                   # zoom in by normal step
  zoom.sh --                                  # zoom out by fast step
  zoom.sh set:2.0                             # set to 2.0x directly
  zoom.sh notify:zoom:on +                    # enable zoom notifications for this call
  zoom.sh notify:off rigid                    # suppress rigid notification once
  zoom.sh mode:add step:0.2 +                 # add 0.2 absolute
  zoom.sh bounds:1:4 ++                       # clamp to [1,4] while fast stepping
USAGE
      exit 2
      ;;
esac
