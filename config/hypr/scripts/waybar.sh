#!/usr/bin/env bash
# ~/.config/hypr/scripts/waybar.sh
#
# Per-output Waybar manager (one Waybar process per output).
# Generates per-output configs from ~/.config/waybar/config (JSONC-ish allowed: //, /* */, trailing commas).
#
# Commands:
#   start | stop | restart | status
#   enable | disable
#   focused-monitor
#   dump-state
#   getpos <MON> | getpos-focused
#   getenabled <MON> | getenabled-focused
#   toggle-focused | toggle-mon <MON>
#   setpos <MON> <top|bottom|left|right> | setpos-focused <top|bottom|left|right>
#   flip-focused
#
# State:
#   ~/.cache/waybar/state.json
#   { "enabled": true, "monitors": { "DP-1": { "position":"top", "enabled":true }, ... } }

set -euo pipefail

need() { command -v "$1" >/dev/null 2>&1 || { printf 'waybar.sh: missing: %s\n' "$1" >&2; exit 127; }; }
need waybar
need hyprctl
need jq
need python3
need mktemp
need nohup

CONF="${XDG_CONFIG_HOME:-$HOME/.config}"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}"

TEMPLATE_CFG="${TEMPLATE_CFG:-$CONF/waybar/config}"
STYLE_CSS="${STYLE_CSS:-$CONF/waybar/style.css}"

BASE_DIR="${BASE_DIR:-$CACHE/waybar}"
STATE_FILE="${STATE_FILE:-$BASE_DIR/state.json}"
PER_DIR="${PER_DIR:-$BASE_DIR/per-output}"
LOG_DIR="${LOG_DIR:-$BASE_DIR/log}"
TEMPLATE_JSON="${TEMPLATE_JSON:-$BASE_DIR/template.strict.json}"

WAYBAR_VERTICAL_WIDTH="${WAYBAR_VERTICAL_WIDTH:-36}"
WAYBAR_HORIZONTAL_HEIGHT_DEFAULT="${WAYBAR_HORIZONTAL_HEIGHT_DEFAULT:-28}"

CPU_TEMP_V="${CPU_TEMP_V:-$CONF/waybar/scripts/cpu_temp_vertical.sh}"
CLOCK_TOGGLE_V="${CLOCK_TOGGLE_V:-$CONF/waybar/scripts/clock_toggle_vertical.sh}"

TRACE="${TRACE:-0}"
TRACE_LOG="${TRACE_LOG:-$BASE_DIR/trace.log}"

mkdir -p "$BASE_DIR" "$PER_DIR" "$LOG_DIR"

ts() { date -Is; }
trace() {
  [[ "$TRACE" == "1" ]] || return 0
  printf '%s %s\n' "$(ts)" "$*" >>"$TRACE_LOG" 2>/dev/null || true
}

pid_alive() { [[ -n "${1:-}" ]] && kill -0 "$1" 2>/dev/null; }
pid_comm() { tr -d '\n' </proc/"$1"/comm 2>/dev/null || true; }

safe_name() { printf '%s' "$1" | tr '/ \t' '___'; }
pid_file_for() { printf '%s/%s.pid\n' "$PER_DIR" "$(safe_name "$1")"; }
cfg_file_for() { printf '%s/%s.json\n' "$PER_DIR" "$(safe_name "$1")"; }
log_file_for() { printf '%s/waybar-%s.log\n' "$LOG_DIR" "$(safe_name "$1")"; }

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

pid_cmd_has_cfg() {
  local pid="$1" cfg="$2"
  pid_alive "$pid" || return 1
  [[ "$(pid_comm "$pid")" == "waybar" ]] || return 1
  tr '\0' ' ' </proc/"$pid"/cmdline 2>/dev/null | grep -Fq -- " -c $cfg " || return 1
  return 0
}

# -------------------------
# Template: JSONC -> strict JSON
# -------------------------
ensure_template_json() {
  [[ -f "$TEMPLATE_CFG" ]] || { printf 'waybar.sh: missing template: %s\n' "$TEMPLATE_CFG" >&2; exit 1; }

  if [[ -f "$TEMPLATE_JSON" && "$TEMPLATE_CFG" -ot "$TEMPLATE_JSON" ]]; then
    return 0
  fi

  trace "template: preprocess -> $TEMPLATE_JSON"
  python3 - "$TEMPLATE_CFG" "$TEMPLATE_JSON" <<'PY'
import json, sys

src, dst = sys.argv[1], sys.argv[2]
raw = open(src, "r", encoding="utf-8", errors="replace").read()

def strip_jsonc_and_trailing_commas(s: str) -> str:
    out = []
    i = 0
    n = len(s)
    in_str = False
    esc = False
    line_comment = False
    block_comment = False

    while i < n:
        c = s[i]
        if line_comment:
            if c == "\n":
                line_comment = False
                out.append(c)
            i += 1
            continue
        if block_comment:
            if c == "*" and i + 1 < n and s[i + 1] == "/":
                block_comment = False
                i += 2
            else:
                i += 1
            continue

        if in_str:
            out.append(c)
            if esc:
                esc = False
            elif c == "\\":
                esc = True
            elif c == '"':
                in_str = False
            i += 1
            continue

        if c == '"':
            in_str = True
            out.append(c)
            i += 1
            continue

        if c == "/" and i + 1 < n:
            nxt = s[i + 1]
            if nxt == "/":
                line_comment = True
                i += 2
                continue
            if nxt == "*":
                block_comment = True
                i += 2
                continue

        out.append(c)
        i += 1

    s2 = "".join(out)

    out2 = []
    i = 0
    n = len(s2)
    in_str = False
    esc = False
    while i < n:
        c = s2[i]
        if in_str:
            out2.append(c)
            if esc:
                esc = False
            elif c == "\\":
                esc = True
            elif c == '"':
                in_str = False
            i += 1
            continue

        if c == '"':
            in_str = True
            out2.append(c)
            i += 1
            continue

        if c == ",":
            j = i + 1
            while j < n and s2[j] in " \t\r\n":
                j += 1
            if j < n and s2[j] in "}]":
                i += 1
                continue

        out2.append(c)
        i += 1

    return "".join(out2)

clean = strip_jsonc_and_trailing_commas(raw)
obj = json.loads(clean)

with open(dst, "w", encoding="utf-8") as f:
    json.dump(obj, f, indent=2, ensure_ascii=False)
    f.write("\n")
PY

  jq -e '.' "$TEMPLATE_JSON" >/dev/null 2>&1 || {
    printf 'waybar.sh: template not valid JSON after preprocessing: %s\n' "$TEMPLATE_CFG" >&2
    rm -f "$TEMPLATE_JSON" 2>/dev/null || true
    exit 1
  }
}

# -------------------------
# Hypr monitors (non-blocking-ish)
# -------------------------
__MON_FULL_JSON=""
__MON_NAMES_JSON=""

monitors_full_json() {
  local raw
  if [[ -n "$__MON_FULL_JSON" ]]; then
    printf '%s' "$__MON_FULL_JSON"
    return 0
  fi

  # Probe briefly; do not block for seconds.
  for _ in 1 2 3 4 5; do
    raw="$(hyprctl monitors -j 2>/dev/null || true)"
    if [[ -n "$raw" ]] && jq -e 'type=="array" and length>0' >/dev/null 2>&1 <<<"$raw"; then
      __MON_FULL_JSON="$raw"
      printf '%s' "$__MON_FULL_JSON"
      return 0
    fi
    sleep 0.05
  done

  __MON_FULL_JSON='[]'
  printf '%s' "$__MON_FULL_JSON"
}

monitors_json() {
  local full
  if [[ -n "$__MON_NAMES_JSON" ]]; then
    printf '%s' "$__MON_NAMES_JSON"
    return 0
  fi
  full="$(monitors_full_json)"
  if jq -e 'type=="array" and length>0' >/dev/null 2>&1 <<<"$full"; then
    __MON_NAMES_JSON="$(jq -c '[.[].name]' <<<"$full")"
  else
    __MON_NAMES_JSON='[]'
  fi
  printf '%s' "$__MON_NAMES_JSON"
}

monitor_height() {
  local mon="$1" full h
  full="$(monitors_full_json)"
  h="$(jq -r --arg m "$mon" '.[] | select(.name==$m) | .height // empty' <<<"$full" 2>/dev/null | head -n1 || true)"
  [[ "$h" =~ ^[0-9]+$ ]] || h=0
  printf '%s\n' "$h"
}

# -------------------------
# State
# -------------------------
ensure_state_file() {
  if [[ -s "$STATE_FILE" ]]; then
    jq -e '.' "$STATE_FILE" >/dev/null 2>&1 || rm -f "$STATE_FILE"
  fi
  if [[ ! -s "$STATE_FILE" ]]; then
    printf '{ "enabled": true, "monitors": {} }\n' >"$STATE_FILE"
  fi
}

merge_monitors_into_state() {
  local mons tmp
  mons="$(monitors_json)"
  jq -e 'type=="array" and length>0' >/dev/null 2>&1 <<<"$mons" || return 0

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
  mv -f "$tmp" "$STATE_FILE"
}

global_enabled() {
  ensure_state_file
  jq -r '(.enabled // true) | if . then "true" else "false" end' "$STATE_FILE" 2>/dev/null || printf 'true\n'
}

monitor_enabled() {
  ensure_state_file
  jq -r --arg m "$1" '(.monitors[$m].enabled // true) | if . then "true" else "false" end' "$STATE_FILE" 2>/dev/null || printf 'true\n'
}

monitor_position() {
  ensure_state_file
  jq -r --arg m "$1" '.monitors[$m].position // "top"' "$STATE_FILE" 2>/dev/null || printf 'top\n'
}

set_global_enabled() {
  local v="${1:-}" jv
  case "$v" in
    true|1|yes|on) jv=true ;;
    false|0|no|off) jv=false ;;
    *) printf 'waybar.sh: enable expects true/false\n' >&2; exit 2 ;;
  esac
  ensure_state_file
  jq --argjson v "$jv" '.enabled = $v' "$STATE_FILE" >"$STATE_FILE.tmp" && mv -f "$STATE_FILE.tmp" "$STATE_FILE"
}

set_monitor_enabled() {
  local mon="$1" v="$2" jv
  case "$v" in
    true|1|yes|on) jv=true ;;
    false|0|no|off) jv=false ;;
    *) printf 'waybar.sh: monitor enable expects true/false\n' >&2; exit 2 ;;
  esac
  ensure_state_file
  jq --arg m "$mon" --argjson v "$jv" '.monitors[$m].enabled = $v' "$STATE_FILE" >"$STATE_FILE.tmp" && mv -f "$STATE_FILE.tmp" "$STATE_FILE"
}

set_monitor_position() {
  local mon="$1" pos="$2"
  case "$pos" in top|bottom|left|right) ;; *) printf 'waybar.sh: invalid position: %s\n' "$pos" >&2; exit 2 ;; esac
  ensure_state_file
  jq --arg m "$mon" --arg p "$pos" '.monitors[$m].position = $p' "$STATE_FILE" >"$STATE_FILE.tmp" && mv -f "$STATE_FILE.tmp" "$STATE_FILE"
}

state_monitor_names_json() {
  ensure_state_file
  jq -c '(.monitors // {}) | keys' "$STATE_FILE" 2>/dev/null || printf '[]'
}

monitors_for_action() {
  local mons
  mons="$(monitors_json)"
  if jq -e 'type=="array" and length>0' >/dev/null 2>&1 <<<"$mons"; then
    printf '%s' "$mons"
  else
    state_monitor_names_json
  fi
}

# -------------------------
# Focused monitor
# -------------------------
cursor_monitor() {
  local pos x y
  pos="$(hyprctl cursorpos 2>/dev/null || true)"
  [[ -n "$pos" ]] || return 1

  x="$(printf '%s' "$pos" | awk -F',' '{gsub(/[[:space:]]/,"",$1); print $1}')"
  y="$(printf '%s' "$pos" | awk -F',' '{gsub(/[[:space:]]/,"",$2); print $2}')"
  [[ "$x" =~ ^-?[0-9]+$ && "$y" =~ ^-?[0-9]+$ ]] || return 1

  hyprctl monitors -j 2>/dev/null | jq -r --argjson x "$x" --argjson y "$y" '
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
  [[ -n "$m" ]] && { printf '%s\n' "$m"; return 0; }
  m="$(activeworkspace_monitor 2>/dev/null || true)"
  [[ -n "$m" ]] && { printf '%s\n' "$m"; return 0; }
  m="$(monitors_for_action | jq -r '.[0] // empty' 2>/dev/null || true)"
  [[ -n "$m" ]] && { printf '%s\n' "$m"; return 0; }
  return 1
}

# -------------------------
# Config generation (keeps your vertical behavior)
# -------------------------
gen_cfg_mon() {
  local mon="$1" pos="$2" out="$3" mon_h
  [[ -f "$STYLE_CSS" ]] || { printf 'waybar.sh: missing style: %s\n' "$STYLE_CSS" >&2; return 1; }

  ensure_template_json

  mon_h="$(monitor_height "$mon")"
  [[ "$mon_h" -gt 0 ]] || mon_h=1080

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
        | .height = $mon_h
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
    --argjson mon_h "$mon_h" \
    --slurpfile cfg "$TEMPLATE_JSON" \
    -f "$jqf" >"$out"

  rm -f "$jqf"

  jq -e 'type=="array" and length>0 and (.[0]|type=="object")' >/dev/null 2>&1 "$out" || {
    printf 'waybar.sh: generated config invalid for monitor %s: %s\n' "$mon" "$out" >&2
    return 1
  }
}

# -------------------------
# Start / Stop
# -------------------------
start_one() {
  local mon="$1" cfg pos pid logf

  [[ "$(global_enabled)" == "true" ]] || return 0
  [[ "$(monitor_enabled "$mon")" == "true" ]] || return 0

  pos="$(monitor_position "$mon")"
  cfg="$(cfg_file_for "$mon")"
  gen_cfg_mon "$mon" "$pos" "$cfg"

  pid="$(read_pid "$mon" 2>/dev/null || true)"
  if [[ -n "$pid" ]] && pid_cmd_has_cfg "$pid" "$cfg"; then
    return 0
  fi

  [[ -n "$pid" ]] && clear_pid "$mon"

  logf="$(log_file_for "$mon")"
  trace "start_one: $mon pos=$pos cfg=$cfg"
  nohup waybar -c "$cfg" -s "$STYLE_CSS" >>"$logf" 2>&1 &
  pid="$!"
  write_pid "$mon" "$pid"

  sleep 0.12
  if ! pid_alive "$pid"; then
    printf 'waybar.sh: waybar crashed starting monitor %s\n' "$mon" >&2
    printf 'log:\n  %s\n' "$logf" >&2
    printf 'try:\n  waybar -c %s -s %s\n' "$cfg" "$STYLE_CSS" >&2
    clear_pid "$mon"
    return 1
  fi
}

stop_one() {
  local mon="$1" pid cfg
  cfg="$(cfg_file_for "$mon")"
  pid="$(read_pid "$mon" 2>/dev/null || true)"

  if [[ -n "$pid" ]] && pid_cmd_has_cfg "$pid" "$cfg"; then
    trace "stop_one: $mon pid=$pid"
    kill "$pid" 2>/dev/null || true
    sleep 0.05
    pid_alive "$pid" && kill -9 "$pid" 2>/dev/null || true
  fi

  clear_pid "$mon"
}

start_all() {
  ensure_state_file
  merge_monitors_into_state
  ensure_template_json

  local mons m
  mons="$(monitors_for_action)"
  while read -r m; do
    [[ -n "$m" ]] || continue
    start_one "$m" || true
  done < <(jq -r '.[]' <<<"$mons")
}

stop_all() {
  local mons m
  mons="$(monitors_for_action)"
  while read -r m; do
    [[ -n "$m" ]] || continue
    stop_one "$m" || true
  done < <(jq -r '.[]' <<<"$mons")
}

restart_all() { stop_all; start_all; }

status() {
  local mons m pid cfg
  mons="$(monitors_for_action)"
  while read -r m; do
    [[ -n "$m" ]] || continue
    cfg="$(cfg_file_for "$m")"
    pid="$(read_pid "$m" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && pid_cmd_has_cfg "$pid" "$cfg"; then
      printf 'running\n'
      return 0
    fi
  done < <(jq -r '.[]' <<<"$mons")
  printf 'stopped\n'
}

toggle_mon() {
  local mon="${1:-}" pid cfg
  [[ -n "$mon" ]] || { printf 'waybar.sh: toggle-mon <MON>\n' >&2; exit 2; }

  ensure_state_file
  merge_monitors_into_state
  ensure_template_json

  cfg="$(cfg_file_for "$mon")"
  pid="$(read_pid "$mon" 2>/dev/null || true)"

  if [[ -n "$pid" ]] && pid_cmd_has_cfg "$pid" "$cfg"; then
    set_monitor_enabled "$mon" false
    stop_one "$mon"
  else
    clear_pid "$mon" 2>/dev/null || true
    set_global_enabled true
    set_monitor_enabled "$mon" true
    start_one "$mon"
  fi
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

dump_state() { ensure_state_file; cat "$STATE_FILE"; }

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
