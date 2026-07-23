#!/usr/bin/env bash
set -euo pipefail

BRIGHTNESS_SCRIPT="${HYPR_BRIGHTNESS_SCRIPT:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/hypr-ddc-brightness.sh}"
BRIGHTNESS_MONITOR="${HYPR_BRIGHTNESS_MONITOR:-}"
SUNSET_SCRIPT="${HYPR_SUNSET_SCRIPT:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/hyprsunset_ctl.sh}"
VIBRANCE_SCRIPT="${HYPR_VIBRANCE_SCRIPT:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/vibrance_shader.sh}"
HYPR_LUA="${HYPRLAND_LUA:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprland.lua}"
HYPR_CONF="${HYPRLAND_CONF:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprland.conf}"
VIBRANCE_SHADER="${VIBRANCE_SHADER_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr/shaders/vibrance}"

BRIGHTNESS_STEP="${HYPR_BRIGHTNESS_STEP:-5}"
CMD_TIMEOUT="${HYPR_SETTINGS_TIMEOUT:-6}"
TITLE="Hypr Quick Settings"
TERM_CLASS="hypr_quicksettings"

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

MOUSE_BUTTON=0
MOUSE_X=0
MOUSE_Y=0
MOUSE_RELEASE=0
UI_MENU_FIRST_ROW=4
SCHED_MENU_FIRST_ROW=4
SCHED_EDITOR_FIRST_ROW=5
declare -a BRIGHTNESS_CLICK_STARTS=()
declare -a BRIGHTNESS_CLICK_ENDS=()
declare -a BRIGHTNESS_CLICK_VALUES=()

mouse_enable() {
  printf '\033[?1000h\033[?1006h'
}

mouse_disable() {
  printf '\033[?1000l\033[?1006l'
}

cleanup() {
  mouse_disable
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

brightness_capture() {
  if [[ -n "$BRIGHTNESS_MONITOR" ]]; then
    run_capture "$BRIGHTNESS_SCRIPT" --monitor "$BRIGHTNESS_MONITOR" "$@"
  else
    run_capture "$BRIGHTNESS_SCRIPT" "$@"
  fi
}

brightness_quiet() {
  if [[ -n "$BRIGHTNESS_MONITOR" ]]; then
    run_quiet "$BRIGHTNESS_SCRIPT" --monitor "$BRIGHTNESS_MONITOR" "$@"
  else
    run_quiet "$BRIGHTNESS_SCRIPT" "$@"
  fi
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

close_existing_quicksettings() {
  local clients address
  local closed=1

  have_cmd hyprctl || return 1
  have_cmd python || return 1

  clients="$(hyprctl -j clients 2>/dev/null)" || return 1
  while IFS= read -r address; do
    [[ -n "$address" ]] || continue
    if run_quiet hyprctl dispatch "hl.dsp.window.close({ window = \"address:${address}\" })"; then
      closed=0
    fi
  done < <(
    printf '%s' "$clients" | python -c '
import json
import sys

window_class = sys.argv[1]
try:
    clients = json.load(sys.stdin)
except Exception:
    raise SystemExit(1)

for client in clients:
    if client.get("class") == window_class or client.get("initialClass") == window_class:
        address = client.get("address")
        if address:
            print(address)
' "$TERM_CLASS"
  )

  return "$closed"
}

launch_terminal() {
  local self
  self="$(readlink -f "${BASH_SOURCE[0]}")"

  if close_existing_quicksettings; then
    return 0
  fi

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
  out="$(brightness_capture status)" || rc=$?
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

  if [[ -f "$HYPR_LUA" ]]; then
    if python - "$HYPR_LUA" <<'PY_QS_VIB' >/dev/null 2>&1
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text()
line_re = re.compile(r'^\s*hl\.config\(\{\s*decoration\s*=\s*\{\s*screen_shader\s*=\s*("(?:\\.|[^"\\])*")\s*\}\s*\}\s*\)\s*$', re.M)
for m in line_re.finditer(text):
    raw = m.group(1)
    try:
        value = bytes(raw[1:-1], "utf-8").decode("unicode_escape")
    except Exception:
        value = raw[1:-1]
    if value.rstrip().endswith('/shaders/vibrance'):
        raise SystemExit(0)
raise SystemExit(1)
PY_QS_VIB
    then
      VIB_ENABLED="1"
    else
      VIB_ENABLED="0"
    fi
  elif [[ -f "$HYPR_CONF" ]]; then
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
  mouse_disable
  printf '\033[2J\033[H\033[?25h'
  printf '%s\n\n' "$TITLE"
  printf '%s\n' "$prompt"
  printf 'Current [%s]\n> ' "$default"
  IFS= read -r input || true
  mouse_enable
  if [[ -z "$input" ]]; then
    REPLY="$default"
  else
    REPLY="$input"
  fi
}

sched_ext_show_help() {
  local sched="$1" out rc=0 key lines cols view_cols height offset end i max_offset total_lines
  local line
  local -a help_lines=() view_lines=()

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

  mapfile -t help_lines < <(printf '%s\n' "$out")
  offset=0

  while true; do
    lines=$(tput lines 2>/dev/null || printf '24')
    cols=$(tput cols 2>/dev/null || printf '80')
    height=$(( lines - 6 ))
    (( height < 8 )) && height=8
    view_cols=$(( cols > 2 ? cols - 1 : 1 ))

    view_lines=()
    for line in "${help_lines[@]}"; do
      if [[ -z "$line" ]]; then
        view_lines+=("")
        continue
      fi
      while (( ${#line} > view_cols )); do
        view_lines+=("${line:0:view_cols}")
        line=${line:view_cols}
      done
      view_lines+=("$line")
    done

    total_lines=${#view_lines[@]}
    max_offset=$(( total_lines > height ? total_lines - height : 0 ))
    (( offset > max_offset )) && offset=$max_offset
    end=$(( offset + height ))
    (( end > total_lines )) && end=$total_lines

    printf '\033[2J\033[H\033[?25l'
    printf '%s\n' "$TITLE"
    printf 'Local help: %s   wheel/arrows scroll   PgUp/PgDn jump   b: back   Esc/q: close\n' "$sched"
    printf 'Showing %d-%d of %d\n\n' "$(( total_lines == 0 ? 0 : offset + 1 ))" "$end" "$total_lines"
    for (( i=offset; i<end; i++ )); do
      printf '%s\n' "${view_lines[$i]}"
    done

    key="$(read_key)" || break
    case "$key" in
      q|Q|$'\e')
        SHOULD_QUIT=1
        return 0
        ;;
      b|B)
        break
        ;;
      $'\e[A'|k)
        (( offset-- )) || true
        (( offset < 0 )) && offset=0
        ;;
      $'\e[B'|j)
        (( offset < max_offset )) && (( offset++ )) || true
        ;;
      $'\e[5~')
        offset=$(( offset - height ))
        (( offset < 0 )) && offset=0
        ;;
      $'\e[6~')
        offset=$(( offset + height ))
        (( offset > max_offset )) && offset=$max_offset
        ;;
      $'\e[H'|$'\e[1~'|$'\eOH')
        offset=0
        ;;
      $'\e[F'|$'\e[4~'|$'\eOF')
        offset=$max_offset
        ;;
      $'\e[<'*)
        if parse_mouse_event "$key" && (( MOUSE_RELEASE == 0 )); then
          case "$MOUSE_BUTTON" in
            64)
              (( offset-- )) || true
              (( offset < 0 )) && offset=0
              ;;
            65)
              (( offset < max_offset )) && (( offset++ )) || true
              ;;
          esac
        fi
        ;;
    esac
  done
}

format_brightness() {
  printf '%s %s/%s' "$BR_CONN" "$BR_CUR" "$BR_MAX"
}

sunset_is_on() {
  case "$SUN_IDENTITY" in
    true) return 1 ;;
    false) return 0 ;;
  esac
  [[ "$SUN_ENABLED" == '1' ]]
}

format_sunset() {
  local onoff mood r g b temp

  if sunset_is_on; then
    onoff='on'
    temp=0
    if [[ "$SUN_TEMP" =~ ([0-9]{3,5}) ]]; then
      temp=${BASH_REMATCH[1]}
    fi

    if (( temp >= 5500 )); then
      mood='cool'
      r=170 g=205 b=255
    elif (( temp >= 4500 )); then
      mood='soft'
      r=255 g=221 b=170
    elif (( temp >= 3500 )); then
      mood='warm'
      r=255 g=170 b=95
    else
      mood='cozy'
      r=255 g=105 b=55
    fi
  else
    onoff='off'
    mood='idle'
    r=90 g=90 b=90
  fi

  printf '%s (%s) %-5s \033[48;2;%d;%d;%dm   \033[0m' "$SUN_TEMP" "$onoff" "$mood" "$r" "$g" "$b"
}

format_vibrance() {
  case "$VIB_ENABLED" in
    1)
      printf '%s (on)  \033[48;2;255;0;150m \033[48;2;140;60;255m \033[48;2;0;220;255m \033[48;2;70;255;130m \033[48;2;255;220;0m \033[0m' "$VIB_VAL"
      ;;
    0)
      printf '%s (off) \033[48;2;75;75;75m     \033[0m' "$VIB_VAL"
      ;;
    *)
      printf '%s (unknown) \033[48;2;75;75;75m     \033[0m' "$VIB_VAL"
      ;;
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

build_brightness_line() {
  local base line plain_len sep token start end pct current_pct current_step

  printf -v base '%-15s %s  [' 'Brightness' "$(format_brightness)"
  line="$base"
  plain_len=${#base}
  BRIGHTNESS_CLICK_STARTS=()
  BRIGHTNESS_CLICK_ENDS=()
  BRIGHTNESS_CLICK_VALUES=()

  current_step=-1
  if [[ "$BR_CUR" =~ ^[0-9]+$ ]] && [[ "$BR_MAX" =~ ^[0-9]+$ ]] && (( BR_MAX > 0 )); then
    current_pct=$(( (BR_CUR * 100 + BR_MAX / 2) / BR_MAX ))
    current_step=$(( ((current_pct + BRIGHTNESS_STEP / 2) / BRIGHTNESS_STEP) * BRIGHTNESS_STEP ))
    (( current_step > 100 )) && current_step=100
  fi

  for (( pct=0; pct<=100; pct+=BRIGHTNESS_STEP )); do
    sep=' '
    token="$pct"
    start=$(( 2 + plain_len + ${#sep} + 1 ))
    end=$(( start + ${#token} - 1 ))
    BRIGHTNESS_CLICK_STARTS+=("$start")
    BRIGHTNESS_CLICK_ENDS+=("$end")
    BRIGHTNESS_CLICK_VALUES+=("$pct")

    line+="$sep"
    if (( pct == current_step )); then
      line+=$'\033[1;4m'
      line+="$token"
      line+=$'\033[0m'
    else
      line+="$token"
    fi
    plain_len=$(( plain_len + ${#sep} + ${#token} ))
  done

  line+=' ]'
  REPLY="$line"
}

draw_ui() {
  local i label value line cols
  cols=$(tput cols 2>/dev/null || printf '80')

  printf '\033[2J\033[H\033[?25l'
  printf '%s\n' "$TITLE"
  printf '%s\n\n' 'Click or Up/Down: select   Left/Right: adjust   Enter: toggle/edit   Esc/q: close'

  for i in "${!MENU_ITEMS[@]}"; do
    label=${MENU_ITEMS[$i]}
    case "$label" in
      Brightness)
        build_brightness_line
        line="$REPLY"
        ;;
      'Night Light')
        value="$(format_sunset)"
        printf -v line '%-15s %s' "$label" "$value"
        ;;
      Vibrance)
        value="$(format_vibrance)"
        printf -v line '%-15s %s' "$label" "$value"
        ;;
      'sched-ext')
        value="$(format_sched_ext)"
        printf -v line '%-15s %s' "$label" "$value"
        ;;
      'Stop sched-ext')
        value='restore default scheduler'
        printf -v line '%-15s %s' "$label" "$value"
        ;;
      *)
        line="$label"
        ;;
    esac

    if (( i == SEL )); then
      printf '\033[1;7m> \033[0m%s\n' "$line"
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

  case "$key" in
    $'\r'|$'\n')
      printf '%s' '__ENTER__'
      return 0
      ;;
    $'\e')
      ;;
    *)
      printf '%s' "$key"
      return 0
      ;;
  esac

  if ! IFS= read -rsN1 -t 0.03 rest; then
    printf '%s' "$key"
    return 0
  fi

  key+="$rest"
  if [[ "$rest" == '[' ]]; then
    while IFS= read -rsN1 -t 0.03 rest; do
      key+="$rest"
      if [[ "$rest" =~ [A-Za-z~] ]]; then
        break
      fi
    done
  elif [[ "$rest" == 'O' ]]; then
    if IFS= read -rsN1 -t 0.03 rest; then
      key+="$rest"
    fi
  fi

  printf '%s' "$key"
}

parse_mouse_event() {
  local seq="$1" payload final button x y

  [[ "$seq" == $'\e[<'* ]] || return 1
  final=${seq: -1}
  [[ "$final" == 'M' || "$final" == 'm' ]] || return 1

  payload=${seq#$'\e[<'}
  payload=${payload%M}
  payload=${payload%m}
  IFS=';' read -r button x y <<< "$payload"
  [[ "$button" =~ ^[0-9]+$ && "$x" =~ ^[0-9]+$ && "$y" =~ ^[0-9]+$ ]] || return 1

  MOUSE_BUTTON=$button
  MOUSE_X=$x
  MOUSE_Y=$y
  MOUSE_RELEASE=0
  [[ "$final" == 'm' ]] && MOUSE_RELEASE=1
  return 0
}

handle_main_mouse() {
  local key="$1" idx i

  parse_mouse_event "$key" || return 1
  (( MOUSE_RELEASE == 0 )) || return 0

  if (( MOUSE_Y >= UI_MENU_FIRST_ROW && MOUSE_Y < UI_MENU_FIRST_ROW + ${#MENU_ITEMS[@]} )); then
    idx=$(( MOUSE_Y - UI_MENU_FIRST_ROW ))
    SEL=$idx
  else
    return 0
  fi

  case "$MOUSE_BUTTON" in
    64)
      do_right
      return 0
      ;;
    65)
      do_left
      return 0
      ;;
  esac

  (( (MOUSE_BUTTON & 3) == 0 )) || return 0

  if (( SEL == 0 )); then
    for i in "${!BRIGHTNESS_CLICK_VALUES[@]}"; do
      if (( MOUSE_X >= BRIGHTNESS_CLICK_STARTS[i] && MOUSE_X <= BRIGHTNESS_CLICK_ENDS[i] )); then
        brightness_set_percent "${BRIGHTNESS_CLICK_VALUES[$i]}"
        return 0
      fi
    done
  fi

  do_action
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

  printf '\033[2J\033[H\033[?25l'
  printf '%s\n' "$TITLE"
  printf '%s\n\n' 'sched-ext picker   Enter/click: apply   e: edit   h: help   b: back   Esc/q: close'

  for i in "${!SCHED_EXT_ITEMS[@]}"; do
    label="${SCHED_EXT_ITEMS[$i]}"
    summary="$(sched_ext_config_summary "$label")"
    line="$label  [${summary}]"
    if [[ "$label" == "$SCHED_EXT_RUNNING" ]]; then
      line+="  [running]"
    fi
    if (( i == idx )); then
      printf '\033[1;7m> \033[0m%s\n' "$line"
    else
      printf '  %s\n' "$line"
    fi
  done

  printf '\n'
  printf '%.*s\n' "$cols" 'Preset flags come from the current CachyOS sched-ext guide. Custom args are appended via scxctl --args.'
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

  printf '\033[2J\033[H\033[?25l'
  printf '%s\n' "$TITLE"
  printf 'sched-ext editor: %s\n' "$sched"
  printf '%s\n\n' 'Click or Up/Down: select   Left/Right: change   Enter: apply   b: back   Esc/q: close'

  local i line
  for i in "${!entries[@]}"; do
    line="${entries[$i]}"
    if (( i == idx )); then
      printf '\033[1;7m> \033[0m%s\n' "$line"
    else
      printf '  %s\n' "$line"
    fi
  done

  printf '\n'
  printf '%.*s\n' "$cols" "Effective args: ${effective:-<none>}"
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

sched_ext_editor_activate() {
  local sched="$1" idx="$2" help_idx="$3" reset_idx="$4" back_idx="$5"
  SCHED_EDITOR_BACK=0

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
  elif (( idx == reset_idx )); then
    sched_ext_reset_config "$sched"
    MSG="sched-ext: reset ${sched} config"
  elif (( idx == back_idx )); then
    SCHED_EDITOR_BACK=1
  fi
}

sched_ext_edit_menu() {
  local sched="$1" idx=0 key count help_idx reset_idx back_idx clicked_idx
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
      q|Q|$'\e')
        SHOULD_QUIT=1
        return 0
        ;;
      b|B)
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
      __ENTER__|' ')
        sched_ext_editor_activate "$sched" "$idx" "$help_idx" "$reset_idx" "$back_idx"
        (( SHOULD_QUIT == 1 )) && return 0
        (( SCHED_EDITOR_BACK == 1 )) && break
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
        (( SHOULD_QUIT == 1 )) && return 0
        ;;
      $'\e[<'*)
        if parse_mouse_event "$key" && (( MOUSE_RELEASE == 0 )); then
          case "$MOUSE_BUTTON" in
            64)
              (( idx-- )) || true
              (( idx < 0 )) && idx=$(( count - 1 ))
              ;;
            65)
              (( idx++ )) || true
              (( idx >= count )) && idx=0
              ;;
            *)
              if (( (MOUSE_BUTTON & 3) == 0 )) && (( MOUSE_Y >= SCHED_EDITOR_FIRST_ROW && MOUSE_Y < SCHED_EDITOR_FIRST_ROW + count )); then
                clicked_idx=$(( MOUSE_Y - SCHED_EDITOR_FIRST_ROW ))
                idx=$clicked_idx
                sched_ext_editor_activate "$sched" "$idx" "$help_idx" "$reset_idx" "$back_idx"
                (( SHOULD_QUIT == 1 )) && return 0
                (( SCHED_EDITOR_BACK == 1 )) && break
              fi
              ;;
          esac
        fi
        ;;
    esac
  done
}

sched_ext_menu() {
  local idx=0 key current i clicked_idx

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
        SHOULD_QUIT=1
        return 0
        ;;
      b|B)
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
      __ENTER__|' ')
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
      $'\e[<'*)
        if parse_mouse_event "$key" && (( MOUSE_RELEASE == 0 )); then
          case "$MOUSE_BUTTON" in
            64)
              (( idx-- )) || true
              (( idx < 0 )) && idx=$((${#SCHED_EXT_ITEMS[@]} - 1))
              ;;
            65)
              (( idx++ )) || true
              (( idx >= ${#SCHED_EXT_ITEMS[@]} )) && idx=0
              ;;
            *)
              if (( (MOUSE_BUTTON & 3) == 0 )) && (( MOUSE_Y >= SCHED_MENU_FIRST_ROW && MOUSE_Y < SCHED_MENU_FIRST_ROW + ${#SCHED_EXT_ITEMS[@]} )); then
                clicked_idx=$(( MOUSE_Y - SCHED_MENU_FIRST_ROW ))
                idx=$clicked_idx
                if ! sched_ext_deps_ok; then
                  break
                fi
                sched_ext_switch_or_start "${SCHED_EXT_ITEMS[$idx]}"
                break
              fi
              ;;
          esac
        fi
        ;;
    esac
  done
}

brightness_set_abs() {
  brightness_quiet set "$1"
}

brightness_set_percent() {
  local percent="$1" target

  if [[ ! "$BR_MAX" =~ ^[0-9]+$ ]]; then
    refresh_brightness
  fi
  if [[ ! "$BR_MAX" =~ ^[0-9]+$ ]]; then
    MSG='brightness: bad status'
    return 1
  fi

  (( percent < 0 )) && percent=0
  (( percent > 100 )) && percent=100
  target=$(( (BR_MAX * percent + 50) / 100 ))

  if brightness_set_abs "$target"; then
    BR_CUR="$target"
    MSG="brightness: ${percent}%"
    return 0
  fi

  MSG='brightness: failed'
  refresh_brightness
  return 1
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
  mouse_disable
  printf '\033[2J\033[H\033[?25h'
  printf '%s\n\n' "$TITLE"
  printf '%s [%s]: ' "$prompt" "$default"
  IFS= read -r input || true
  mouse_enable
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
  mouse_enable

  while true; do
    draw_ui
    MSG=''
    local key
    key="$(read_key)" || break

    case "$key" in
      q|Q|$'\e')
        break
        ;;
      r|R)
        refresh_all
        ;;
      __ENTER__|' ')
        do_action
        if (( SHOULD_QUIT == 1 )); then
          break
        fi
        ;;
      $'\e[A'|k)
        move_sel_up
        ;;
      $'\e[B'|j)
        move_sel_down
        ;;
      $'\e[D'|h)
        do_left
        ;;
      $'\e[C'|l)
        do_right
        ;;
      $'\e[<'*)
        handle_main_mouse "$key"
        ;;
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
