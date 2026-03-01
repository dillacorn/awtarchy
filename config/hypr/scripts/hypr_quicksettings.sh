#!/usr/bin/env bash
set -euo pipefail

BRIGHTNESS_SCRIPT="${HYPR_BRIGHTNESS_SCRIPT:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/hypr-ddc-brightness.sh}"
SUNSET_SCRIPT="${HYPR_SUNSET_SCRIPT:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/hyprsunset_ctl.sh}"
VIBRANCE_SCRIPT="${HYPR_VIBRANCE_SCRIPT:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/vibrance_shader.sh}"
HYPR_CONF="${HYPRLAND_CONF:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprland.conf}"
VIBRANCE_SHADER="${VIBRANCE_SHADER_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr/shaders/vibrance}"

BRIGHTNESS_STEP="${HYPR_BRIGHTNESS_STEP:-5}"
CMD_TIMEOUT="${HYPR_SETTINGS_TIMEOUT:-6}"
TITLE="Hypr Quick Settings"
TERM_CLASS="hypr-quicksettings"

MENU_ITEMS=("Brightness" "Night Light" "Vibrance")
SEL=0
MSG=""

BR_CONN="N/A"
BR_CUR="N/A"
BR_MAX="N/A"
SUN_TEMP="N/A"
SUN_IDENTITY="unknown"
SUN_ENABLED="0"
VIB_VAL="N/A"
VIB_ENABLED="?"

cleanup() {
  printf '\033[?25h\033[0m\033[2J\033[H'
}

run_quiet() {
  local rc=0
  "$@" >/dev/null 2>&1 || rc=$?
  return "$rc"
}

run_capture() {
  local out rc=0
  if command -v timeout >/dev/null 2>&1; then
    out="$(timeout "${CMD_TIMEOUT}" "$@" 2>/dev/null)" || rc=$?
  else
    out="$("$@" 2>/dev/null)" || rc=$?
  fi
  printf '%s' "$out"
  return "$rc"
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

launch_terminal() {
  local self
  self="$(readlink -f "${BASH_SOURCE[0]}")"

  if [[ -t 1 ]]; then
    exec "$self" --ui
  fi

  if have_cmd kitty; then
    exec kitty --class "$TERM_CLASS" -e "$self" --ui
  fi
  if have_cmd foot; then
    exec foot --app-id="$TERM_CLASS" "$self" --ui
  fi
  if have_cmd alacritty; then
    exec alacritty --class "$TERM_CLASS" -e "$self" --ui
  fi
  if have_cmd wezterm; then
    exec wezterm start --class "$TERM_CLASS" -- "$self" --ui
  fi
  if have_cmd konsole; then
    exec konsole --appname "$TERM_CLASS" -e "$self" --ui
  fi
  if have_cmd gnome-terminal; then
    exec gnome-terminal --title="$TERM_CLASS" -- "$self" --ui
  fi

  exec xterm -T "$TERM_CLASS" -e "$self" --ui
}

require_files() {
  local missing=0
  for p in "$BRIGHTNESS_SCRIPT" "$SUNSET_SCRIPT" "$VIBRANCE_SCRIPT"; do
    if [[ ! -e "$p" ]]; then
      printf 'missing: %s\n' "$p" >&2
      missing=1
    fi
  done
  return "$missing"
}

parse_kv_into() {
  local text="$1"
  local prefix="$2"
  local line key val
  while IFS= read -r line; do
    [[ "$line" == *=* ]] || continue
    key=${line%%=*}
    val=${line#*=}
    key=${key//[^a-zA-Z0-9_]/_}
    printf -v "${prefix}_${key}" '%s' "$val"
  done <<< "$text"
}

refresh_brightness() {
  local out rc=0
  BR_CONN="N/A"
  BR_CUR="N/A"
  BR_MAX="N/A"
  out="$(run_capture "$BRIGHTNESS_SCRIPT" status)" || rc=$?
  if (( rc == 0 )) && [[ -n "$out" ]]; then
    local BR_conn="N/A" BR_cur="N/A" BR_max="N/A"
    parse_kv_into "$out" BR
    BR_CONN="${BR_conn:-N/A}"
    BR_CUR="${BR_cur:-N/A}"
    BR_MAX="${BR_max:-N/A}"
  fi
}

refresh_sunset() {
  local out rc=0
  SUN_TEMP="N/A"
  SUN_IDENTITY="unknown"
  SUN_ENABLED="0"
  out="$(run_capture "$SUNSET_SCRIPT" status)" || rc=$?
  if (( rc == 0 )) && [[ -n "$out" ]]; then
    local SUN_temp="N/A" SUN_identity="unknown" SUN_enabled="0"
    parse_kv_into "$out" SUN
    SUN_TEMP="${SUN_temp:-N/A}"
    SUN_IDENTITY="${SUN_identity:-unknown}"
    SUN_ENABLED="${SUN_enabled:-0}"
  fi
}

refresh_vibrance() {
  VIB_VAL="N/A"
  VIB_ENABLED="?"

  if [[ -f "$VIBRANCE_SHADER" ]]; then
    local line value
    while IFS= read -r line; do
      case "$line" in
        *'#define VIBRANCE '*)
          value=${line##*#define VIBRANCE }
          if [[ "$value" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
            printf -v VIB_VAL '%.2f' "$value"
          else
            VIB_VAL="$value"
          fi
          break
          ;;
      esac
    done < "$VIBRANCE_SHADER"
  fi

  if [[ -f "$HYPR_CONF" ]]; then
    if grep -Eq '^[[:space:]]*screen_shader[[:space:]]*=.*(/|^)shaders/vibrance([[:space:]]|$|#)' "$HYPR_CONF"; then
      VIB_ENABLED="1"
    else
      VIB_ENABLED="0"
    fi
  fi
}

refresh_all() {
  refresh_brightness
  refresh_sunset
  refresh_vibrance
}

format_brightness() {
  printf '%s %s/%s' "$BR_CONN" "$BR_CUR" "$BR_MAX"
}

format_sunset() {
  local onoff
  case "$SUN_IDENTITY" in
    true) onoff='off' ;;
    false) onoff='on' ;;
    *)
      if [[ "$SUN_ENABLED" == "1" ]]; then
        onoff='on'
      else
        onoff='off'
      fi
      ;;
  esac
  printf '%s (%s)' "$SUN_TEMP" "$onoff"
}

format_vibrance() {
  case "$VIB_ENABLED" in
    1) printf '%s (on)' "$VIB_VAL" ;;
    0) printf '%s (off)' "$VIB_VAL" ;;
    *) printf '%s (unknown)' "$VIB_VAL" ;;
  esac
}

draw_ui() {
  local i label value line cols
  cols=$(tput cols 2>/dev/null || printf '80')

  printf '\033[2J\033[H\033[?25l'
  printf '%s\n' "$TITLE"
  printf '%s\n\n' 'Up/Down: select   Left/Right: adjust   Space: toggle/edit   Enter: also works   r: refresh   q: quit'

  for i in "${!MENU_ITEMS[@]}"; do
    label=${MENU_ITEMS[$i]}
    case "$label" in
      Brightness) value="$(format_brightness)" ;;
      'Night Light') value="$(format_sunset)" ;;
      Vibrance) value="$(format_vibrance)" ;;
      *) value='' ;;
    esac

    printf -v line '%-11s %s' "$label" "$value"
    if (( i == SEL )); then
      printf '\033[7m> %s\033[0m\n' "$line"
    else
      printf '  %s\n' "$line"
    fi
  done

  printf '\n'
  if [[ -n "$MSG" ]]; then
    printf '%.*s' "$cols" "$MSG"
  fi
}

read_key() {
  local key rest
  IFS= read -rsN1 key || return 1
  if [[ "$key" == $'\e' ]]; then
    if IFS= read -rsN1 -t 0.001 rest; then
      key+="$rest"
      if [[ "$rest" == '[' ]]; then
        if IFS= read -rsN1 -t 0.001 rest; then
          key+="$rest"
        fi
      fi
    fi
  fi
  printf '%s' "$key"
}

move_sel_up() {
  (( SEL-- )) || true
  if (( SEL < 0 )); then
    SEL=$((${#MENU_ITEMS[@]} - 1))
  fi
}

move_sel_down() {
  (( SEL++ )) || true
  if (( SEL >= ${#MENU_ITEMS[@]} )); then
    SEL=0
  fi
}

brightness_set_abs() {
  run_quiet "$BRIGHTNESS_SCRIPT" set "$1"
}

brightness_adjust() {
  local delta="$1" cur max target
  if [[ ! "$BR_CUR" =~ ^[0-9]+$ ]] || [[ ! "$BR_MAX" =~ ^[0-9]+$ ]]; then
    refresh_brightness
  fi
  if [[ ! "$BR_CUR" =~ ^[0-9]+$ ]] || [[ ! "$BR_MAX" =~ ^[0-9]+$ ]]; then
    MSG='brightness: bad status'
    return
  fi

  cur=$BR_CUR
  max=$BR_MAX
  target=$(( cur + delta ))
  (( target < 0 )) && target=0
  (( target > max )) && target=$max

  if brightness_set_abs "$target"; then
    BR_CUR="$target"
  else
    MSG='brightness: failed'
    refresh_brightness
  fi
}

prompt_number() {
  local prompt="$1" default="$2" input
  printf '\033[2J\033[H'
  printf '%s\n\n' "$TITLE"
  printf '%s [%s]: ' "$prompt" "$default"
  IFS= read -r input || true
  if [[ -z "$input" ]]; then
    REPLY="$default"
  else
    REPLY="$input"
  fi
}

do_action() {
  case "${MENU_ITEMS[$SEL]}" in
    Brightness)
      if [[ ! "$BR_CUR" =~ ^[0-9]+$ ]] || [[ ! "$BR_MAX" =~ ^[0-9]+$ ]]; then
        refresh_brightness
      fi
      if [[ ! "$BR_CUR" =~ ^[0-9]+$ ]] || [[ ! "$BR_MAX" =~ ^[0-9]+$ ]]; then
        MSG='brightness: bad status'
        return
      fi
      prompt_number "Set brightness (0-$BR_MAX)" "$BR_CUR"
      if [[ ! "$REPLY" =~ ^[0-9]+$ ]]; then
        MSG='brightness: numbers only'
        return
      fi
      local val="$REPLY"
      (( val < 0 )) && val=0
      (( val > BR_MAX )) && val=$BR_MAX
      if brightness_set_abs "$val"; then
        BR_CUR="$val"
      else
        MSG='brightness: failed'
        refresh_brightness
      fi
      ;;
    'Night Light')
      if run_quiet "$SUNSET_SCRIPT" toggle; then
        refresh_sunset
      else
        MSG='night light: failed'
        refresh_sunset
      fi
      ;;
    Vibrance)
      if run_quiet "$VIBRANCE_SCRIPT" toggle; then
        refresh_vibrance
      else
        MSG='vibrance: failed'
        refresh_vibrance
      fi
      ;;
  esac
}

do_left() {
  case "${MENU_ITEMS[$SEL]}" in
    Brightness)
      brightness_adjust "-$BRIGHTNESS_STEP"
      ;;
    'Night Light')
      if run_quiet "$SUNSET_SCRIPT" down; then
        refresh_sunset
      else
        MSG='night light: failed'
        refresh_sunset
      fi
      ;;
    Vibrance)
      if run_quiet "$VIBRANCE_SCRIPT" down; then
        refresh_vibrance
      else
        MSG='vibrance: failed'
        refresh_vibrance
      fi
      ;;
  esac
}

do_right() {
  case "${MENU_ITEMS[$SEL]}" in
    Brightness)
      brightness_adjust "$BRIGHTNESS_STEP"
      ;;
    'Night Light')
      if run_quiet "$SUNSET_SCRIPT" up; then
        refresh_sunset
      else
        MSG='night light: failed'
        refresh_sunset
      fi
      ;;
    Vibrance)
      if run_quiet "$VIBRANCE_SCRIPT" up; then
        refresh_vibrance
      else
        MSG='vibrance: failed'
        refresh_vibrance
      fi
      ;;
  esac
}

ui_loop() {
  trap cleanup EXIT INT TERM
  require_files || exit 1
  refresh_all

  while true; do
    draw_ui
    MSG=''
    local key
    key="$(read_key)" || break

    case "$key" in
      q|Q) break ;;
      r|R) refresh_all ;;
      $' ') do_action ;;
      $'\e[A'|k) move_sel_up ;;
      $'\e[B'|j) move_sel_down ;;
      $'\e[D'|h) do_left ;;
      $'\e[C'|l) do_right ;;
      $'\n'|$'\r') do_action ;;
    esac
  done
}

main() {
  case "${1:-}" in
    --ui) ui_loop ;;
    *) launch_terminal ;;
  esac
}

main "$@"
