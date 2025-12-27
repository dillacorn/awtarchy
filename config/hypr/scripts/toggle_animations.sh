#!/usr/bin/env bash
# github.com/dillacorn/awtarchy/tree/main/config/hypr/scripts
# ~/.config/hypr/scripts/toggle_animations.sh

set -euo pipefail

HYPRCTL="$(command -v hyprctl || true)"
NOTIFY_SEND="$(command -v notify-send || true)"
HYPRLOCK_CONF="${HYPRLOCK_CONF:-$HOME/.config/hypr/hyprlock.conf}"

if [[ -z "$HYPRCTL" ]]; then
  echo "hyprctl not found in PATH" >&2
  exit 1
fi

read_state_json() {
  "$HYPRCTL" getoption "animations:enabled" -j 2>/dev/null \
    | sed -n 's/.*"int":[[:space:]]*\([0-9]\+\).*/\1/p'
}

read_state_fallback() {
  "$HYPRCTL" getoption "animations:enabled" 2>/dev/null \
    | awk '{
        for(i=1;i<=NF;i++){
          if ($i ~ /^[0-9]+$/) { print $i; exit }
          if ($i ~ /[0-9]+:/)  { gsub(/[^0-9]/,"",$i); print $i; exit }
        }
      }'
}

update_hyprlock_animations_enabled() {
  local enabled_bool="$1"   # "true" or "false"
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
    function ltrim(s){ sub(/^[ \t\r\n]+/, "", s); return s }
    function rtrim(s){ sub(/[ \t\r\n]+$/, "", s); return s }
    function trim(s){ return rtrim(ltrim(s)) }

    BEGIN {
      in_anim = 0
      saw_anim_block = 0
      changed = 0
      saw_enabled_in_block = 0
    }

    {
      line = $0

      # Enter animations block
      if (!in_anim && line ~ /^[ \t]*animations[ \t]*\{[ \t]*$/) {
        in_anim = 1
        saw_anim_block = 1
        print line
        next
      }

      if (in_anim) {
        # Replace enabled line inside animations block
        if (line ~ /^[ \t]*enabled[ \t]*=[ \t]*(true|false)[ \t]*$/) {
          match(line, /^[ \t]*/)
          indent = substr(line, RSTART, RLENGTH)
          print indent "enabled = " target
          changed = 1
          saw_enabled_in_block = 1
          next
        }

        # Before closing brace, inject enabled if missing
        if (line ~ /^[ \t]*\}[ \t]*$/) {
          if (!saw_enabled_in_block) {
            print "    enabled = " target
            changed = 1
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
        changed = 1
      }
    }
  ' "$conf" > "$tmp"

  mv -f -- "$tmp" "$conf"
}

state="$(read_state_json || true)"
if [[ -z "${state:-}" ]]; then
  state="$(read_state_fallback || true)"
fi
if [[ -z "${state:-}" ]]; then
  state="1"
fi

if [[ "$state" == "1" ]]; then
  target="0"
  msg="OFF"
  hyprlock_enabled="false"
else
  target="1"
  msg="ON"
  hyprlock_enabled="true"
fi

"$HYPRCTL" keyword "animations:enabled" "$target"

# Keep hyprlock.conf in sync (best-effort)
update_hyprlock_animations_enabled "$hyprlock_enabled" "$HYPRLOCK_CONF" || true

if [[ -n "$NOTIFY_SEND" ]]; then
  "$NOTIFY_SEND" -a "Hyprland" \
    -r 49110 \
    -t 1000 \
    "Animations: $msg" \
    "animations:enabled = $target"
fi
