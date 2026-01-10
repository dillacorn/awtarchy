#!/usr/bin/env bash
# FILE: ~/.config/hypr/scripts/waybar.sh
#
# Per-monitor waybar manager (one waybar process per output).
# Toggle logic uses live PID existence.
#
# Template (strict JSON array):
#   ~/.config/waybar/config
# Style:
#   ~/.config/waybar/style.css
#
# State:
#   ~/.cache/waybar/state.json
# Per-monitor cfg/pid:
#   ~/.cache/waybar/per-output/<MON>.json
#   ~/.cache/waybar/per-output/<MON>.pid

set -euo pipefail

need() { command -v "$1" >/dev/null 2>&1 || { printf 'waybar.sh: missing: %s\n' "$1" >&2; exit 127; }; }
need waybar
need hyprctl
need jq
need mktemp
need nohup

DEBUG="${DEBUG:-0}"
log() { [[ "$DEBUG" == "1" ]] && printf '[waybar.sh] %s\n' "$*" >&2 || true; }

CONF="${XDG_CONFIG_HOME:-$HOME/.config}"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}"

TEMPLATE_CFG="${TEMPLATE_CFG:-$CONF/waybar/config}"
STYLE_CSS="${STYLE_CSS:-$CONF/waybar/style.css}"

BASE_DIR="${BASE_DIR:-$CACHE/waybar}"
STATE_FILE="${STATE_FILE:-$BASE_DIR/state.json}"
PER_DIR="${PER_DIR:-$BASE_DIR/per-output}"

WAYBAR_VERTICAL_WIDTH="${WAYBAR_VERTICAL_WIDTH:-36}"
WAYBAR_HORIZONTAL_HEIGHT_DEFAULT="${WAYBAR_HORIZONTAL_HEIGHT_DEFAULT:-28}"

CPU_TEMP_V="${CPU_TEMP_V:-$CONF/waybar/scripts/cpu_temp_vertical.sh}"
CLOCK_TOGGLE_V="${CLOCK_TOGGLE_V:-$CONF/waybar/scripts/clock_toggle_vertical.sh}"
mkdir -p "$BASE_DIR" "$PER_DIR"

safe_name() { printf '%s' "$1" | tr '/ ' '__'; }
pidfile_for() { printf '%s/%s.pid' "$PER_DIR" "$(safe_name "$1")"; }
cfgfile_for() { printf '%s/%s.json' "$PER_DIR" "$(safe_name "$1")"; }

pid_alive() { [[ -n "${1:-}" ]] && kill -0 "$1" 2>/dev/null; }

monitors_json() { hyprctl monitors -j | jq -c '[.[].name]'; }

cursor_monitor() {
  local pos x y
  pos="$(hyprctl cursorpos 2>/dev/null || true)"
  [[ -n "$pos" ]] || return 1
  x="$(printf '%s' "$pos" | awk -F',' '{gsub(/[[:space:]]/,"",$1); print $1}')"
  y="$(printf '%s' "$pos" | awk -F',' '{gsub(/[[:space:]]/,"",$2); print $2}')"
  [[ "$x" =~ ^-?[0-9]+$ && "$y" =~ ^-?[0-9]+$ ]] || return 1

  hyprctl monitors -j | jq -r --argjson x "$x" --argjson y "$y" '
    .[]
    | select(($x >= .x) and ($x < (.x + .width)) and ($y >= .y) and ($y < (.y + .height)))
    | .name
  ' | head -n1
}

activeworkspace_monitor() {
  hyprctl activeworkspace -j 2>/dev/null | jq -r '.monitor // empty' | head -n1
}

focused_monitor() {
  local m=""
  m="$(cursor_monitor 2>/dev/null || true)"
  [[ -n "$m" ]] && { echo "$m"; return 0; }
  m="$(activeworkspace_monitor 2>/dev/null || true)"
  [[ -n "$m" ]] && { echo "$m"; return 0; }
  return 1
}

ensure_state() {
  local mons tmp
  mons="$(monitors_json)"

  if [[ ! -f "$STATE_FILE" ]]; then
    jq -n --argjson mons "$mons" '
      { enabled: true, monitors: ($mons | map({(.): {position:"top", enabled:true}}) | add) }
    ' > "$STATE_FILE"
    return 0
  fi

  tmp="$(mktemp)"
  jq --argjson mons "$mons" '
    . as $s
    | ($s.enabled // true) as $enabled
    | ($s.monitors // {}) as $m
    | {
        enabled: $enabled,
        monitors: (
          $mons
          | map(. as $n | { ($n): ({position:"top", enabled:true} * ($m[$n] // {})) })
          | add
        )
      }
  ' "$STATE_FILE" > "$tmp"
  mv "$tmp" "$STATE_FILE"
}

global_enabled() { ensure_state; jq -r '(.enabled // true) | if . then "true" else "false" end' "$STATE_FILE"; }

set_global_enabled() {
  local v="${1:-}" jv
  case "$v" in true|1|yes|on) jv=true ;; false|0|no|off) jv=false ;; *) printf 'waybar.sh: enable expects true/false\n' >&2; exit 2 ;; esac
  ensure_state
  local tmp; tmp="$(mktemp)"
  jq --argjson v "$jv" '.enabled = $v' "$STATE_FILE" > "$tmp"
  mv "$tmp" "$STATE_FILE"
}

get_pos() {
  local mon="${1:-}"
  [[ -n "$mon" ]] || { printf 'waybar.sh: getpos <MON>\n' >&2; exit 2; }
  ensure_state
  jq -r --arg m "$mon" '.monitors[$m].position // "top"' "$STATE_FILE"
}

set_pos() {
  local mon="${1:-}" pos="${2:-}"
  [[ -n "$mon" && -n "$pos" ]] || { printf 'waybar.sh: setpos <MON> <top|bottom|left|right>\n' >&2; exit 2; }
  case "$pos" in top|bottom|left|right) ;; *) printf 'waybar.sh: invalid pos: %s\n' "$pos" >&2; exit 2 ;; esac
  ensure_state
  local tmp; tmp="$(mktemp)"
  jq --arg m "$mon" --arg p "$pos" '.monitors[$m].position = $p' "$STATE_FILE" > "$tmp"
  mv "$tmp" "$STATE_FILE"
}

get_mon_enabled() {
  local mon="${1:-}"
  [[ -n "$mon" ]] || { printf 'waybar.sh: getenabled <MON>\n' >&2; exit 2; }
  ensure_state
  jq -r --arg m "$mon" '(.monitors[$m].enabled // true) | if . then "true" else "false" end' "$STATE_FILE"
}

set_mon_enabled() {
  local mon="${1:-}" v="${2:-}" jv
  [[ -n "$mon" && -n "$v" ]] || { printf 'waybar.sh: setenabled <MON> <true|false>\n' >&2; exit 2; }
  case "$v" in true|1|yes|on) jv=true ;; false|0|no|off) jv=false ;; *) printf 'waybar.sh: setenabled expects true/false\n' >&2; exit 2 ;; esac
  ensure_state
  local tmp; tmp="$(mktemp)"
  jq --arg m "$mon" --argjson v "$jv" '.monitors[$m].enabled = $v' "$STATE_FILE" > "$tmp"
  mv "$tmp" "$STATE_FILE"
}

mon_pid() {
  local mon="$1" pf pid
  pf="$(pidfile_for "$mon")"
  [[ -f "$pf" ]] || return 1
  pid="$(cat "$pf" 2>/dev/null || true)"
  pid_alive "$pid" || return 1
  printf '%s\n' "$pid"
  return 0
}

stop_mon() {
  local mon="$1" pf pid
  pf="$(pidfile_for "$mon")"
  [[ -f "$pf" ]] || return 0
  pid="$(cat "$pf" 2>/dev/null || true)"

  if pid_alive "$pid"; then
    log "stop $mon pid=$pid"
    kill "$pid" 2>/dev/null || true
    for _ in $(seq 1 60); do
      pid_alive "$pid" || break
      sleep 0.05
    done
    pid_alive "$pid" && kill -KILL "$pid" 2>/dev/null || true
  fi

  rm -f "$pf"
}

gen_cfg_mon() {
  local mon="$1" pos="$2" out="$3"

  [[ -f "$TEMPLATE_CFG" ]] || { printf 'waybar.sh: missing template: %s\n' "$TEMPLATE_CFG" >&2; exit 1; }

  jq -e '.' "$TEMPLATE_CFG" >/dev/null 2>&1 || {
    printf 'waybar.sh: template is not strict JSON (jq must parse it): %s\n' "$TEMPLATE_CFG" >&2
    exit 1
  }

  local jqf; jqf="$(mktemp)"
  cat >"$jqf" <<'JQ'
def base:
  if ($cfg[0] | type) == "array" then $cfg[0][0] else $cfg[0] end;

def trim: gsub("^[[:space:]]+|[[:space:]]+$";"");
def norm: (gsub("[[:space:]]+";" ") | trim);
def toks: (norm | split(" "));
def firsttok: (toks | .[0]);
def lasttok: (toks | .[-1]);

base as $b
| ($b.height // $hdef) as $hheight
| ($b
    | .output = [$mon]
    | .position = $pos
    | if ($pos == "left" or $pos == "right") then
        del(.height) | .width = ($b.width // $vwidth)

        # remove hyprland/window when vertical
        | .["modules-center"] = ((.["modules-center"] // []) | map(select(. != "hyprland/window")))
        | (if .["hyprland/window"]? then del(.["hyprland/window"]) else . end)

        # ws arrows vertical so it doesn't reserve a sideways gap
        | (if .["group/ws-arrows"]? then .["group/ws-arrows"].orientation = "vertical" else . end)

        # cpu icon above usage
        | (if .cpu? and .cpu.format? then
             (.cpu.format | norm | lasttok) as $ico
             | .cpu.format = ($ico + "\n{usage}")
           else . end)

        # memory icon above value (your format is "{} <icon>")
        | (if .memory? and .memory.format? then
             (.memory.format | norm | lasttok) as $ico
             | .memory.format = ($ico + "\n{}")
           else . end)

        # backlight icon above percent
        | (if .backlight? then .backlight.format = "{icon}\n{percent}" else . end)

        # battery icon above percent
        | (if .battery? then
             .battery.format = "{icon}\n{capacity}"
             | (if .battery["format-charging"]? then
                  (.battery["format-charging"] | norm | firsttok) as $ico
                  | .battery["format-charging"] = ($ico + "\n{capacity}")
                else . end)
             | (if .battery["format-plugged"]? then
                  (.battery["format-plugged"] | norm | firsttok) as $ico
                  | .battery["format-plugged"] = ($ico + "\n{capacity}")
                else . end)
           else . end)

        # volume: hide icon
        | (if .wireplumber? then
             .wireplumber.format = "{volume}"
             | .wireplumber["format-bluetooth"] = "{volume}"
             | .wireplumber["format-muted"] = "mute"
             | .wireplumber["format-bluetooth-muted"] = "mute"
           else . end)

        # VERTICAL_WRAPPERS_BEGIN
        # custom modules: run wrapper scripts that emit vertical-friendly output.
        # cputemp wrapper emits JSON with "\n" in text, so set return-type json here.
        | (if ($b["custom/cputemp"]? != null) then
             .["custom/cputemp"] = ($b["custom/cputemp"] * {"exec":$cputemp_exec_v, "return-type":"json"})
           else . end)
        | (if ($b["custom/clock-toggle"]? != null) then
             .["custom/clock-toggle"] = ($b["custom/clock-toggle"] * {"exec":$clock_toggle_exec_v})
           else . end)
        # VERTICAL_WRAPPERS_END

      else
        del(.width) | .height = $hheight
      end
  )
| [.]
JQ

  jq -n \
    --arg mon "$mon" \
    --arg pos "$pos" \
    --arg cputemp_exec_v "$CPU_TEMP_V" \
    --arg clock_toggle_exec_v "$CLOCK_TOGGLE_V" \
    --argjson vwidth "$WAYBAR_VERTICAL_WIDTH" \
    --argjson hdef "$WAYBAR_HORIZONTAL_HEIGHT_DEFAULT" \
    --slurpfile cfg "$TEMPLATE_CFG" \
    -f "$jqf" > "$out"

  rm -f "$jqf"
}

start_mon() {
  local mon="$1" pos cfg pf pid
  pos="$(get_pos "$mon")"
  cfg="$(cfgfile_for "$mon")"
  pf="$(pidfile_for "$mon")"

  gen_cfg_mon "$mon" "$pos" "$cfg"

  if [[ -f "$pf" ]]; then
    pid="$(cat "$pf" 2>/dev/null || true)"
    pid_alive "$pid" || rm -f "$pf"
  fi

  log "start $mon pos=$pos"
  if [[ -f "$STYLE_CSS" ]]; then
    nohup waybar -c "$cfg" -s "$STYLE_CSS" >/dev/null 2>&1 &
  else
    nohup waybar -c "$cfg" >/dev/null 2>&1 &
  fi
  pid="$!"
  echo "$pid" > "$pf"
  disown || true

  sleep 0.15
  if ! pid_alive "$pid"; then
    rm -f "$pf"
    printf 'waybar.sh: waybar crashed starting monitor %s\n' "$mon" >&2
    printf 'try:\n  waybar -c %s -s %s\n' "$cfg" "$STYLE_CSS" >&2
    exit 1
  fi
}

start_all() {
  ensure_state
  [[ "$(global_enabled)" == "true" ]] || return 0

  local mons m
  mons="$(monitors_json)"
  for m in $(jq -r '.[]' <<<"$mons"); do
    if [[ "$(get_mon_enabled "$m")" == "true" ]]; then
      if ! mon_pid "$m" >/dev/null 2>&1; then
        start_mon "$m"
      fi
    fi
  done
}

stop_all() {
  ensure_state
  local mons m
  mons="$(monitors_json)"
  for m in $(jq -r '.[]' <<<"$mons"); do
    stop_mon "$m"
  done
}

status() {
  ensure_state
  local mons m
  mons="$(monitors_json)"
  for m in $(jq -r '.[]' <<<"$mons"); do
    if mon_pid "$m" >/dev/null 2>&1; then
      echo running
      return 0
    fi
  done
  echo stopped
}

toggle_mon() {
  local mon="${1:-}"
  [[ -n "$mon" ]] || { printf 'waybar.sh: toggle-mon <MON>\n' >&2; exit 2; }

  if mon_pid "$mon" >/dev/null 2>&1; then
    set_mon_enabled "$mon" false
    stop_mon "$mon"
    return 0
  fi

  rm -f "$(pidfile_for "$mon")" 2>/dev/null || true

  set_global_enabled true
  set_mon_enabled "$mon" true
  start_mon "$mon"
}

toggle_focused() {
  local mon
  mon="$(focused_monitor)" || { printf 'waybar.sh: cannot determine focused monitor\n' >&2; exit 1; }
  toggle_mon "$mon"
}

setpos_focused() {
  local pos="${1:-}"
  [[ -n "$pos" ]] || { printf 'waybar.sh: setpos-focused <top|bottom|left|right>\n' >&2; exit 2; }
  case "$pos" in top|bottom|left|right) ;; *) printf 'waybar.sh: invalid pos: %s\n' "$pos" >&2; exit 2 ;; esac

  local mon pid
  mon="$(focused_monitor)" || exit 1
  set_pos "$mon" "$pos"

  if pid="$(mon_pid "$mon" 2>/dev/null || true)"; [[ -n "$pid" ]]; then
    stop_mon "$mon"
    start_mon "$mon"
  fi
}

flip_focused() {
  local mon cur nxt
  mon="$(focused_monitor)" || exit 1
  cur="$(get_pos "$mon")"
  case "$cur" in
    top) nxt=bottom ;;
    bottom) nxt=top ;;
    left) nxt=right ;;
    right) nxt=left ;;
    *) nxt=bottom ;;
  esac
  setpos_focused "$nxt"
}

case "${1:-}" in
  start) start_all ;;
  stop) stop_all ;;
  restart) stop_all; start_all ;;
  status) status ;;

  focused-monitor) focused_monitor || true ;;

  toggle-focused) toggle_focused ;;
  toggle-mon) toggle_mon "${2:-}" ;;

  getpos) get_pos "${2:-}" ;;
  getpos-focused) get_pos "$(focused_monitor)" ;;
  getenabled) get_mon_enabled "${2:-}" ;;
  getenabled-focused) get_mon_enabled "$(focused_monitor)" ;;

  setpos-focused) setpos_focused "${2:-}" ;;
  flip-focused) flip_focused ;;

  dump-state) ensure_state; cat "$STATE_FILE" ;;
  *)
    cat >&2 <<'USAGE'
usage: waybar.sh <command>

global:
  start | stop | restart | status

focused:
  focused-monitor
  toggle-focused
  setpos-focused <top|bottom|left|right>
  flip-focused
  getpos-focused
  getenabled-focused

specific:
  toggle-mon <MON>
  getpos <MON>
  getenabled <MON>

debug:
  dump-state
USAGE
    exit 2
    ;;
esac
