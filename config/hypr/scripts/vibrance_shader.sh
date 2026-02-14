#!/usr/bin/env bash
set -euo pipefail

# vibrance_shader.sh
# Usage:
#   vibrance_shader.sh up
#   vibrance_shader.sh down
#   vibrance_shader.sh off      # TOGGLE on/off (keeps current value)
#   vibrance_shader.sh toggle   # same as off

CONF="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprland.conf"
SHADER="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/shaders/vibrance"

# First step is +0.15, then +0.10 thereafter.
LEVELS=(0.00 0.15 0.25 0.35 0.45 0.55 0.65 0.75 0.85 0.95)

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
need_file() { [[ -f "$1" ]] || die "missing: $1"; }

notify() {
  local msg="$1"
  if command -v hyprctl >/dev/null 2>&1; then
    hyprctl notify -1 2200 0 "Vibrance: $msg" >/dev/null 2>&1 || true
    return 0
  fi
  command -v notify-send >/dev/null 2>&1 && notify-send -a Hyprland -t 2200 "Vibrance" "$msg" >/dev/null 2>&1 || true
}

read_vibrance() {
  local v
  v="$(awk '$1=="#define" && $2=="VIBRANCE" {print $3; exit}' "$SHADER" 2>/dev/null || true)"
  [[ -n "${v:-}" ]] || v="0.00"
  awk -v x="$v" 'BEGIN{printf "%.2f", x+0.0}'
}

nearest_index() {
  local cur="$1"
  local best_i=0 best_d="999999" d
  for i in "${!LEVELS[@]}"; do
    d="$(awk -v a="$cur" -v b="${LEVELS[$i]}" 'BEGIN{d=a-b; if(d<0)d=-d; printf "%.6f", d}')"
    if awk -v d="$d" -v bd="$best_d" 'BEGIN{exit !(d < bd)}'; then
      best_d="$d"
      best_i="$i"
    fi
  done
  printf '%s' "$best_i"
}

set_shader_define() {
  local new="$1"
  local tmp
  tmp="$(mktemp)"
  awk -v new="$new" '
    BEGIN { found=0; just=0 }
    {
      if ($0 ~ /^[[:space:]]*#define[[:space:]]+VIBRANCE([[:space:]]+|$)/) {
        print "#define VIBRANCE " new
        print ""
        found=1
        just=1
        next
      }
      if (just==1) {
        if ($0 ~ /^[[:space:]]*$/) next
        just=0
      }
      print
    }
    END {
      if (!found) {
        print ""
        print "#define VIBRANCE " new
        print ""
      }
    }
  ' "$SHADER" >"$tmp"
  mv -f "$tmp" "$SHADER"
}

conf_vibrance_enabled() {
  # returns 0 if enabled, 1 otherwise
  awk '
    $0 ~ /^[[:space:]]*screen_shader[[:space:]]*=/ && $0 ~ /\/shaders\/vibrance[[:space:]]*$/ { found=1 }
    END { exit(found ? 0 : 1) }
  ' "$CONF"
}

set_conf_vibrance_line() {
  # mode: on|off
  local mode="$1"
  local tmp
  tmp="$(mktemp)"

  awk -v mode="$mode" '
    function indent_of(line,   m) {
      m = match(line, /^[[:space:]]*/)
      return substr(line, 1, RLENGTH)
    }

    BEGIN {
      ref="~/.config/hypr/shaders/vibrance"
      inserted=0
      pick_indent="    "
    }

    function is_vibrance_line(line) {
      return (line ~ /^[[:space:]]*#?[[:space:]]*screen_shader[[:space:]]*=/ && line ~ /\/shaders\/vibrance[[:space:]]*$/)
    }

    {
      # When we hit "# pick ONE:" insert exactly one vibrance line right after it (keeps indentation)
      if ($0 ~ /^[[:space:]]*#[[:space:]]*pick[[:space:]]+ONE[[:space:]]*:/) {
        pick_indent = indent_of($0)
        print $0
        if (!inserted) {
          if (mode=="on") print pick_indent "screen_shader = " ref
          else            print pick_indent "#screen_shader = " ref
          inserted=1
        }
        next
      }

      # Remove any existing vibrance shader lines anywhere (commented or not)
      if (is_vibrance_line($0)) next

      # If enabling vibrance, force any other active screen_shader lines to commented (only one shader allowed)
      if (mode=="on" && $0 ~ /^[[:space:]]*screen_shader[[:space:]]*=/) {
        ind=indent_of($0)
        line=$0
        sub(/^[[:space:]]*screen_shader/, ind "#screen_shader", line)
        print line
        next
      }

      print $0
    }

    END {
      # No "# pick ONE:" line found. Still keep exactly one vibrance line (best-effort indentation).
      if (!inserted) {
        if (mode=="on") print pick_indent "screen_shader = " ref
        else            print pick_indent "#screen_shader = " ref
      }
    }
  ' "$CONF" >"$tmp"

  mv -f "$tmp" "$CONF"
}

reload_hypr() {
  command -v hyprctl >/dev/null 2>&1 || return 0
  hyprctl reload >/dev/null 2>&1 || true
}

main() {
  local action="${1:-}"
  [[ -n "$action" ]] || die "usage: $0 up|down|off|toggle"

  need_file "$CONF"
  need_file "$SHADER"

  local cur idx new_idx new
  cur="$(read_vibrance)"
  idx="$(nearest_index "$cur")"

  case "$action" in
    up)
      new_idx="$(( idx + 1 ))"
      (( new_idx > ${#LEVELS[@]} - 1 )) && new_idx="$(( ${#LEVELS[@]} - 1 ))"
      new="${LEVELS[$new_idx]}"
      set_shader_define "$new"
      if awk -v x="$new" 'BEGIN{exit !(x>0.0)}'; then
        set_conf_vibrance_line on
      else
        set_conf_vibrance_line off
      fi
      reload_hypr
      notify "$new"
      ;;
    down)
      new_idx="$(( idx - 1 ))"
      (( new_idx < 0 )) && new_idx=0
      new="${LEVELS[$new_idx]}"
      set_shader_define "$new"
      if awk -v x="$new" 'BEGIN{exit (x>0.0)}'; then
        set_conf_vibrance_line off
        reload_hypr
        notify "off"
      else
        set_conf_vibrance_line on
        reload_hypr
        notify "$new"
      fi
      ;;
    off|toggle)
      # Toggle ONLY. Do not touch the VIBRANCE value.
      if conf_vibrance_enabled; then
        set_conf_vibrance_line off
        reload_hypr
        notify "off (kept $cur)"
      else
        # if value is 0.00 and user toggles on, it will be enabled but visually no-op. that is fine.
        set_conf_vibrance_line on
        reload_hypr
        notify "on ($cur)"
      fi
      ;;
    *)
      die "usage: $0 up|down|off|toggle"
      ;;
  esac
}

main "$@"
