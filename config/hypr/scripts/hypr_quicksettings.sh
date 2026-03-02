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
SHOULD_QUIT=0

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
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hypr_quicksettings"
SCHED_EXT_STATE_FILE="${STATE_DIR}/sched_ext_state.sh"
declare -A SCHED_EXT_PROFILE_MAP=()
declare -A SCHED_EXT_CUSTOM_ARGS_MAP=()
declare -A SCHED_EXT_LAVD_AUTOPOWER_MAP=()

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

trim_spaces() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

sched_ext_state_init_defaults() {
  local sched
  for sched in "${SCHED_EXT_ITEMS[@]}"; do
    [[ -v SCHED_EXT_PROFILE_MAP["$sched"] ]] || SCHED_EXT_PROFILE_MAP["$sched"]='Default'
    [[ -v SCHED_EXT_CUSTOM_ARGS_MAP["$sched"] ]] || SCHED_EXT_CUSTOM_ARGS_MAP["$sched"]=''
    [[ -v SCHED_EXT_LAVD_AUTOPOWER_MAP["$sched"] ]] || SCHED_EXT_LAVD_AUTOPOWER_MAP["$sched"]='0'
  done
}

sched_ext_state_load() {
  sched_ext_state_init_defaults
  if [[ -f "$SCHED_EXT_STATE_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$SCHED_EXT_STATE_FILE"
    sched_ext_state_init_defaults
  fi
}

sched_ext_state_save() {
  local tmpfile
  mkdir -p "$STATE_DIR"
  tmpfile="$(mktemp)"
  {
    printf '#!/usr/bin/env bash
'
    declare -p SCHED_EXT_PROFILE_MAP
    declare -p SCHED_EXT_CUSTOM_ARGS_MAP
    declare -p SCHED_EXT_LAVD_AUTOPOWER_MAP
  } > "$tmpfile"
  install -m 600 "$tmpfile" "$SCHED_EXT_STATE_FILE"
  rm -f "$tmpfile"
}

sched_ext_profiles_for() {
  case "$1" in
    scx_bpfland)
      printf '%s
' 'Default' 'Low Latency' 'Power Save' 'Server'
      ;;
    scx_cosmos)
      printf '%s
' 'Default' 'Auto' 'Gaming' 'Power Save' 'Low Latency' 'Server'
      ;;
    scx_flash)
      printf '%s
' 'Default' 'Low Latency' 'Gaming' 'Power Save' 'Server'
      ;;
    scx_lavd)
      printf '%s
' 'Default' 'Performance' 'Power Save'
      ;;
    scx_p2dq)
      printf '%s
' 'Default' 'Gaming' 'Low Latency' 'Power Save' 'Server'
      ;;
    scx_tickless)
      printf '%s
' 'Default' 'Gaming' 'Power Save' 'Low Latency' 'Server'
      ;;
    *)
      printf '%s
' 'Default'
      ;;
  esac
}

sched_ext_profile_index() {
  local sched="$1" needle="$2" idx=0 item
  while IFS= read -r item; do
    if [[ "$item" == "$needle" ]]; then
      printf '%s' "$idx"
      return 0
    fi
    (( idx++ )) || true
  done < <(sched_ext_profiles_for "$sched")
  printf '0'
}

sched_ext_has_extra_profiles() {
  local sched="$1"
  local -a profiles=()
  mapfile -t profiles < <(sched_ext_profiles_for "$sched")
  (( ${#profiles[@]} > 1 ))
}

sched_ext_profile_cycle() {
  local sched="$1" dir="$2" current idx count next
  local -a profiles=()
  mapfile -t profiles < <(sched_ext_profiles_for "$sched")
  count=${#profiles[@]}
  (( count > 1 )) || return 0
  current="${SCHED_EXT_PROFILE_MAP[$sched]:-Default}"
  idx="$(sched_ext_profile_index "$sched" "$current")"
  next=$(( idx + dir ))
  if (( next < 0 )); then
    next=$(( count - 1 ))
  elif (( next >= count )); then
    next=0
  fi
  SCHED_EXT_PROFILE_MAP["$sched"]="${profiles[$next]}"
  sched_ext_state_save
}

sched_ext_flags_for_profile() {
  local sched="$1" profile="$2"
  case "$sched:$profile" in
    scx_bpfland:Low\ Latency) printf '%s' '-m,performance,-w' ;;
    scx_bpfland:Power\ Save) printf '%s' '-s,20000,-m,powersave,-I,100,-t,100' ;;
    scx_bpfland:Server) printf '%s' '-s,20000,-S' ;;

    scx_cosmos:Auto) printf '%s' '-s,20000,-d,-c,0,-p,0' ;;
    scx_cosmos:Gaming) printf '%s' '-c,0,-p,0' ;;
    scx_cosmos:Power\ Save) printf '%s' '-m,powersave,-d,-p,5000' ;;
    scx_cosmos:Low\ Latency) printf '%s' '-m,performance,-c,0,-p,0,-w' ;;
    scx_cosmos:Server) printf '%s' '-s,20000' ;;

    scx_flash:Low\ Latency) printf '%s' '-m,performance,-w,-C,0' ;;
    scx_flash:Gaming) printf '%s' '-m,all' ;;
    scx_flash:Power\ Save) printf '%s' '-m,powersave,-I,10000,-t,10000,-s,10000,-S,1000' ;;
    scx_flash:Server) printf '%s' '-m,all,-s,20000,-S,1000,-I,-1,-D,-L' ;;

    scx_lavd:Performance) printf '%s' '--performance' ;;
    scx_lavd:Power\ Save) printf '%s' '--powersave' ;;

    scx_p2dq:Gaming) printf '%s' '--task-slice,true,-f,--sched-mode,performance' ;;
    scx_p2dq:Low\ Latency) printf '%s' '-y,-f,--task-slice,true' ;;
    scx_p2dq:Power\ Save) printf '%s' '--sched-mode,efficiency' ;;
    scx_p2dq:Server) printf '%s' '--keep-running' ;;

    scx_tickless:Gaming) printf '%s' '-f,5000,-s,5000' ;;
    scx_tickless:Power\ Save) printf '%s' '-f,50' ;;
    scx_tickless:Low\ Latency) printf '%s' '-f,5000,-s,1000' ;;
    scx_tickless:Server) printf '%s' '-f,100' ;;

    *) printf '%s' '' ;;
  esac
}

sched_ext_normalize_args() {
  local raw="$1" out
  raw="${raw//$'
'/ }"
  raw="$(trim_spaces "$raw")"
  if [[ -z "$raw" ]]; then
    printf '%s' ''
    return 0
  fi
  if [[ "$raw" == *','* ]]; then
    out="$(printf '%s' "$raw" | sed -E 's/[[:space:]]*,[[:space:]]*/,/g; s/,+/,/g; s/^,+//; s/,+$//')"
  else
    out="$(printf '%s' "$raw" | sed -E 's/[[:space:]]+/,/g; s/,+/,/g; s/^,+//; s/,+$//')"
  fi
  printf '%s' "$out"
}

sched_ext_effective_args() {
  local sched="$1" profile preset custom combined autopower
  profile="${SCHED_EXT_PROFILE_MAP[$sched]:-Default}"
  preset="$(sched_ext_flags_for_profile "$sched" "$profile")"
  custom="$(sched_ext_normalize_args "${SCHED_EXT_CUSTOM_ARGS_MAP[$sched]:-}")"
  combined="$preset"

  if [[ "$sched" == 'scx_lavd' ]] && [[ "${SCHED_EXT_LAVD_AUTOPOWER_MAP[$sched]:-0}" == '1' ]]; then
    autopower='--autopower'
    if [[ -n "$combined" ]]; then
      combined+=",${autopower}"
    else
      combined="$autopower"
    fi
  fi

  if [[ -n "$custom" ]]; then
    if [[ -n "$combined" ]]; then
      combined+=",${custom}"
    else
      combined="$custom"
    fi
  fi

  printf '%s' "$combined"
}

sched_ext_config_summary() {
  local sched="$1" profile custom summary
  profile="${SCHED_EXT_PROFILE_MAP[$sched]:-Default}"
  custom="$(sched_ext_normalize_args "${SCHED_EXT_CUSTOM_ARGS_MAP[$sched]:-}")"
  summary="$profile"
  if [[ "$sched" == 'scx_lavd' ]] && [[ "${SCHED_EXT_LAVD_AUTOPOWER_MAP[$sched]:-0}" == '1' ]]; then
    summary+='+autopower'
  fi
  if [[ -n "$custom" ]]; then
    summary+='+custom'
  fi
  printf '%s' "$summary"
}

sched_ext_reset_config() {
  local sched="$1"
  SCHED_EXT_PROFILE_MAP["$sched"]='Default'
  SCHED_EXT_CUSTOM_ARGS_MAP["$sched"]=''
  SCHED_EXT_LAVD_AUTOPOWER_MAP["$sched"]='0'
  sched_ext_state_save
}

prompt_text() {
  local prompt="$1" default="$2" input
  printf '[2J[H'
  printf '%s

' "$TITLE"
  printf '%s
' "$prompt"
  printf 'Current [%s]
> ' "$default"
  IFS= read -r input || true
  if [[ -z "$input" ]]; then
    REPLY="$default"
  else
    REPLY="$input"
  fi
}

sched_ext_show_help() {
  local sched="$1" out rc=0 key lines cols height offset end i
  local -a help_lines=()

  if ! have_cmd "$sched"; then
    MSG="sched-ext: ${sched} not installed"
    return 1
  fi

  if command -v timeout >/dev/null 2>&1; then
    out="$(timeout "${CMD_TIMEOUT}" "$sched" --help 2>&1)" || rc=$?
  else
    out="$("$sched" --help 2>&1)" || rc=$?
  fi
  if [[ -z "$out" ]]; then
    if (( rc != 0 )); then
      MSG="sched-ext: ${sched} --help failed"
      return 1
    fi
    out="No help output from ${sched} --help"
  fi

  mapfile -t help_lines < <(printf '%s
' "$out")
  lines=$(tput lines 2>/dev/null || printf '24')
  cols=$(tput cols 2>/dev/null || printf '80')
  height=$(( lines - 5 ))
  (( height < 8 )) && height=8
  offset=0

  while true; do
    printf '[2J[H[?25l'
    printf '%s
' "$TITLE"
    printf 'Local help: %s   j/k or arrows scroll   PgUp/PgDn jump   q: quit   b/Esc: back\n\n' "$sched"
    end=$(( offset + height ))
    if (( end > ${#help_lines[@]} )); then
      end=${#help_lines[@]}
    fi
    for (( i=offset; i<end; i++ )); do
      printf '%.*s
' "$cols" "${help_lines[$i]}"
    done
    key="$(read_key)" || break
    case "$key" in
      q|Q)
        SHOULD_QUIT=1
        return 0
        ;;
      b|B|$'\e')
        break
        ;;
      $'\e[A'|k)
        (( offset-- )) || true
        (( offset < 0 )) && offset=0
        ;;
      $'\e[B'|j)
        if (( offset + height < ${#help_lines[@]} )); then
          (( offset++ )) || true
        fi
        ;;
      $'\e[5'|$'\e[5~')
        offset=$(( offset - height ))
        (( offset < 0 )) && offset=0
        ;;
      $'\e[6'|$'\e[6~')
        offset=$(( offset + height ))
        if (( offset > ${#help_lines[@]} - 1 )); then
          offset=$(( ${#help_lines[@]} > height ? ${#help_lines[@]} - height : 0 ))
        fi
        ;;
    esac
  done
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
  printf '%s\n\n' 'Up/Down: select   Left/Right: adjust   Space: toggle/edit   r: refresh   q: quit'

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

sched_ext_switch_or_start() {
  local sched_full="$1" sched_short verb args summary
  sched_short="${sched_full#scx_}"
  args="$(sched_ext_effective_args "$sched_full")"
  summary="$(sched_ext_config_summary "$sched_full")"

  if [[ "$SCHED_EXT_ENABLED" == '1' ]]; then
    verb='switch'
  else
    verb='start'
  fi

  if [[ -n "$args" ]]; then
    if scxctl_run_quiet "$verb" --sched "$sched_short" --args "$args"; then
      refresh_sched_ext
      MSG="sched-ext: ${sched_full} [${summary}]"
      return 0
    fi
  else
    if scxctl_run_quiet "$verb" --sched "$sched_short"; then
      refresh_sched_ext
      MSG="sched-ext: ${sched_full} [${summary}]"
      return 0
    fi
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
  local idx="$1" i label line cols summary
  cols=$(tput cols 2>/dev/null || printf '80')

  printf '[2J[H[?25l'
  printf '%s
' "$TITLE"
  printf '%s\n\n' 'sched-ext picker   Up/Down: select   Space: apply   e: edit   h: help   q: quit   b/Esc: back'

  for i in "${!SCHED_EXT_ITEMS[@]}"; do
    label="${SCHED_EXT_ITEMS[$i]}"
    summary="$(sched_ext_config_summary "$label")"
    line="$label  [${summary}]"
    if [[ "$label" == "$SCHED_EXT_RUNNING" ]]; then
      line+="  [running]"
    fi
    if (( i == idx )); then
      printf '[7m> %s[0m
' "$line"
    else
      printf '  %s
' "$line"
    fi
  done

  printf '
'
  printf '%.*s
' "$cols" 'Preset flags come from the current CachyOS sched-ext guide. Custom args are appended via scxctl --args.'
  printf '%.*s' "$cols" 'Custom args may be comma-separated or space-separated. Press h for local scheduler help.'
}

draw_sched_ext_editor() {
  local sched="$1" idx="$2" cols profile custom autopower effective
  local -a entries=()
  cols=$(tput cols 2>/dev/null || printf '80')
  profile="${SCHED_EXT_PROFILE_MAP[$sched]:-Default}"
  custom="$(sched_ext_normalize_args "${SCHED_EXT_CUSTOM_ARGS_MAP[$sched]:-}")"
  autopower='off'
  [[ "${SCHED_EXT_LAVD_AUTOPOWER_MAP[$sched]:-0}" == '1' ]] && autopower='on'
  effective="$(sched_ext_effective_args "$sched")"

  if sched_ext_has_extra_profiles "$sched"; then
    entries+=("Profile: ${profile}")
  else
    entries+=("Profile: none available")
  fi
  entries+=("Custom args: ${custom:-<none>}")
  if [[ "$sched" == 'scx_lavd' ]]; then
    entries+=("Autopower: ${autopower}")
  fi
  entries+=("View local --help")
  entries+=("Reset saved config")
  entries+=("Back")

  printf '[2J[H[?25l'
  printf '%s
' "$TITLE"
  printf 'sched-ext editor: %s
' "$sched"
  printf '%s\n\n' 'Up/Down: select   Left/Right: change/toggle   Space: apply/toggle   e: edit custom args   h: help   q: quit   b/Esc: back'

  local i line
  for i in "${!entries[@]}"; do
    line="${entries[$i]}"
    if (( i == idx )); then
      printf '[7m> %s[0m
' "$line"
    else
      printf '  %s
' "$line"
    fi
  done

  printf '
'
  printf '%.*s
' "$cols" "Effective args: ${effective:-<none>}"
  printf '%.*s' "$cols" 'Use custom args for any scheduler-specific flags not covered by the preset profiles.'
}

sched_ext_toggle_lavd_autopower() {
  local sched="$1"
  if [[ "${SCHED_EXT_LAVD_AUTOPOWER_MAP[$sched]:-0}" == '1' ]]; then
    SCHED_EXT_LAVD_AUTOPOWER_MAP["$sched"]='0'
  else
    SCHED_EXT_LAVD_AUTOPOWER_MAP["$sched"]='1'
  fi
  sched_ext_state_save
}

sched_ext_edit_menu() {
  local sched="$1" idx=0 key count help_idx reset_idx back_idx
  if [[ "$sched" == 'scx_lavd' ]]; then
    count=6
    help_idx=3
  else
    count=5
    help_idx=2
  fi
  reset_idx=$(( help_idx + 1 ))
  back_idx=$(( help_idx + 2 ))

  while true; do
    draw_sched_ext_editor "$sched" "$idx"
    key="$(read_key)" || break
    case "$key" in
      q|Q)
        SHOULD_QUIT=1
        return 0
        ;;
      b|B|$'\e')
        break
        ;;
      $'\e[A'|k)
        (( idx-- )) || true
        if (( idx < 0 )); then
          idx=$(( count - 1 ))
        fi
        ;;
      $'\e[B'|j)
        (( idx++ )) || true
        if (( idx >= count )); then
          idx=0
        fi
        ;;
      $'\e[D')
        if (( idx == 0 )); then
          sched_ext_profile_cycle "$sched" -1
        elif [[ "$sched" == 'scx_lavd' ]] && (( idx == 2 )); then
          sched_ext_toggle_lavd_autopower "$sched"
        fi
        ;;
      $'\e[C')
        if (( idx == 0 )); then
          sched_ext_profile_cycle "$sched" 1
        elif [[ "$sched" == 'scx_lavd' ]] && (( idx == 2 )); then
          sched_ext_toggle_lavd_autopower "$sched"
        fi
        ;;
      $' ')
        if (( idx == 0 )); then
          sched_ext_profile_cycle "$sched" 1
        elif (( idx == 1 )); then
          prompt_text 'Enter custom scxctl args. Comma-separated is preferred. Blank clears them.' "$(sched_ext_normalize_args "${SCHED_EXT_CUSTOM_ARGS_MAP[$sched]:-}")"
          SCHED_EXT_CUSTOM_ARGS_MAP["$sched"]="$(sched_ext_normalize_args "$REPLY")"
          sched_ext_state_save
        elif [[ "$sched" == 'scx_lavd' ]] && (( idx == 2 )); then
          sched_ext_toggle_lavd_autopower "$sched"
        elif (( idx == help_idx )); then
          sched_ext_show_help "$sched"
          (( SHOULD_QUIT == 1 )) && return 0
        elif (( idx == reset_idx )); then
          sched_ext_reset_config "$sched"
          MSG="sched-ext: reset ${sched} config"
        elif (( idx == back_idx )); then
          break
        fi
        ;;
      e|E)
        if (( idx == 1 )); then
          prompt_text 'Enter custom scxctl args. Comma-separated is preferred. Blank clears them.' "$(sched_ext_normalize_args "${SCHED_EXT_CUSTOM_ARGS_MAP[$sched]:-}")"
          SCHED_EXT_CUSTOM_ARGS_MAP["$sched"]="$(sched_ext_normalize_args "$REPLY")"
          sched_ext_state_save
        fi
        ;;
      h|H)
        sched_ext_show_help "$sched"
        ;;
    esac
  done
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
      q|Q)
        SHOULD_QUIT=1
        return 0
        ;;
      b|B|$'\e')
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
      $' ')
        if ! sched_ext_deps_ok; then
          break
        fi
        sched_ext_switch_or_start "${SCHED_EXT_ITEMS[$idx]}"
        break
        ;;
      e|E)
        sched_ext_edit_menu "${SCHED_EXT_ITEMS[$idx]}"
        (( SHOULD_QUIT == 1 )) && return 0
        ;;
      h|H)
        sched_ext_show_help "${SCHED_EXT_ITEMS[$idx]}"
        (( SHOULD_QUIT == 1 )) && return 0
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
      (( SHOULD_QUIT == 1 )) && return
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
  sched_ext_state_load
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
    esac

    if (( SHOULD_QUIT == 1 )); then
      break
    fi
  done
}

main() {
  case "${1:-}" in
    --ui) ui_loop ;;
    *) launch_terminal ;;
  esac
}

main "$@"
