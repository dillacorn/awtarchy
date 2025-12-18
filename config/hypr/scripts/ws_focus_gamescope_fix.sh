#!/usr/bin/env bash
# github.com/dillacorn/awtarchy/tree/main/config/hypr/scripts
# ~/.config/hypr/scripts/ws_focus_gamescope_fix.sh
#
# Goal:
# - If you're focused on gamescope and you press "workspace N":
#     - If workspace N is already ACTIVE on a different monitor:
#         - focus that monitor (do NOT change workspaces on the current monitor)
#         - warp cursor to the center of that monitor to escape gamescope grab
#     - Else:
#         - normal "workspace N" on the current monitor
#
# deps: hyprctl, jq

set -euo pipefail

WS="${1:-}"
[[ -n "${WS}" ]] || exit 2

command -v hyprctl >/dev/null 2>&1 || exit 3
command -v jq >/dev/null 2>&1 || { hyprctl dispatch workspace "${WS}" >/dev/null; exit 0; }

AW="$(hyprctl -j activewindow 2>/dev/null || echo '{}')"
AW_CLASS="$(jq -r '.class // ""' <<<"${AW}" 2>/dev/null || echo '')"
AW_ICLASS="$(jq -r '.initialClass // ""' <<<"${AW}" 2>/dev/null || echo '')"

# Not gamescope: keep stock behavior.
if [[ "${AW_CLASS}" != "gamescope" && "${AW_ICLASS}" != "gamescope" ]]; then
  hyprctl dispatch workspace "${WS}" >/dev/null
  exit 0
fi

MON_JSON="$(hyprctl -j monitors 2>/dev/null)"

FOCUSED_MON="$(jq -r '.[] | select(.focused==true) | .name' <<<"${MON_JSON}" | head -n1)"

# Find which monitor currently has workspace WS as its activeWorkspace.
TARGET_MON_INFO="$(jq -c --arg ws "${WS}" '
  .[]
  | select(.activeWorkspace.name == $ws or ((.activeWorkspace.id|tostring) == $ws))
' <<<"${MON_JSON}" | head -n1)"

# If WS is active on another monitor: focus that monitor and warp cursor there.
if [[ -n "${TARGET_MON_INFO}" && -n "${FOCUSED_MON}" ]]; then
  TARGET_NAME="$(jq -r '.name' <<<"${TARGET_MON_INFO}")"

  if [[ -n "${TARGET_NAME}" && "${TARGET_NAME}" != "${FOCUSED_MON}" ]]; then
    X="$(jq -r '.x' <<<"${TARGET_MON_INFO}")"
    Y="$(jq -r '.y' <<<"${TARGET_MON_INFO}")"
    W="$(jq -r '.width'  <<<"${TARGET_MON_INFO}")"
    H="$(jq -r '.height' <<<"${TARGET_MON_INFO}")"

    # center point
    CX=$(( X + (W / 2) ))
    CY=$(( Y + (H / 2) ))

    hyprctl --batch "dispatch focusmonitor ${TARGET_NAME}; dispatch movecursor ${CX} ${CY}" >/dev/null
    exit 0
  fi
fi

# Otherwise: act like a normal workspace bind on the current monitor.
hyprctl dispatch workspace "${WS}" >/dev/null
