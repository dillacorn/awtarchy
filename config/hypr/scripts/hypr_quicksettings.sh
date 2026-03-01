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

MENU_ITEMS=("Brightness" "Night Light" "Vibrance" "sched-ext" "Stop sched-ext")
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

SCHED_EXT_ITEMS=(
  "scx_beerland"
  "scx_bpfland"
  "scx_cosmos"
  "scx_flash"
  "scx_lavd"
  "scx_p2dq"
  "scx_tickless"
  "scx_rustland"
  "scx_rusty"
)
SCHED_EXT_RUNNING="off"
SCHED_EXT_MODE=""
SCHED_EXT_ENABLED="0"

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

hypr_notify() {
  local msg="$1"
  local color="${2:-rgb(ff6b6b)}"
  if have_cmd hyprctl; then
    run_quiet hyprctl notify -1 7000 "$color" "$msg"
  fi
}

have_pkg_any() {
  if ! have_cmd pacman; then
    return 1
  fi
  local pkg
  for pkg in "$@"; do
    if pacman -Q "$pkg" >/dev/null 2>&1; then
      return 0
    fi
  done
  return 1
}

sudo_can_run_scxctl_noninteractive() {
  (( EUID == 0 )) && return 0
  have_cmd sudo || return 1
  sudo -n /usr/bin/scxctl list >/dev/null 2>&1
}

sudoers_included() {
  if (( EUID == 0 )); then
    grep -Eq '^[[:space:]]*(@includedir|#includedir)[[:space:]]+/etc/sudoers\.d([[:space:]]|$)' /etc/sudoers
    return $?
  fi
  sudo grep -Eq '^[[:space:]]*(@includedir|#includedir)[[:space:]]+/etc/sudoers\.d([[:space:]]|$)' /etc/sudoers
}

ensure_scxctl_nopasswd_rule() {
  local user sudoers_name sudoers_target tmpfile

  (( EUID == 0 )) && return 0

  if sudo_can_run_scxctl_noninteractive; then
    return 0
  fi

  if ! have_cmd sudo || ! have_cmd visudo; then
    MSG='sched-ext: sudo and visudo required'
    return 1
  fi

  user="$(id -un)"
  sudoers_name="90-hypr-quicksettings-scxctl-${user}"
  sudoers_target="/etc/sudoers.d/${sudoers_name}"

  printf '\033[2J\033[H'
  printf '%s\n\n' "$TITLE"
  printf 'sched-ext needs one sudo prompt to allow passwordless scxctl later.\n\n'

  if ! sudo -v; then
    MSG='sched-ext: sudo auth failed'
    return 1
  fi

  if sudo test -f "$sudoers_target" && sudo_can_run_scxctl_noninteractive; then
    return 0
  fi

  if ! sudoers_included; then
    MSG='sched-ext: /etc/sudoers.d not included'
    return 1
  fi

  tmpfile="$(mktemp)"
  printf '%s ALL=(root) NOPASSWD: /usr/bin/scxctl\n' "$user" > "$tmpfile"

  if ! visudo -c -f "$tmpfile" >/dev/null 2>&1; then
    rm -f "$tmpfile"
    MSG='sched-ext: sudoers validation failed'
    return 1
  fi

  if ! sudo install -m 440 "$tmpfile" "$sudoers_target"; then
    rm -f "$tmpfile"
    MSG='sched-ext: failed to install sudoers rule'
    return 1
  fi

  rm -f "$tmpfile"

  if ! sudo_can_run_scxctl_noninteractive; then
    MSG='sched-ext: sudoers rule installed but unusable'
    return 1
  fi

  MSG='sched-ext: scxctl sudo setup complete'
  return 0
}

scxctl_run_quiet() {
  if (( EUID == 0 )); then
    run_quiet /usr/bin/scxctl "$@"
    return $?
  fi

  if sudo_can_run_scxctl_noninteractive || ensure_scxctl_nopasswd_rule; then
    run_quiet sudo -n /usr/bin/scxctl "$@"
    return $?
  fi

  return 1
}

scxctl_run_capture() {
  local out rc=0

  if (( EUID == 0 )); then
    out="$(run_capture /usr/bin/scxctl "$@")" || rc=$?
    printf '%s' "$out"
    return "$rc"
  fi

  if ! sudo_can_run_scxctl_noninteractive; then
    return 1
  fi

  out="$(run_capture sudo -n /usr/bin/scxctl "$@")" || rc=$?
  printf '%s' "$out"
  return "$rc"
}

sched_ext_deps_ok() {
  local have_scheds=1 have_tools=1

  if have_cmd pacman; then
    have_scheds=1
    have_tools=1
    have_pkg_any scx-scheds scx-scheds-git && have_scheds=0
    have_pkg_any scx-tools scx-tools-git && have_tools=0
    if (( have_scheds == 0 && have_tools == 0 )); then
      return 0
    fi
  else
    if have_cmd scxctl; then
      return 0
    fi
  fi

  hypr_notify 'scx-scheds scx-tools both need to be installed'
  hypr_notify 'Run: sudo pacman -S scx-scheds scx-tools' 'rgb(f6c177)'
  MSG='sched-ext: missing scx-scheds/scx-tools'
  return 1
}

refresh_sched_ext() {
  local out rc=0 lowered sched mode
  SCHED_EXT_RUNNING='off'
  SCHED_EXT_MODE=''
  SCHED_EXT_ENABLED='0'

  if ! have_cmd scxctl; then
    return
  fi

  out="$(scxctl_run_capture get)" || rc=$?
  if (( rc != 0 )) || [[ -z "$out" ]]; then
    return
  fi

  lowered=$(printf '%s' "$out" | tr '[:upper:]' '[:lower:]')
  if [[ "$lowered" == *'no scx scheduler running'* ]]; then
    return
  fi

  shopt -s nocasematch
  if [[ "$out" =~ ^running[[:space:]]+(.+)[[:space:]]+in[[:space:]]+(.+)[[:space:]]+mode$ ]]; then
    sched="${BASH_REMATCH[1]}"
    mode="${BASH_REMATCH[2]}"
  elif [[ "$out" =~ ^running[[:space:]]+(.+)$ ]]; then
    sched="${BASH_REMATCH[1]}"
    mode=''
  else
    shopt -u nocasematch
    return
  fi
  shopt -u nocasematch

  sched=${sched#scx_}
  sched=${sched#SCX_}
  sched=${sched,,}
  if [[ -n "$sched" ]]; then
    SCHED_EXT_RUNNING="scx_${sched}"
    SCHED_EXT_ENABLED='1'
  fi
  if [[ -n "$mode" ]]; then
    SCHED_EXT_MODE="${mode,,}"
  fi
}

refresh_all() {
  refresh_brightness
  refresh_sunset
  refresh_vibrance
  refresh_sched_ext
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
      if [[ "$SUN_ENABLED" == '1' ]]; then
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

format_sched_ext() {
  if [[ "$SCHED_EXT_ENABLED" == '1' ]]; then
    if [[ -n "$SCHED_EXT_MODE" ]]; then
      printf "running '%s' (%s)" "$SCHED_EXT_RUNNING" "$SCHED_EXT_MODE"
    else
      printf "running '%s'" "$SCHED_EXT_RUNNING"
    fi
  else
    printf 'off'
  fi
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
      'sched-ext') value="$(format_sched_ext)" ;;
      'Stop sched-ext') value='restore default scheduler' ;;
      *) value='' ;;
    esac

    printf -v line '%-15s %s' "$label" "$value"
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

sched_ext_mode_for() {
  case "$1" in
    scx_cosmos|scx_flash|scx_lavd|scx_p2dq|scx_tickless)
      printf 'gaming'
      ;;
    *)
      printf 'auto'
      ;;
  esac
}

sched_ext_switch_or_start() {
  local sched_full="$1" sched_short mode verb
  sched_short="${sched_full#scx_}"
  mode="$(sched_ext_mode_for "$sched_full")"

  if [[ "$SCHED_EXT_ENABLED" == '1' ]]; then
    verb='switch'
  else
    verb='start'
  fi

  if scxctl_run_quiet "$verb" --sched "$sched_short" --mode "$mode"; then
    refresh_sched_ext
    MSG="sched-ext: ${sched_full} (${mode})"
    return 0
  fi

  if scxctl_run_quiet "$verb" --sched "$sched_short"; then
    refresh_sched_ext
    MSG="sched-ext: ${sched_full}"
    return 0
  fi

  refresh_sched_ext
  MSG='sched-ext: failed'
  return 1
}

sched_ext_stop() {
  if ! sched_ext_deps_ok; then
    return 1
  fi

  if [[ "$SCHED_EXT_ENABLED" != '1' ]]; then
    MSG='sched-ext: already off'
    return 0
  fi

  if scxctl_run_quiet stop; then
    refresh_sched_ext
    MSG='sched-ext: stopped'
    return 0
  fi

  refresh_sched_ext
  MSG='sched-ext: stop failed'
  return 1
}

draw_sched_ext_menu() {
  local idx="$1" i label line cols
  cols=$(tput cols 2>/dev/null || printf '80')

  printf '\033[2J\033[H\033[?25l'
  printf '%s\n' "$TITLE"
  printf '%s\n\n' 'sched-ext picker   Up/Down: select   Space/Enter: apply   q/Esc: back'

  for i in "${!SCHED_EXT_ITEMS[@]}"; do
    label="${SCHED_EXT_ITEMS[$i]}"
    line="$label"
    if [[ "$label" == "$SCHED_EXT_RUNNING" ]]; then
      line+="  [running]"
    fi
    if (( i == idx )); then
      printf '\033[7m> %s\033[0m\n' "$line"
    else
      printf '  %s\n' "$line"
    fi
  done

  printf '\n'
  printf '%.*s' "$cols" 'Selecting a scheduler uses gaming mode where supported, otherwise auto.'
}

sched_ext_menu() {
  local idx=0 key current i

  current="$SCHED_EXT_RUNNING"
  for i in "${!SCHED_EXT_ITEMS[@]}"; do
    if [[ "${SCHED_EXT_ITEMS[$i]}" == "$current" ]]; then
      idx=$i
      break
    fi
  done

  while true; do
    draw_sched_ext_menu "$idx"
    key="$(read_key)" || break

    case "$key" in
      q|Q|$'\e')
        break
        ;;
      $'\e[A'|k)
        (( idx-- )) || true
        if (( idx < 0 )); then
          idx=$((${#SCHED_EXT_ITEMS[@]} - 1))
        fi
        ;;
      $'\e[B'|j)
        (( idx++ )) || true
        if (( idx >= ${#SCHED_EXT_ITEMS[@]} )); then
          idx=0
        fi
        ;;
      $' '|$'\n'|$'\r')
        if ! sched_ext_deps_ok; then
          break
        fi
        sched_ext_switch_or_start "${SCHED_EXT_ITEMS[$idx]}"
        break
        ;;
    esac
  done
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
    'sched-ext')
      sched_ext_menu
      refresh_sched_ext
      ;;
    'Stop sched-ext')
      sched_ext_stop
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
