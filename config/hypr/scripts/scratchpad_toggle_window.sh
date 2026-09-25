#!/usr/bin/env bash
# Toggle the active window between its normal workspace and special:magic.
# Also owns scratchpad-aware explicit move-to-workspace behavior for number binds.

set -euo pipefail

for cmd in hyprctl jq mktemp; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "$cmd missing" >&2
    exit 1
  }
done

runtime_base="${XDG_RUNTIME_DIR:-/tmp/awtarchy-${UID}}"
state_dir="$runtime_base/awtarchy/scratchpad"
mkdir -p -- "$state_dir"
chmod 700 "$state_dir" 2>/dev/null || true

active_window_json() {
  hyprctl -j activewindow
}

state_file_for_address() {
  local address="$1" state_key
  state_key="${address//[^[:alnum:]_.-]/_}"
  printf '%s/%s.state\n' "$state_dir" "$state_key"
}

scratchpad_is_visible() {
  hyprctl -j monitors \
    | jq -e 'any(.[]; (.specialWorkspace.name // "") == "special:magic")' \
    >/dev/null
}

scratchpad_client_count() {
  hyprctl -j clients \
    | jq '[.[] | select((.workspace.name // "") == "special:magic")] | length'
}

hide_empty_scratchpad() {
  local count
  count="$(scratchpad_client_count)"
  [[ "$count" =~ ^[0-9]+$ ]] || return 0
  if (( count == 0 )) && scratchpad_is_visible; then
    hyprctl dispatch togglespecialworkspace magic >/dev/null
  fi
}

read_saved_state() {
  local state_file="$1"
  SAVED_PID=""
  SAVED_WORKSPACE=""
  SAVED_FLOATING=""
  SAVED_X=""
  SAVED_Y=""
  SAVED_W=""
  SAVED_H=""

  [[ -f "$state_file" ]] || return 1

  local first="" second="" third="" fourth="" fifth="" sixth="" seventh="" eighth=""
  IFS=$'\t' read -r first second third fourth fifth sixth seventh eighth <"$state_file" || true

  if [[ "$first" == "v2" ]]; then
    SAVED_PID="$second"
    SAVED_WORKSPACE="$third"
    SAVED_FLOATING="$fourth"
    SAVED_X="$fifth"
    SAVED_Y="$sixth"
    SAVED_W="$seventh"
    SAVED_H="$eighth"
  else
    SAVED_PID="$first"
    SAVED_WORKSPACE="$second"
  fi

  [[ -n "$SAVED_PID" && -n "$SAVED_WORKSPACE" ]]
}

restore_geometry_if_possible() {
  local address="$1"

  case "$SAVED_FLOATING" in
    true)
      hyprctl dispatch setfloating "address:$address" >/dev/null || true
      if [[ "$SAVED_W" =~ ^[0-9]+$ && "$SAVED_H" =~ ^[0-9]+$ ]]; then
        hyprctl dispatch resizewindowpixel "exact $SAVED_W $SAVED_H,address:$address" >/dev/null || true
      fi
      if [[ "$SAVED_X" =~ ^-?[0-9]+$ && "$SAVED_Y" =~ ^-?[0-9]+$ ]]; then
        hyprctl dispatch movewindowpixel "exact $SAVED_X $SAVED_Y,address:$address" >/dev/null || true
      fi
      ;;
    false)
      hyprctl dispatch settiled "address:$address" >/dev/null || true
      ;;
  esac
}

toggle_active_window() {
  local active_json address workspace_id workspace_name window_pid state_file
  active_json="$(active_window_json)"
  address="$(jq -r '.address // empty' <<<"$active_json")"
  workspace_id="$(jq -r '.workspace.id // empty' <<<"$active_json")"
  workspace_name="$(jq -r '.workspace.name // empty' <<<"$active_json")"
  window_pid="$(jq -r '.pid // 0' <<<"$active_json")"

  [[ -n "$address" && "$address" != "0x0" ]] || exit 0
  state_file="$(state_file_for_address "$address")"

  if [[ "$workspace_name" == "special:magic" ]]; then
    local target_workspace=""
    if read_saved_state "$state_file"; then
      if [[ "$SAVED_PID" == "$window_pid" && "$SAVED_WORKSPACE" =~ ^[1-9][0-9]*$ ]]; then
        target_workspace="$SAVED_WORKSPACE"
      fi
    fi

    if [[ -z "$target_workspace" ]]; then
      target_workspace="$(
        hyprctl -j monitors \
          | jq -r '.[] | select(.focused == true) | .activeWorkspace.id' \
          | head -n1
      )"
    fi

    if [[ ! "$target_workspace" =~ ^[1-9][0-9]*$ ]]; then
      if command -v notify-send >/dev/null 2>&1; then
        notify-send "Scratchpad" "Could not determine the window's previous workspace." || true
      fi
      exit 1
    fi

    hyprctl dispatch movetoworkspacesilent "$target_workspace,address:$address" >/dev/null
    restore_geometry_if_possible "$address"
    rm -f -- "$state_file"

    hyprctl dispatch workspace "$target_workspace" >/dev/null
    hyprctl dispatch focuswindow "address:$address" >/dev/null || true
    exit 0
  fi

  if [[ ! "$workspace_id" =~ ^[1-9][0-9]*$ ]]; then
    if command -v notify-send >/dev/null 2>&1; then
      notify-send "Scratchpad" "The active window is not on a normal workspace." || true
    fi
    exit 1
  fi

  local floating x y width height tmp_state
  floating="$(jq -r '.floating // false' <<<"$active_json")"
  x="$(jq -r '.at[0] // 0' <<<"$active_json")"
  y="$(jq -r '.at[1] // 0' <<<"$active_json")"
  width="$(jq -r '.size[0] // 0' <<<"$active_json")"
  height="$(jq -r '.size[1] // 0' <<<"$active_json")"

  tmp_state="$(mktemp "$state_dir/.state.XXXXXX")"
  trap 'rm -f -- "$tmp_state"' EXIT
  printf 'v2\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$window_pid" "$workspace_id" "$floating" "$x" "$y" "$width" "$height" >"$tmp_state"
  chmod 600 "$tmp_state" 2>/dev/null || true
  mv -f -- "$tmp_state" "$state_file"
  trap - EXIT

  if ! hyprctl dispatch movetoworkspace "special:magic,address:$address" >/dev/null; then
    rm -f -- "$state_file"
    exit 1
  fi
}

move_active_to_workspace() {
  local target_workspace="$1"
  [[ "$target_workspace" =~ ^[1-9][0-9]*$ ]] || {
    echo "Invalid workspace: $target_workspace" >&2
    exit 2
  }

  local active_json address workspace_name state_file
  active_json="$(active_window_json)"
  address="$(jq -r '.address // empty' <<<"$active_json")"
  workspace_name="$(jq -r '.workspace.name // empty' <<<"$active_json")"

  [[ -n "$address" && "$address" != "0x0" ]] || exit 0
  state_file="$(state_file_for_address "$address")"

  hyprctl dispatch movetoworkspacesilent "$target_workspace,address:$address" >/dev/null

  if [[ "$workspace_name" == "special:magic" ]]; then
    rm -f -- "$state_file"
    hide_empty_scratchpad
  fi
}

case "${1:-toggle}" in
  toggle)
    toggle_active_window
    ;;
  move-to)
    [[ $# -eq 2 ]] || {
      echo "Usage: ${0##*/} move-to <workspace>" >&2
      exit 2
    }
    move_active_to_workspace "$2"
    ;;
  *)
    echo "Usage: ${0##*/} [toggle | move-to <workspace>]" >&2
    exit 2
    ;;
esac
