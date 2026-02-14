#!/usr/bin/env bash
set -euo pipefail

# vibrance_shader.sh
# Adjusts ~/.config/hypr/shaders/vibrance (#define VIBRANCE X)
# and toggles the matching screen_shader line in hyprland.conf
# without duplicating lines or breaking indentation.
#
# Usage:
#   vibrance_shader.sh up
#   vibrance_shader.sh down
#   vibrance_shader.sh toggle        # keep current value, toggle on/off
#   vibrance_shader.sh off           # alias: toggle
#   vibrance_shader.sh set 0.35      # set to an exact value (snaps to nearest LEVEL)
#   vibrance_shader.sh key 1..9|0    # 1=0.00, 2=0.15, ... 9=0.85, 0=0.95

CONF="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprland.conf"
SHADER="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/shaders/vibrance"

# First step is +0.15, then +0.10 thereafter.
LEVELS=(0.00 0.15 0.25 0.35 0.45 0.55 0.65 0.75 0.85 0.95)

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

need_file() { [[ -f "$1" ]] || die "missing: $1"; }

notify() {
  local msg="$1"
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send -a Hyprland -t 2200 "Vibrance" "$msg" >/dev/null 2>&1 || true
}

fmt2() { awk -v x="$1" 'BEGIN{printf "%.2f", x+0.0}'; }

read_vibrance() {
  local v
  v="$(awk '
    $1=="#define" && $2=="VIBRANCE" {print $3; exit}
  ' "$SHADER" 2>/dev/null || true)"
  [[ -n "${v:-}" ]] || v="0.00"
  fmt2 "$v"
}

nearest_index() {
  local cur="$1"
  local best_i=0
  local best_d="999999"
  local d
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

  if grep -Eq '^[[:space:]]*#define[[:space:]]+VIBRANCE[[:space:]]+' "$SHADER"; then
    # Use [ \t] not [[:space:]] so we never eat newlines/blank lines.
    perl -i -pe "s/^[ \t]*#define[ \t]+VIBRANCE[ \t]+[0-9.]+[ \t]*\$/#define VIBRANCE $new/" "$SHADER"
  else
    # Insert define before main() if missing.
    awk -v new="$new" '
      BEGIN{ins=0}
      {
        if (!ins && $0 ~ /^[ \t]*void[ \t]+main[ \t]*\(/) {
          print "#define VIBRANCE " new
          print ""
          ins=1
        }
        print
      }
      END{
        if(!ins){
          print ""
          print "#define VIBRANCE " new
        }
      }
    ' "$SHADER" >"${SHADER}.tmp" && mv -f "${SHADER}.tmp" "$SHADER"
  fi

  # Ensure a blank line exists between #define and void main().
  awk '
    BEGIN{prev_define=0}
    {
      if (prev_define && $0 ~ /^[ \t]*void[ \t]+main[ \t]*\(/) {
        print ""
      }
      print
      prev_define = ($0 ~ /^[ \t]*#define[ \t]+VIBRANCE[ \t]+[0-9.]+[ \t]*$/) ? 1 : 0
    }
  ' "$SHADER" >"${SHADER}.tmp" && mv -f "${SHADER}.tmp" "$SHADER"
}

conf_has_enabled_vibrance() {
  grep -Eq '^[[:space:]]*screen_shader[[:space:]]*=[[:space:]]*.*\/shaders\/vibrance[[:space:]]*$' "$CONF"
}

pick_indent() {
  awk '
    function ind(s){ match(s,/^[ \t]*/); return substr(s, RSTART, RLENGTH) }
    $0 ~ /^[ \t]*#.*pick[ \t]+ONE:/ {print ind($0); exit}
  ' "$CONF"
}

header_indent() {
  awk '
    function ind(s){ match(s,/^[ \t]*/); return substr(s, RSTART, RLENGTH) }
    $0 ~ /^[ \t]*#.*Screen[ \t]+shaders/ {print ind($0); exit}
  ' "$CONF"
}

vibrance_line_indent() {
  awk '
    function ind(s){ match(s,/^[ \t]*/); return substr(s, RSTART, RLENGTH) }
    $0 ~ /^[ \t]*#?[ \t]*screen_shader[ \t]*=/ && $0 ~ /\/shaders\/vibrance[ \t]*$/ {print ind($0); exit}
  ' "$CONF"
}

best_indent() {
  local iv ip ih best
  iv="$(vibrance_line_indent || true)"
  ip="$(pick_indent || true)"
  ih="$(header_indent || true)"

  best="$iv"
  [[ "${#ip}" -gt "${#best}" ]] && best="$ip"
  [[ "${#ih}" -gt "${#best}" ]] && best="$ih"
  [[ -n "$best" ]] || best="    "
  printf '%s' "$best"
}

first_vibrance_lineno() {
  awk '
    $0 ~ /^[ \t]*#?[ \t]*screen_shader[ \t]*=/ && $0 ~ /\/shaders\/vibrance[ \t]*$/ {print NR; exit}
  ' "$CONF"
}

pick_one_lineno() {
  awk '
    $0 ~ /^[ \t]*#.*pick[ \t]+ONE:/ {print NR; exit}
  ' "$CONF"
}

update_conf_vibrance_line() {
  local enable="$1"   # 1 enable, 0 disable
  local indent conf_path desired first pick tmp

  indent="$(best_indent)"

  # Use literal path in config to avoid "~" ambiguity + shellcheck SC2088.
  conf_path="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/shaders/vibrance"

  if [[ "$enable" == "1" ]]; then
    desired="${indent}screen_shader = ${conf_path}"
  else
    desired="${indent}#screen_shader = ${conf_path}"
  fi

  first="$(first_vibrance_lineno || true)"
  pick="$(pick_one_lineno || true)"

  tmp="$(mktemp)"
  awk -v first="$first" -v pick="$pick" -v desired="$desired" '
    function is_vibrance_line(s) {
      return (s ~ /^[ \t]*#?[ \t]*screen_shader[ \t]*=/ && s ~ /\/shaders\/vibrance[ \t]*$/)
    }
    BEGIN{done=0}
    {
      if (is_vibrance_line($0)) {
        if (first != "" && NR == first) {
          print desired
          done=1
        }
        next
      }
      print
      if (first == "" && pick != "" && NR == pick) {
        print desired
        done=1
      }
    }
    END{
      if(done==0){
        print ""
        print desired
      }
    }
  ' "$CONF" >"$tmp"
  mv -f "$tmp" "$CONF"
}

reload_hypr() {
  command -v hyprctl >/dev/null 2>&1 || return 0
  hyprctl reload >/dev/null 2>&1 || true
}

snap_level_value() {
  local raw="$1"
  local idx
  idx="$(nearest_index "$(fmt2 "$raw")")"
  printf '%s' "${LEVELS[$idx]}"
}

notify_enabled_or_off() {
  local want_enable="$1"
  local val="$2"
  if [[ "$want_enable" == "1" ]]; then
    notify "$val"
  else
    notify "off"
  fi
}

main() {
  local action="${1:-}"
  [[ -n "$action" ]] || die "usage: $0 up|down|toggle|off|set <val>|key <1..9|0>"

  need_file "$CONF"
  need_file "$SHADER"

  local cur idx new_idx new enabled_now want_enable

  enabled_now=0
  conf_has_enabled_vibrance && enabled_now=1

  cur="$(read_vibrance)"
  idx="$(nearest_index "$cur")"

  case "$action" in
    up)
      new_idx="$(( idx + 1 ))"
      (( new_idx > ${#LEVELS[@]} - 1 )) && new_idx="$(( ${#LEVELS[@]} - 1 ))"
      new="${LEVELS[$new_idx]}"
      set_shader_define "$new"
      want_enable=1
      [[ "$new" == "0.00" ]] && want_enable=0
      update_conf_vibrance_line "$want_enable"
      reload_hypr
      notify_enabled_or_off "$want_enable" "$new"
      ;;
    down)
      new_idx="$(( idx - 1 ))"
      (( new_idx < 0 )) && new_idx=0
      new="${LEVELS[$new_idx]}"
      set_shader_define "$new"
      want_enable=1
      [[ "$new" == "0.00" ]] && want_enable=0
      update_conf_vibrance_line "$want_enable"
      reload_hypr
      notify_enabled_or_off "$want_enable" "$new"
      ;;
    toggle|off)
      if [[ "$enabled_now" == "1" ]]; then
        update_conf_vibrance_line 0
        reload_hypr
        notify "off"
      else
        update_conf_vibrance_line 1
        reload_hypr
        notify "$(read_vibrance)"
      fi
      ;;
    set)
      [[ -n "${2:-}" ]] || die "usage: $0 set 0.35"
      new="$(snap_level_value "$2")"
      set_shader_define "$new"
      want_enable=1
      [[ "$new" == "0.00" ]] && want_enable=0
      update_conf_vibrance_line "$want_enable"
      reload_hypr
      notify_enabled_or_off "$want_enable" "$new"
      ;;
    key)
      [[ -n "${2:-}" ]] || die "usage: $0 key 1..9|0"
      case "$2" in
        1) new="0.00" ;;
        2) new="0.15" ;;
        3) new="0.25" ;;
        4) new="0.35" ;;
        5) new="0.45" ;;
        6) new="0.55" ;;
        7) new="0.65" ;;
        8) new="0.75" ;;
        9) new="0.85" ;;
        0) new="0.95" ;;
        *) die "key must be 1..9 or 0" ;;
      esac
      set_shader_define "$new"
      want_enable=1
      [[ "$new" == "0.00" ]] && want_enable=0
      update_conf_vibrance_line "$want_enable"
      reload_hypr
      notify_enabled_or_off "$want_enable" "$new"
      ;;
    *)
      die "usage: $0 up|down|toggle|off|set <val>|key <1..9|0>"
      ;;
  esac
}

main "$@"
