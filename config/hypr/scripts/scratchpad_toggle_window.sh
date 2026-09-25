#!/usr/bin/env bash
# Toggle the active window between its normal workspace and special:magic.
# The prior workspace is retained per window for the current login session.

set -euo pipefail

for cmd in hyprctl jq mktemp; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "$cmd missing" >&2
    exit 1
  }
done

active_json="$(hyprctl -j activewindow)"
address="$(jq -r '.address // empty' <<<"$active_json")"
workspace_id="$(jq -r '.workspace.id // empty' <<<"$active_json")"
workspace_name="$(jq -r '.workspace.name // empty' <<<"$active_json")"
window_pid="$(jq -r '.pid // 0' <<<"$active_json")"

[[ -n "$address" && "$address" != "0x0" ]] || exit 0

runtime_base="${XDG_RUNTIME_DIR:-/tmp/awtarchy-${UID}}"
state_dir="$runtime_base/awtarchy/scratchpad"
mkdir -p -- "$state_dir"
chmod 700 "$state_dir" 2>/dev/null || true

state_key="${address//[^[:alnum:]_.-]/_}"
state_file="$state_dir/${state_key}.state"

focused_workspace_id() {
  hyprctl -j monitors \
    | jq -r '.[] | select(.focused == true) | .activeWorkspace.id' \
    | head -n1
}

if [[ "$workspace_name" == "special:magic" ]]; then
  target_workspace=""
  if [[ -f "$state_file" ]]; then
    saved_pid=""
    saved_workspace=""
    IFS=$'\t' read -r saved_pid saved_workspace <"$state_file" || true
    if [[ "$saved_pid" == "$window_pid" && "$saved_workspace" =~ ^[1-9][0-9]*$ ]]; then
      target_workspace="$saved_workspace"
    fi
  fi

  if [[ -z "$target_workspace" ]]; then
    target_workspace="$(focused_workspace_id || true)"
  fi

  if [[ ! "$target_workspace" =~ ^[1-9][0-9]*$ ]]; then
    command -v notify-send >/dev/null 2>&1 \
      && notify-send "Scratchpad" "Could not determine the window's previous workspace." \
      || true
    exit 1
  fi

  hyprctl dispatch movetoworkspace "$target_workspace" >/dev/null
  rm -f -- "$state_file"
  exit 0
fi

if [[ ! "$workspace_id" =~ ^[1-9][0-9]*$ ]]; then
  command -v notify-send >/dev/null 2>&1 \
    && notify-send "Scratchpad" "The active window is not on a normal workspace." \
    || true
  exit 1
fi

tmp_state="$(mktemp "$state_dir/.${state_key}.XXXXXX")"
trap 'rm -f -- "$tmp_state"' EXIT
printf '%s\t%s\n' "$window_pid" "$workspace_id" >"$tmp_state"
chmod 600 "$tmp_state" 2>/dev/null || true
mv -f -- "$tmp_state" "$state_file"
trap - EXIT

if ! hyprctl dispatch movetoworkspace "special:magic" >/dev/null; then
  rm -f -- "$state_file"
  exit 1
fi
