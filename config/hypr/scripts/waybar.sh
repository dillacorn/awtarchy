#!/usr/bin/env bash
# FILE: ~/.config/hypr/scripts/waybar.sh
#
# Generates per-monitor Waybar config from ~/.config/waybar/config (JSON array).
# Vertical (left/right) overrides:
#   - remove hyprland/window
#   - replace custom/clock-toggle with clock (time only, no icon)
#   - group/ws-arrows.orientation = vertical
#   - stack cpu/mem/backlight/battery icons above values
#   - temp: force icon above degrees, strip non-numeric glyphs from cpu_temp.sh output
#   - wireplumber: hide icon (volume only)

set -euo pipefail

WAYBAR_BIN="${WAYBAR_BIN:-waybar}"
TEMPLATE_CFG="${TEMPLATE_CFG:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar/config}"

CACHE_DIR="${CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/waybar}"
STATE_FILE="${STATE_FILE:-${CACHE_DIR}/state.json}"
GENERATED_CFG="${GENERATED_CFG:-${CACHE_DIR}/config.generated.json}"

# sizing
WAYBAR_VERTICAL_WIDTH="${WAYBAR_VERTICAL_WIDTH:-36}"          # px when position is left/right
WAYBAR_HORIZONTAL_HEIGHT_DEFAULT="${WAYBAR_HORIZONTAL_HEIGHT_DEFAULT:-28}"

KILL_ALL_WAYBAR="${KILL_ALL_WAYBAR:-1}"   # 1 = pkill -x waybar before starting

need() { command -v "$1" >/dev/null 2>&1 || { printf 'waybar.sh: missing: %s\n' "$1" >&2; exit 127; }; }
need "$WAYBAR_BIN"
need hyprctl
need jq
need pgrep
need pkill
need mktemp
need nohup

mkdir -p "$CACHE_DIR"

monitors_array_json() {
  hyprctl monitors -j | jq -c '[.[].name]'
}

ensure_state() {
  local mons tmp
  mons="$(monitors_array_json)"

  if [[ ! -f "$STATE_FILE" ]]; then
    jq -n --argjson mons "$mons" '
      {
        enabled: true,
        monitors: ($mons | map({(.): {position:"top"}}) | add)
      }
    ' > "$STATE_FILE"
    return
  fi

  tmp="$(mktemp)"
  jq --argjson mons "$mons" '
    . as $s
    | ($s.enabled // true) as $enabled
    | ($s.monitors // {}) as $m
    | ($mons | map({(.): {position:"top"}}) | add) as $defaults
    | { enabled: $enabled, monitors: ($defaults * $m) }
  ' "$STATE_FILE" > "$tmp"
  mv "$tmp" "$STATE_FILE"
}

state_enabled() { ensure_state; jq -r '.enabled // true' "$STATE_FILE"; }

set_enabled() {
  local val="${1:-}" tmp jval
  case "$val" in
    true|1|yes|on) jval=true ;;
    false|0|no|off) jval=false ;;
    *) printf 'waybar.sh: set_enabled expects true/false\n' >&2; exit 2 ;;
  esac
  ensure_state
  tmp="$(mktemp)"
  jq --argjson v "$jval" '.enabled = $v' "$STATE_FILE" > "$tmp"
  mv "$tmp" "$STATE_FILE"
}

focused_monitor() { hyprctl activeworkspace -j | jq -r '.monitor'; }

get_pos() {
  local mon="${1:-}"
  [[ -n "$mon" ]] || { printf 'waybar.sh: getpos requires <MON>\n' >&2; exit 2; }
  ensure_state
  jq -r --arg m "$mon" '.monitors[$m].position // "top"' "$STATE_FILE"
}

set_pos() {
  local mon="${1:-}" pos="${2:-}"
  [[ -n "$mon" && -n "$pos" ]] || { printf 'waybar.sh: setpos requires <MON> <POS>\n' >&2; exit 2; }
  case "$pos" in top|bottom|left|right) ;; *) printf 'waybar.sh: invalid pos: %s\n' "$pos" >&2; exit 2 ;; esac
  ensure_state
  local tmp
  tmp="$(mktemp)"
  jq --arg m "$mon" --arg p "$pos" '.monitors[$m].position = $p' "$STATE_FILE" > "$tmp"
  mv "$tmp" "$STATE_FILE"
}

flip_pos_value() {
  local cur="${1:-top}"
  case "$cur" in
    top) echo bottom ;;
    bottom) echo top ;;
    left) echo right ;;
    right) echo left ;;
    *) echo bottom ;;
  esac
}

generate_config() {
  ensure_state
  [[ -f "$TEMPLATE_CFG" ]] || { printf 'waybar.sh: template config not found: %s\n' "$TEMPLATE_CFG" >&2; exit 1; }

  local base mons tmp jqf
  base="$(jq -c '.[0]' "$TEMPLATE_CFG")"
  mons="$(monitors_array_json)"
  tmp="$(mktemp)"
  jqf="$(mktemp)"

  cat >"$jqf" <<'JQ'
def trim: gsub("^\\s+|\\s+$";"");
def norm: (trim | gsub("\\s+";" "));
def toks: (norm | split(" "));
def lasttok: (toks | .[-1]);
def firsttok: (toks | .[0]);

($st[0].monitors // {}) as $mmap
| ($base.height // $hdef) as $hheight
| [ $mons[] as $m
    | ($base
        | .output = [$m]
        | .position = ($mmap[$m].position // "top")

        | if (.position == "left" or .position == "right") then
            # size
            del(.height) | .width = ($base.width // $vwidth)

            # remove window title
            | .["modules-center"] = ((.["modules-center"] // []) | map(select(. != "hyprland/window")))

            # replace clock-toggle with clock (time only)
            | .["modules-right"] = ((.["modules-right"] // []) | map(if .=="custom/clock-toggle" then "clock" else . end))
            | .clock = { "format":"{:%H:%M}", "tooltip": false }

            # stack ws arrows vertically
            | (if .["group/ws-arrows"]? then .["group/ws-arrows"].orientation = "vertical" else . end)

            # cpu: icon above usage (extract last token glyph from existing format)
            | (if .cpu? and .cpu.format? then
                 (.cpu.format | lasttok) as $ico
                 | .cpu.format = ($ico + "\n{usage}")
               else . end)

            # memory: icon above value (fix trailing-space bug)
            | (if .memory? and .memory.format? then
                 (.memory.format | lasttok) as $ico
                 | .memory.format = ($ico + "\n{}")
               else . end)

            # temp: icon above degrees, strip any glyphs from script output
            | (if .["custom/cputemp"]? then
                 .["custom/cputemp"].format = "\uf2c8\n{}"
                 | .["custom/cputemp"].exec = "$HOME/.config/waybar/scripts/cpu_temp.sh | sed -E s/[^0-9.+°-]//g"
               else . end)

            # backlight: icon above percent
            | (if .backlight? then .backlight.format = "{icon}\n{percent}" else . end)

            # battery: icon above value; charging/plugged keep their special icon
            | (if .battery? then
                 .battery.format = "{icon}\n{capacity}"
                 | .battery["format-full"] = "{icon}\n{capacity}"
                 | .battery["format-alt"] = "{icon}\n{time}"
                 | (if .battery["format-charging"]? then
                      (.battery["format-charging"] | firsttok) as $ico
                      | .battery["format-charging"] = ($ico + "\n{capacity}")
                    else . end)
                 | (if .battery["format-plugged"]? then
                      (.battery["format-plugged"] | firsttok) as $ico
                      | .battery["format-plugged"] = ($ico + "\n{capacity}")
                    else . end)
               else . end)

            # volume: hide icon (volume only)
            | (if .wireplumber? then
                 .wireplumber.format = "{volume}"
                 | .wireplumber["format-bluetooth"] = "{volume}"
                 | .wireplumber["format-muted"] = "mute"
                 | .wireplumber["format-bluetooth-muted"] = "mute"
               else . end)

          else
            del(.width) | .height = $hheight
          end
      )
  ]
JQ

  jq -n \
    --argjson base "$base" \
    --argjson mons "$mons" \
    --slurpfile st "$STATE_FILE" \
    --argjson vwidth "$WAYBAR_VERTICAL_WIDTH" \
    --argjson hdef "$WAYBAR_HORIZONTAL_HEIGHT_DEFAULT" \
    -f "$jqf" > "$tmp"

  rm -f "$jqf"
  mv "$tmp" "$GENERATED_CFG"
}

is_running() { pgrep -x waybar >/dev/null 2>&1; }

start() {
  ensure_state
  [[ "$(state_enabled)" == "true" ]] || exit 0
  generate_config
  [[ "$KILL_ALL_WAYBAR" == "1" ]] && pkill -x waybar 2>/dev/null || true
  nohup "$WAYBAR_BIN" -c "$GENERATED_CFG" >/dev/null 2>&1 &
  disown
}

stop() { pkill -x waybar 2>/dev/null || true; }
restart() { stop; start; }

toggle() {
  if is_running; then
    set_enabled false
    stop
  else
    set_enabled true
    start
  fi
}

status() { is_running && echo running || echo stopped; }

flip_focused() {
  local mon cur nxt
  mon="$(focused_monitor)"
  cur="$(get_pos "$mon")"
  nxt="$(flip_pos_value "$cur")"
  set_pos "$mon" "$nxt"
  is_running && restart || true
}

case "${1:-}" in
  start) start ;;
  stop) stop ;;
  restart) restart ;;
  toggle) toggle ;;
  status) status ;;
  enable) set_enabled true ;;
  disable) set_enabled false ;;
  focused-monitor) focused_monitor ;;
  getpos) get_pos "${2:-}" ;;
  getpos-focused) get_pos "$(focused_monitor)" ;;
  setpos) set_pos "${2:-}" "${3:-}" ;;
  setpos-focused) set_pos "$(focused_monitor)" "${2:-}" ;;
  flip-focused) flip_focused ;;
  dump-state) ensure_state; cat "$STATE_FILE" ;;
  *)
    cat >&2 <<'USAGE'
usage: waybar.sh <command>

commands:
  start | stop | restart | toggle | status
  enable | disable
  focused-monitor
  getpos <MON> | getpos-focused
  setpos <MON> <top|bottom|left|right> | setpos-focused <top|bottom|left|right>
  flip-focused
  dump-state
USAGE
    exit 2
    ;;
esac
