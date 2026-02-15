#!/usr/bin/env bash
set -euo pipefail

# vibrance_shader.sh
# - Edits ~/.config/hypr/shaders/vibrance (#define VIBRANCE X)
# - Toggles ONLY the screen_shader vibrance line in hyprland.conf by commenting/uncommenting it.
# - When enabling, comments any other active screen_shader lines (pick-one behavior).
#
# Usage:
#   vibrance_shader.sh up
#   vibrance_shader.sh down
#   vibrance_shader.sh toggle
#   vibrance_shader.sh off
#   vibrance_shader.sh set 0.35
#   vibrance_shader.sh key 1..9|0

CONF="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprland.conf"
SHADER="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/shaders/vibrance"

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
  v="$(awk '$1=="#define" && $2=="VIBRANCE" {print $3; exit}' "$SHADER" 2>/dev/null || true)"
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
    perl -i -pe "s/^[ \t]*#define[ \t]+VIBRANCE[ \t]+[0-9.]+[ \t]*\$/#define VIBRANCE $new/" "$SHADER"
  else
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

  awk '
    BEGIN{prev_define=0}
    {
      if (prev_define && $0 ~ /^[ \t]*void[ \t]+main[ \t]*\(/) print ""
      print
      prev_define = ($0 ~ /^[ \t]*#define[ \t]+VIBRANCE[ \t]+[0-9.]+[ \t]*$/) ? 1 : 0
    }
  ' "$SHADER" >"${SHADER}.tmp" && mv -f "${SHADER}.tmp" "$SHADER"
}

conf_vibrance_is_active() {
  awk '
    function strip_cr(s){ sub(/\r$/, "", s); return s }
    function ltrim(s){ sub(/^[ \t]+/, "", s); return s }
    {
      line=strip_cr($0)
      t=ltrim(line)
      if (t ~ /^#/) next
      if (t !~ /^screen_shader[ \t]*=/) next
      sub(/^screen_shader[ \t]*=/, "", t)
      sub(/#.*/, "", t)
      gsub(/[ \t]/, "", t)
      if (t ~ /\/shaders\/vibrance$/) { found=1; exit }
    }
    END{ exit !found }
  ' "$CONF"
}

set_conf_vibrance_state() {
  local enable="$1" # 1 enable, 0 disable
  local tmp default_path
  tmp="$(mktemp)"
  default_path="${HOME}/.config/hypr/shaders/vibrance"

  awk -v enable="$enable" -v default_path="$default_path" '
    function strip_cr(s){ sub(/\r$/, "", s); return s }
    function ltrim(s){ sub(/^[ \t]+/, "", s); return s }
    function indent_of(s){ match(s,/^[ \t]*/); return substr(s,RSTART,RLENGTH) }

    function is_shader_line(line, t){
      t=line; t=strip_cr(t); t=ltrim(t)
      return (t ~ /^#?[ \t]*screen_shader[ \t]*=/) ? 1 : 0
    }

    function shader_is_active(line, t){
      t=line; t=strip_cr(t); t=ltrim(t)
      return (t ~ /^screen_shader[ \t]*=/) ? 1 : 0
    }

    function shader_path_norm(line, t){
      t=line; t=strip_cr(t); t=ltrim(t)
      sub(/^#[ \t]*/, "", t)
      if (t !~ /^screen_shader[ \t]*=/) return ""
      sub(/^screen_shader[ \t]*=/, "", t)
      sub(/#.*/, "", t)
      gsub(/[ \t]/, "", t)
      return t
    }

    function is_vibrance(line, p){
      p=shader_path_norm(line)
      return (p ~ /\/shaders\/vibrance$/) ? 1 : 0
    }

    BEGIN{
      vib_found=0
      first_vib_done=0
      indent_guess=""
    }

    {
      line=strip_cr($0)

      if (indent_guess=="" && line ~ /^[ \t]*#?[ \t]*screen_shader[ \t]*=/) indent_guess=indent_of(line)

      if (is_shader_line(line)) {
        if (is_vibrance(line)) {
          vib_found=1

          ind=indent_of(line)
          rest=substr(line, length(ind)+1)

          if (enable=="1") {
            # first vibrance line becomes ACTIVE, any other vibrance lines become COMMENTED
            if (!first_vib_done) {
              sub(/^#[ \t]*/, "", rest)
              print ind rest
              first_vib_done=1
            } else {
              if (rest !~ /^#/) rest="#" rest
              sub(/^##+/, "#", rest)
              print ind rest
            }
            next
          } else {
            # disable: comment ALL vibrance lines
            if (rest !~ /^#/) rest="#" rest
            sub(/^##+/, "#", rest)
            print ind rest
            next
          }
        } else {
          # other shaders
          if (enable=="1" && shader_is_active(line)) {
            ind=indent_of(line)
            rest=substr(line, length(ind)+1)
            if (rest !~ /^#/) rest="#" rest
            sub(/^##+/, "#", rest)
            print ind rest
            next
          }
        }
      }

      print line
    }

    END{
      if (enable=="1" && vib_found==0) {
        ind = (indent_guess!="") ? indent_guess : "    "
        print ind "screen_shader = " default_path
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

  local cur idx new_idx new want_enable

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
      set_conf_vibrance_state "$want_enable"
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
      set_conf_vibrance_state "$want_enable"
      reload_hypr
      notify_enabled_or_off "$want_enable" "$new"
      ;;
    toggle|off)
      if conf_vibrance_is_active; then
        set_conf_vibrance_state 0
        reload_hypr
        notify "off"
      else
        set_conf_vibrance_state 1
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
      set_conf_vibrance_state "$want_enable"
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
      set_conf_vibrance_state "$want_enable"
      reload_hypr
      notify_enabled_or_off "$want_enable" "$new"
      ;;
    *)
      die "usage: $0 up|down|toggle|off|set <val>|key <1..9|0>"
      ;;
  esac
}

main "$@"
