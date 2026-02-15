#!/usr/bin/env bash
set -euo pipefail

# Hyprsunset controller with:
# - toggle on/off
# - +/- step adjustments
# - internal "offset from neutral" state so it never resumes a previous temp
# - mako notifications via notify-send

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hyprsunset"
STATE_FILE="$STATE_DIR/offset"
mkdir -p "$STATE_DIR"

# Neutral daylight baseline.
BASE_K=6500

# When toggling ON from OFF, start here (offset from BASE_K).
# Negative = warmer (lower temp). Example: 6500-1500 = 5000K.
DEFAULT_ON_OFFSET=-1500

STEP=500

notify() {
  local msg="$1"
  if command -v notify-send >/dev/null 2>&1; then
    notify-send -a "hyprsunset" -t 1400 "Night Light" "$msg"
  fi
}

have_jq() { command -v jq >/dev/null 2>&1; }

# Best-effort: return "true" / "false" / "unknown"
get_identity_state() {
  if have_jq; then
    if hyprctl -j hyprsunset >/dev/null 2>&1; then
      local v
      v="$(hyprctl -j hyprsunset | jq -r '(.identity // "unknown")' 2>/dev/null || true)"
      printf '%s\n' "$v"
      return 0
    fi
  fi
  printf '%s\n' "unknown"
}

read_offset() {
  if [[ -f "$STATE_FILE" ]]; then
    local v
    v="$(<"$STATE_FILE")"
    [[ "$v" =~ ^-?[0-9]+$ ]] && printf '%s\n' "$v" && return 0
  fi
  printf '0\n'
}

write_offset() {
  printf '%s\n' "$1" >"$STATE_FILE"
}

apply_offset() {
  local offset="$1"
  local target=$(( BASE_K + offset ))

  # Clamp to sane range; adjust if you want.
  if (( target < 1000 )); then target=1000; fi
  if (( target > 20000 )); then target=20000; fi

  hyprctl hyprsunset temperature "$target" >/dev/null
  notify "Temp: ${target}K (offset ${offset})"
}

set_off() {
  hyprctl hyprsunset identity >/dev/null
  write_offset 0
  notify "Off (identity)"
}

set_on_default() {
  write_offset "$DEFAULT_ON_OFFSET"
  apply_offset "$DEFAULT_ON_OFFSET"
}

usage() {
  cat <<'EOF'
Usage: hyprsunset_ctl.sh <cmd>

Commands:
  toggle         Toggle night light on/off (uses identity for off)
  up             Increase temperature by STEP (colder) from BASE, using internal offset
  down           Decrease temperature by STEP (warmer) from BASE, using internal offset
  off            Force off (identity) and reset offset to 0
  on             Force on to DEFAULT_ON_OFFSET
  status         Print offset + best-effort identity state

Edit in script:
  BASE_K, DEFAULT_ON_OFFSET, STEP
EOF
}

cmd="${1:-}"
case "$cmd" in
  toggle)
    id="$(get_identity_state)"
    if [[ "$id" == "true" ]]; then
      set_on_default
    elif [[ "$id" == "false" ]]; then
      set_off
    else
      # Fallback heuristic: offset==0 means "probably off"
      offset="$(read_offset)"
      if [[ "$offset" == "0" ]]; then
        set_on_default
      else
        set_off
      fi
    fi
    ;;

  up)
    off="$(get_identity_state)"
    offset="$(read_offset)"

    # If currently off/identity, start from 0 offset (BASE) then apply step.
    if [[ "$off" == "true" ]]; then
      offset=0
    fi

    offset=$(( offset + STEP ))
    write_offset "$offset"
    apply_offset "$offset"
    ;;

  down)
    off="$(get_identity_state)"
    offset="$(read_offset)"

    if [[ "$off" == "true" ]]; then
      offset=0
    fi

    offset=$(( offset - STEP ))
    write_offset "$offset"
    apply_offset "$offset"
    ;;

  off)
    set_off
    ;;

  on)
    set_on_default
    ;;

  status)
    offset="$(read_offset)"
    id="$(get_identity_state)"
    printf 'offset=%s\nidentity=%s\n' "$offset" "$id"
    ;;

  ""|-h|--help|help)
    usage
    ;;

  *)
    echo "Unknown cmd: $cmd" >&2
    usage >&2
    exit 2
    ;;
esac
