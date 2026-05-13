#!/usr/bin/env bash
# github.com/dillacorn/awtarchy/tree/main/config/hypr/scripts
# ~/.config/hypr/scripts/splitratio_steam.sh
#
# Single-run: wait for Steam main + Friends once, ensure Friends is RIGHT,
# set split, exit.
#
# Hyprland 0.55 Lua-compatible hyprctl dispatch version.
# Deps: hyprctl, jq

set -euo pipefail

POLL="0.20"       # seconds between checks while waiting
SPLIT="0.80"      # target ratio for Steam when Steam is LEFT and Friends is RIGHT
MAX_WAIT="300"    # total seconds to wait before giving up
DEBUG="${DEBUG:-0}"

log() {
  [ "$DEBUG" -eq 1 ] && printf '[splitratio_steam] %s\n' "$*" >&2 || true
}

lua_quote() {
  local s="${1:-}"
  s=${s//\\/\\\\}
  s=${s//\'/\\\'}
  printf "'%s'" "$s"
}

lua_ws_expr() {
  local ws="${1:-}"
  if [[ "$ws" =~ ^[1-9][0-9]*$ ]]; then
    printf '%s' "$ws"
  else
    lua_quote "$ws"
  fi
}

hypr_dispatch() {
  hyprctl dispatch "$1"
}

clients_json() {
  hyprctl clients -j 2>/dev/null || printf '[]\n'
}

get_ids() {
  local json steam_id friends_id
  json="$(clients_json)"

  steam_id="$(printf '%s\n' "$json" \
    | jq -r '.[] | select(.class=="steam" and .title=="Steam") | .address' \
    | head -n1 || true)"

  friends_id="$(printf '%s\n' "$json" \
    | jq -r '.[] | select(.class=="steam" and .title=="Friends List") | .address' \
    | head -n1 || true)"

  printf '%s\n%s\n' "${steam_id:-}" "${friends_id:-}"
}

get_field() {
  local addr="$1" jq_expr="$2"
  clients_json | jq -r --arg a "$addr" ".[] | select(.address==\$a) | $jq_expr" 2>/dev/null || true
}

get_x() { get_field "$1" '.at[0]'; }
get_y() { get_field "$1" '.at[1]'; }
get_w() { get_field "$1" '.size[0]'; }
get_h() { get_field "$1" '.size[1]'; }
get_ws_id() { get_field "$1" '.workspace.id'; }
get_floating() { get_field "$1" '.floating'; }
get_fullscreen() { get_field "$1" '.fullscreen'; }

same_ws() {
  local a="$1" b="$2" wa wb
  wa="$(get_ws_id "$a")"
  wb="$(get_ws_id "$b")"
  [[ -n "$wa" && -n "$wb" && "$wa" = "$wb" ]]
}

focus_addr() {
  local addr="$1"
  [ -n "$addr" ] || return 1
  hypr_dispatch "hl.dsp.focus({ window = $(lua_quote "address:$addr") })" >/dev/null 2>&1
}

focus_ws() {
  local ws="$1"
  [ -n "$ws" ] || return 1
  hypr_dispatch "hl.dsp.focus({ workspace = $(lua_ws_expr "$ws") })" >/dev/null 2>&1
}

move_focused_to_ws() {
  local ws="$1"
  [ -n "$ws" ] || return 1
  hypr_dispatch "hl.dsp.window.move({ workspace = $(lua_ws_expr "$ws"), follow = false })" >/dev/null 2>&1
}

move_addr_to_ws() {
  local addr="$1" ws="$2"
  [ -n "$addr" ] && [ -n "$ws" ] || return 1
  focus_addr "$addr" || return 1
  move_focused_to_ws "$ws"
}

set_tiled_addr() {
  local addr="$1"
  [ -n "$addr" ] || return 1

  # Try targeted first. If Hyprland rejects window= for this dispatcher,
  # fall back to focusing the window and applying to activewindow.
  hypr_dispatch "hl.dsp.window.float({ action = 'disable', window = $(lua_quote "address:$addr") })" >/dev/null 2>&1 \
    || { focus_addr "$addr" && hypr_dispatch "hl.dsp.window.float({ action = 'disable' })" >/dev/null 2>&1; } \
    || true
}

layout_msg() {
  hypr_dispatch "hl.dsp.layout($(lua_quote "$1"))" >/dev/null 2>&1 || true
}

swap_window_dir() {
  hypr_dispatch "hl.dsp.window.swap({ direction = $(lua_quote "$1") })" >/dev/null 2>&1 || true
}

ensure_tiled_same_ws() {
  local steam_id="$1" friends_id="$2" target_ws

  target_ws="$(get_ws_id "$steam_id")"
  [[ -n "$target_ws" && "$target_ws" != "null" ]] || return 0

  move_addr_to_ws "$steam_id" "$target_ws" || true
  move_addr_to_ws "$friends_id" "$target_ws" || true

  if ! same_ws "$steam_id" "$friends_id"; then
    move_addr_to_ws "$friends_id" "$target_ws" || true
  fi

  set_tiled_addr "$steam_id"
  set_tiled_addr "$friends_id"
}

ensure_friends_right() {
  local steam_id="$1" friends_id="$2" sx fx attempt

  for ((attempt=0; attempt<6; attempt++)); do
    sx="$(get_x "$steam_id")"
    fx="$(get_x "$friends_id")"
    [[ -z "$sx" || -z "$fx" ]] && sleep 0.05 && continue

    if (( fx > sx )); then
      return 0
    fi

    focus_addr "$steam_id" || true
    layout_msg "swapsplit"
    sleep 0.10

    sx="$(get_x "$steam_id")"
    fx="$(get_x "$friends_id")"
    if [[ -n "$sx" && -n "$fx" ]] && (( fx > sx )); then
      return 0
    fi

    focus_addr "$steam_id" || true
    swap_window_dir "r"
    sleep 0.10

    sx="$(get_x "$steam_id")"
    fx="$(get_x "$friends_id")"
    if [[ -n "$sx" && -n "$fx" ]] && (( fx > sx )); then
      return 0
    fi

    sleep 0.05
  done

  return 0
}

ratio_applied() {
  local steam_id="$1" friends_id="$2" sw fw total ratio
  sw="$(get_w "$steam_id")"
  fw="$(get_w "$friends_id")"

  [[ "$sw" =~ ^[0-9]+$ ]] || return 1
  [[ "$fw" =~ ^[0-9]+$ ]] || return 1

  total=$(( sw + fw ))
  [ "$total" -gt 0 ] || return 1

  ratio="$(awk -v sw="$sw" -v total="$total" 'BEGIN { printf "%.3f", sw / total }')"
  awk -v got="$ratio" -v want="$SPLIT" 'BEGIN {
    d = got - want;
    if (d < 0) d = -d;
    exit(d <= 0.06 ? 0 : 1)
  }'
}

apply_splitratio_exact() {
  local steam_id="$1" friends_id="$2"

  focus_addr "$steam_id" || return 1

  # Hyprland 0.55 Lua: layout-specific messages go through hl.dsp.layout().
  layout_msg "splitratio exact $SPLIT"
  sleep 0.10
  if ratio_applied "$steam_id" "$friends_id"; then
    log "layout splitratio exact worked"
    return 0
  fi

  return 1
}

apply_resizeactive_fallback() {
  local steam_id="$1" friends_id="$2"
  local sw fw sh target_w

  focus_addr "$steam_id" || return 1

  sw="$(get_w "$steam_id")"
  fw="$(get_w "$friends_id")"
  sh="$(get_h "$steam_id")"

  [[ "$sw" =~ ^[0-9]+$ ]] || return 1
  [[ "$fw" =~ ^[0-9]+$ ]] || return 1
  [[ "$sh" =~ ^[0-9]+$ ]] || return 1

  target_w="$(awk -v sw="$sw" -v fw="$fw" -v r="$SPLIT" 'BEGIN {
    printf "%d", (sw + fw) * r
  }')"

  [ "$target_w" -gt 0 ] || return 1

  hypr_dispatch "hl.dsp.window.resize({ x = $target_w, y = $sh, relative = false })" >/dev/null 2>&1 || true
  sleep 0.10

  if ratio_applied "$steam_id" "$friends_id"; then
    log "window resize exact fallback worked"
    return 0
  fi

  return 1
}

preflight_ok() {
  local steam_id="$1" friends_id="$2"
  local sf ff sfs ffs

  sf="$(get_floating "$steam_id")"
  ff="$(get_floating "$friends_id")"
  sfs="$(get_fullscreen "$steam_id")"
  ffs="$(get_fullscreen "$friends_id")"

  if [[ "$sf" == "true" || "$ff" == "true" ]]; then
    log "window is floating; attempting settiled"
  fi

  if [[ "$sfs" != "0" || "$ffs" != "0" ]]; then
    log "window is fullscreen/maximized; resizing may be ignored"
  fi

  return 0
}

apply_once() {
  local steam_id="$1" friends_id="$2"
  [ -n "$steam_id" ] && [ -n "$friends_id" ] || return 1

  ensure_tiled_same_ws "$steam_id" "$friends_id"
  ensure_friends_right "$steam_id" "$friends_id"
  preflight_ok "$steam_id" "$friends_id"

  if apply_splitratio_exact "$steam_id" "$friends_id"; then
    return 0
  fi

  if apply_resizeactive_fallback "$steam_id" "$friends_id"; then
    return 0
  fi

  log "no resize method succeeded"
  return 1
}

main() {
  local start ts elapsed ids steam_id friends_id seen_steam=0

  start="$(date +%s)"

  ids="$(get_ids)"
  steam_id="$(printf '%s\n' "$ids" | sed -n '1p')"
  friends_id="$(printf '%s\n' "$ids" | sed -n '2p')"
  if apply_once "$steam_id" "$friends_id"; then
    exit 0
  fi

  while :; do
    if pgrep -x steam >/dev/null 2>&1; then
      seen_steam=1
    else
      if [ "$seen_steam" -eq 1 ]; then
        exit 0
      fi
    fi

    ids="$(get_ids)"
    steam_id="$(printf '%s\n' "$ids" | sed -n '1p')"
    friends_id="$(printf '%s\n' "$ids" | sed -n '2p')"

    if [ -n "$steam_id" ] && [ -n "$friends_id" ]; then
      sleep 0.12
      if apply_once "$steam_id" "$friends_id"; then
        exit 0
      fi
    fi

    sleep "$POLL"
    ts="$(date +%s)"
    elapsed="$(( ts - start ))"
    if [ "$elapsed" -ge "$MAX_WAIT" ]; then
      exit 0
    fi
  done
}

main
