#!/usr/bin/env bash
# github.com/dillacorn/awtarchy/tree/main/config/hypr/scripts
# ~/.config/hypr/scripts/toggle_animations.sh

set -euo pipefail

HYPRCTL="$(command -v hyprctl || true)"
NOTIFY_SEND="$(command -v notify-send || true)"

HYPRLOCK_CONF="${HYPRLOCK_CONF:-$HOME/.config/hypr/hyprlock.conf}"
STATE_FILE="${STATE_FILE:-${XDG_RUNTIME_DIR:-/tmp}/hypr-animations-enabled}"

if [[ -z "$HYPRCTL" ]]; then
  echo "hyprctl not found in PATH" >&2
  exit 1
fi

normalize_state() {
  case "${1:-}" in
    1|true|yes|on) echo "1" ;;
    0|false|no|off) echo "0" ;;
    *) echo "" ;;
  esac
}

read_live_state_json() {
  "$HYPRCTL" getoption "animations.enabled" -j 2>/dev/null \
    | sed -nE 's/.*"(int|bool)"[[:space:]]*:[[:space:]]*"?([0-9]+|true|false)"?.*/\2/p' \
    | head -n1
}

read_live_state_fallback() {
  "$HYPRCTL" getoption "animations.enabled" 2>/dev/null \
    | awk '
        /int:/ {
          for (i=1; i<=NF; i++) {
            if ($i ~ /^[0-9]+$/) {
              print $i
              exit
            }
          }
        }

        /bool:/ {
          for (i=1; i<=NF; i++) {
            if ($i == "true") {
              print 1
              exit
            }
            if ($i == "false") {
              print 0
              exit
            }
          }
        }
      '
}

read_state() {
  local state=""

  state="$(normalize_state "$(read_live_state_json || true)")"
  if [[ -n "$state" ]]; then
    echo "$state"
    return 0
  fi

  state="$(normalize_state "$(read_live_state_fallback || true)")"
  if [[ -n "$state" ]]; then
    echo "$state"
    return 0
  fi

  if [[ -f "$STATE_FILE" ]]; then
    state="$(normalize_state "$(cat "$STATE_FILE" 2>/dev/null || true)")"
    if [[ -n "$state" ]]; then
      echo "$state"
      return 0
    fi
  fi

  echo "1"
}

apply_hyprland_animation_state() {
  local target="$1"
  local lua_bool

  if [[ "$target" == "1" ]]; then
    lua_bool="true"
  else
    lua_bool="false"
  fi

  "$HYPRCTL" eval "hl.config({ animations = { enabled = ${lua_bool} } })"
}

update_hyprlock_animations_enabled() {
  local enabled_bool="$1"
  local conf="$2"

  [[ -f "$conf" ]] || return 0

  local dir base ts bak tmp
  dir="$(dirname -- "$conf")"
  base="$(basename -- "$conf")"
  ts="$(date +%Y%m%d-%H%M%S)"
  bak="$dir/${base}.bak.${ts}"
  tmp="$(mktemp "${dir}/.${base}.tmp.XXXXXX")"

  cp -a -- "$conf" "$bak"

  awk -v target="$enabled_bool" '
    BEGIN {
      in_anim = 0
      saw_anim_block = 0
      saw_enabled_in_block = 0
    }

    {
      line = $0

      if (!in_anim && line ~ /^[ \t]*animations[ \t]*\{[ \t]*$/) {
        in_anim = 1
        saw_anim_block = 1
        print line
        next
      }

      if (in_anim) {
        if (line ~ /^[ \t]*enabled[ \t]*=[ \t]*(true|false)[ \t]*$/) {
          match(line, /^[ \t]*/)
          indent = substr(line, RSTART, RLENGTH)
          print indent "enabled = " target
          saw_enabled_in_block = 1
          next
        }

        if (line ~ /^[ \t]*\}[ \t]*$/) {
          if (!saw_enabled_in_block) {
            print "    enabled = " target
          }

          in_anim = 0
          print line
          next
        }

        print line
        next
      }

      print line
    }

    END {
      if (!saw_anim_block) {
        print ""
        print "animations {"
        print "    enabled = " target
        print "}"
      }
    }
  ' "$conf" > "$tmp"

  mv -f -- "$tmp" "$conf"
}

state="$(read_state)"

if [[ "$state" == "1" ]]; then
  target="0"
  msg="OFF"
  hyprlock_enabled="false"
else
  target="1"
  msg="ON"
  hyprlock_enabled="true"
fi

apply_hyprland_animation_state "$target"
printf '%s\n' "$target" > "$STATE_FILE"

update_hyprlock_animations_enabled "$hyprlock_enabled" "$HYPRLOCK_CONF" || true

if [[ -n "$NOTIFY_SEND" ]]; then
  "$NOTIFY_SEND" -a "Hyprland" \
    -r 49110 \
    -t 1000 \
    "Animations: $msg" \
    "animations.enabled = $target"
fi
