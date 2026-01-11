#!/usr/bin/env bash
# FILE: ~/.config/hypr/scripts/waybar.sh
#
# Per-monitor waybar manager (one waybar process per output).
# Generates per-output configs from ~/.config/waybar/config (strict JSON).
#
# Legacy-compatible commands (used by your helper scripts):
#   start | stop | restart | status
#   focused-monitor
#   dump-state
#   getpos <MON> | getpos-focused
#   getenabled <MON> | getenabled-focused
#   toggle-focused | toggle-mon <MON>
#   setpos <MON> <top|bottom|left|right> | setpos-focused <top|bottom|left|right>
#   flip-focused
#   enable | disable
#
# Paths:
#   Template:  ~/.config/waybar/config
#   Style:     ~/.config/waybar/style.css
#   State:     ~/.cache/waybar/state.json
#   Per-out:   ~/.cache/waybar/per-output/<MON_SAFE>.json / .pid

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

# Vertical wrappers
CPU_TEMP_V="${CPU_TEMP_V:-$CONF/waybar/scripts/cpu_temp_vertical.sh}"
CLOCK_TOGGLE_V="${CLOCK_TOGGLE_V:-$CONF/waybar/scripts/clock_toggle_vertical.sh}"

mkdir -p "$BASE_DIR" "$PER_DIR"

pid_alive() { [[ -n "${1:-}" ]] && kill -0 "$1" 2>/dev/null; }

safe_name() { printf '%s' "$1" | tr '/ \t' '___'; }
pid_file_for() { printf '%s/%s.pid\n' "$PER_DIR" "$(safe_name "$1")"; }
cfg_file_for() { printf '%s/%s.json\n' "$PER_DIR" "$(safe_name "$1")"; }

read_pid() {
  local f
  f="$(pid_file_for "$1")"
  [[ -s "$f" ]] || return 1
  tr -d ' \t\r\n' <"$f"
}

write_pid() {
  local f
  f="$(pid_file_for "$1")"
  printf '%s\n' "$2" >"$f"
}

clear_pid() { rm -f "$(pid_file_for "$1")" 2>/dev/null || true; }

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
  local m
  m="$(cursor_monitor 2>/dev/null || true)"
  [[ -n "$m" ]] && { printf '%s
' "$m"; return 0; }
  m="$(activeworkspace_monitor 2>/dev/null || true)"
  [[ -n "$m" ]] && { printf '%s
' "$m"; return 0; }

  # Fallback: first monitor (prevents binds from "doing nothing" if focus detection fails)
  m="$(monitors_json 2>/dev/null | jq -r '.[0] // empty' 2>/dev/null || true)"
  [[ -n "$m" ]] && { printf '%s
' "$m"; return 0; }

  return 1
}
ensure_state() {
  local mons tmp
  mons="$(monitors_json)"

  # If state exists but is invalid JSON, nuke it and regenerate.
  if [[ -s "$STATE_FILE" ]]; then
    jq -e '.' "$STATE_FILE" >/dev/null 2>&1 || rm -f "$STATE_FILE"
  fi

  if [[ ! -s "$STATE_FILE" ]]; then
    jq -n --argjson mons "$mons" '
      { enabled: true, monitors: ($mons | map({(.): {position:"top", enabled:true}}) | add) }
    ' >"$STATE_FILE"
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
  ' "$STATE_FILE" >"$tmp"
  mv "$tmp" "$STATE_FILE"
}
global_enabled() {
  ensure_state
  jq -r '(.enabled // true) | if . then "true" else "false" end' "$STATE_FILE"
}

set_global_enabled() {
  local v="${1:-}" jv
  case "$v" in
    true|1|yes|on) jv=true ;;
    false|0|no|off) jv=false ;;
    *) printf 'waybar.sh: enable expects true/false\n' >&2; exit 2 ;;
  esac

  ensure_state
  local tmp
  tmp="$(mktemp)"
  jq --argjson v "$jv" '.enabled = $v' "$STATE_FILE" >"$tmp"
  mv "$tmp" "$STATE_FILE"
}

monitor_enabled() {
  local mon="$1"
  ensure_state
  jq -r --arg m "$mon" '(.monitors[$m].enabled // true) | if . then "true" else "false" end' "$STATE_FILE"
}

set_monitor_enabled() {
  local mon="$1" v="$2" jv
  case "$v" in
    true|1|yes|on) jv=true ;;
    false|0|no|off) jv=false ;;
    *) printf 'waybar.sh: monitor enable expects true/false\n' >&2; exit 2 ;;
  esac

  ensure_state
  local tmp
  tmp="$(mktemp)"
  jq --arg m "$mon" --argjson v "$jv" '.monitors[$m].enabled = $v' "$STATE_FILE" >"$tmp"
  mv "$tmp" "$STATE_FILE"
}

monitor_position() {
  local mon="$1"
  ensure_state
  jq -r --arg m "$mon" '.monitors[$m].position // "top"' "$STATE_FILE"
}

set_monitor_position() {
  local mon="$1" pos="$2"
  case "$pos" in
    top|bottom|left|right) ;;
    *) printf 'waybar.sh: invalid position: %s\n' "$pos" >&2; exit 2 ;;
  esac

  ensure_state
  local tmp
  tmp="$(mktemp)"
  jq --arg m "$mon" --arg p "$pos" '.monitors[$m].position = $p' "$STATE_FILE" >"$tmp"
  mv "$tmp" "$STATE_FILE"
}

gen_cfg_mon() {
  local mon="$1" pos="$2" out="$3"
  [[ -f "$TEMPLATE_CFG" ]] || { printf 'waybar.sh: missing template: %s\n' "$TEMPLATE_CFG" >&2; return 1; }

  jq -e '.' "$TEMPLATE_CFG" >/dev/null 2>&1 || {
    printf 'waybar.sh: template is not strict JSON (jq must parse it): %s\n' "$TEMPLATE_CFG" >&2
    return 1
  }

  local jqf
  jqf="$(mktemp)"
  cat >"$jqf" <<'JQ'
def base:
  if ($cfg[0] | type) == "array" then $cfg[0][0] else $cfg[0] end;

def trim: gsub("^[[:space:]]+|[[:space:]]+$";"");
def norm: (gsub("[[:space:]]+";" ") | trim);
def toks: (norm | split(" "));

def icon_from_format($fmt; $fallback):
  ($fmt | norm) as $f
  | ($f | toks) as $t
  | ($t[0] // "") as $t0
  | ($t[-1] // "") as $tL
  | (if ($t0 | test("\\{")) then $tL else $t0 end) as $pick
  | (if ($pick | test("\\{")) then $fallback else $pick end);

def expand_one($m):
  if $m == "cpu" then ["cpu#v_icon","cpu#v_val"]
  elif $m == "memory" then ["memory#v_icon","memory#v_val"]
  elif $m == "wireplumber" then ["wireplumber#v_icon","wireplumber#v_val"]
  elif $m == "custom/cputemp" then ["custom/cputemp#v_icon","custom/cputemp#v_val"]
  elif $m == "custom/clock-toggle" then ["custom/clock-toggle#v_icon","custom/clock-toggle#v_a","custom/clock-toggle#v_b"]
  else [$m] end;

def expand_list($arr): [ $arr[] as $m | expand_one($m)[] ];

base as $b
| ($b.height // $hdef) as $hheight
| ($b
    | .output = [$mon]
    | .position = $pos
    | if ($pos == "left" or $pos == "right") then
        .width = $vwidth
        | .height = 0
        | .margin = 0
        | .spacing = 0

        | .["modules-center"] = []
        | (if .["hyprland/window"]? then del(.["hyprland/window"]) else . end)

        | .["modules-left"]  = ((.["modules-left"]  // []) | map(select(. != "custom/spacer-submap")))
        | .["modules-right"] = ((.["modules-right"] // []) | map(select(. != "custom/spacer-submap")))

        | (if .["group/ws-arrows"]? then .["group/ws-arrows"].orientation = "vertical" else . end)

        | .["modules-right"] = expand_list(.["modules-right"] // [])

        | (if .cpu? then
             (icon_from_format((.cpu.format? // "{usage}"); "")) as $ico
             | .["cpu#v_icon"] = (.cpu * {"format": $ico})
             | .["cpu#v_val"]  = (.cpu * {"format": "{usage}"})
           else . end)

        | (if .memory? then
             (icon_from_format((.memory.format? // "{}"); "")) as $ico
             | .["memory#v_icon"] = (.memory * {"format": $ico})
             | .["memory#v_val"]  = (.memory * {"format": "{}"})
           else . end)

        | (if .wireplumber? then
             .["wireplumber#v_icon"] =
               (.wireplumber
                 * {"format":"{icon}",
                    "format-bluetooth":"{icon}",
                    "format-muted":"",
                    "format-bluetooth-muted":""})
             | .["wireplumber#v_val"] =
               (.wireplumber
                 * {"format":"{volume}",
                    "format-bluetooth":"{volume}",
                    "format-muted":"mute",
                    "format-bluetooth-muted":"mute"})
           else . end)

        | (if ($b["custom/cputemp"]? != null) then
             .["custom/cputemp#v_icon"] =
               ($b["custom/cputemp"] * {"exec": ($cputemp_exec_v + " icon"), "format":"{}"})
             | .["custom/cputemp#v_val"] =
               ($b["custom/cputemp"] * {"exec": ($cputemp_exec_v + " temp"), "format":"{}"})
           else . end)

        | (if ($b["custom/clock-toggle"]? != null) then
             .["custom/clock-toggle#v_icon"] =
               ($b["custom/clock-toggle"]
                 * {"exec": ($clock_toggle_exec_v + " icon"), "return-type":"json"})
             | .["custom/clock-toggle#v_a"] =
               (($b["custom/clock-toggle"]
                  * {"exec": ($clock_toggle_exec_v + " a"), "return-type":"json"})
                 | del(."on-click", ."on-click-right", ."on-scroll-up", ."on-scroll-down"))
             | .["custom/clock-toggle#v_b"] =
               (($b["custom/clock-toggle"]
                  * {"exec": ($clock_toggle_exec_v + " b"), "return-type":"json"})
                 | del(."on-click", ."on-click-right", ."on-scroll-up", ."on-scroll-down"))
           else . end)

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
    -f "$jqf" >"$out"

  rm -f "$jqf"
}

start_one() {
  local mon="$1"
  ensure_state

  [[ "$(global_enabled)" == "true" ]] || return 0
  [[ "$(monitor_enabled "$mon")" == "true" ]] || return 0

  local pid cfg pos
  pos="$(monitor_position "$mon")"
  cfg="$(cfg_file_for "$mon")"
  gen_cfg_mon "$mon" "$pos" "$cfg"

  pid="$(read_pid "$mon" 2>/dev/null || true)"
  if [[ -n "$pid" ]] && pid_alive "$pid"; then
    return 0
  fi

  log "starting $mon at $pos"
  nohup waybar -c "$cfg" -s "$STYLE_CSS" >/dev/null 2>&1 &
  pid="$!"
  write_pid "$mon" "$pid"

  sleep 0.08
  if ! pid_alive "$pid"; then
    printf 'waybar.sh: waybar crashed starting monitor %s\n' "$mon" >&2
    printf 'try:\n  waybar -c %s -s %s\n' "$cfg" "$STYLE_CSS" >&2
    clear_pid "$mon"
    return 1
  fi
}

stop_one() {
  local mon="$1" pid
  pid="$(read_pid "$mon" 2>/dev/null || true)"
  if [[ -n "$pid" ]] && pid_alive "$pid"; then
    log "stopping $mon pid $pid"
    kill "$pid" 2>/dev/null || true
    sleep 0.05
    pid_alive "$pid" && kill -9 "$pid" 2>/dev/null || true
  fi
  clear_pid "$mon"
}

start_all() {
  local mons m
  mons="$(monitors_json)"
  while read -r m; do
    start_one "$m" || true
  done < <(jq -r '.[]' <<<"$mons")
}

stop_all() {
  local mons m
  mons="$(monitors_json)"
  while read -r m; do
    stop_one "$m" || true
  done < <(jq -r '.[]' <<<"$mons")
}

restart_all() { stop_all; start_all; }

status() {
  local mons m pid
  mons="$(monitors_json)"
  while read -r m; do
    pid="$(read_pid "$m" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && pid_alive "$pid"; then
      printf 'running\n'
      return 0
    fi
  done < <(jq -r '.[]' <<<"$mons")
  printf 'stopped\n'
}

toggle_mon() {
  local mon="${1:-}"
  [[ -n "$mon" ]] || { printf 'waybar.sh: toggle-mon <MON>
' >&2; exit 2; }

  ensure_state

  # Decide toggle by ACTUAL running process, not by possibly-stale enabled flags.
  local pid=""
  pid="$(read_pid "$mon" 2>/dev/null || true)"
  if [[ -n "$pid" ]] && pid_alive "$pid"; then
    set_monitor_enabled "$mon" false
    stop_one "$mon"
    return 0
  fi

  clear_pid "$mon" 2>/dev/null || true
  set_global_enabled true
  set_monitor_enabled "$mon" true
  start_one "$mon"
}
toggle_focused() {
  local mon
  mon="$(focused_monitor)" || { printf 'waybar.sh: cannot determine focused monitor\n' >&2; exit 1; }
  toggle_mon "$mon"
}

setpos_mon() {
  local mon="$1" pos="$2"
  set_monitor_position "$mon" "$pos"
  stop_one "$mon"
  start_one "$mon"
}

setpos_focused() {
  local pos="$1" mon
  mon="$(focused_monitor)" || { printf 'waybar.sh: cannot determine focused monitor\n' >&2; exit 1; }
  setpos_mon "$mon" "$pos"
}

flip_focused() {
  local mon cur nxt
  mon="$(focused_monitor)" || { printf 'waybar.sh: cannot determine focused monitor\n' >&2; exit 1; }
  cur="$(monitor_position "$mon")"
  case "$cur" in
    top) nxt=bottom ;;
    bottom) nxt=top ;;
    left) nxt=right ;;
    right) nxt=left ;;
    *) nxt=bottom ;;
  esac
  setpos_mon "$mon" "$nxt"
}

dump_state() {
  ensure_state
  cat "$STATE_FILE"
}

usage() {
  cat >&2 <<'EOF'
usage: waybar.sh <command>

global:
  start | stop | restart | status
  enable | disable
  dump-state

focused:
  focused-monitor
  toggle-focused
  getpos-focused
  getenabled-focused
  setpos-focused <top|bottom|left|right>
  flip-focused

per-monitor:
  toggle-mon <MON>
  getpos <MON>
  getenabled <MON>
  setpos <MON> <top|bottom|left|right>
EOF
}

cmd="${1:-}"
case "$cmd" in
  start) start_all ;;
  stop) stop_all ;;
  restart) restart_all ;;
  status) status ;;

  enable) set_global_enabled true; start_all ;;
  disable) set_global_enabled false; stop_all ;;

  focused-monitor) focused_monitor || true ;;
  dump-state) dump_state ;;

  getpos)
    [[ -n "${2:-}" ]] || { usage; exit 2; }
    monitor_position "$2"
    ;;
  getpos-focused)
    mon="$(focused_monitor)" || exit 1
    monitor_position "$mon"
    ;;
  getenabled)
    [[ -n "${2:-}" ]] || { usage; exit 2; }
    monitor_enabled "$2"
    ;;
  getenabled-focused)
    mon="$(focused_monitor)" || exit 1
    monitor_enabled "$mon"
    ;;

  toggle-focused) toggle_focused ;;
  toggle-mon)
    [[ -n "${2:-}" ]] || { usage; exit 2; }
    toggle_mon "$2"
    ;;
  setpos)
    [[ -n "${2:-}" && -n "${3:-}" ]] || { usage; exit 2; }
    setpos_mon "$2" "$3"
    ;;
  setpos-focused)
    [[ -n "${2:-}" ]] || { usage; exit 2; }
    setpos_focused "$2"
    ;;
  flip-focused) flip_focused ;;

  ""|-h|--help|help) usage; exit 0 ;;
  *) usage; exit 2 ;;
esac
