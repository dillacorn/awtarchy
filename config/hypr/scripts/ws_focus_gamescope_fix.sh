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

read_ppid() {
  local pid="$1"
  [[ -r "/proc/${pid}/status" ]] || { echo 0; return 0; }
  awk '/^PPid:/{print $2; exit}' "/proc/${pid}/status" 2>/dev/null || echo 0
}

read_comm() {
  local pid="$1"
  [[ -r "/proc/${pid}/comm" ]] || { echo ""; return 0; }
  tr -d '\n' < "/proc/${pid}/comm" 2>/dev/null || echo ""
}

pid_chain_has_gamescope() {
  local pid="$1" depth=0 comm ppid
  while (( pid > 1 )) && (( depth < 64 )); do
    comm="$(read_comm "${pid}")"
    [[ -n "${comm}" ]] || break
    [[ "${comm}" == gamescope* ]] && return 0
    ppid="$(read_ppid "${pid}")"
    [[ "${ppid}" =~ ^[0-9]+$ ]] || break
    (( ppid == pid )) && break
    pid="${ppid}"
    ((depth++))
  done
  return 1
}

getopt_int() {
  local key="$1" j v p
  j="$(hyprctl -j getoption "${key}" 2>/dev/null || true)"
  if [[ -n "${j}" ]]; then
    v="$(jq -r '(.int // .value // .data.int // .data.value // empty) | tostring' <<<"${j}" 2>/dev/null || true)"
    [[ "${v}" =~ ^-?[0-9]+$ ]] && { echo "${v}"; return 0; }
  fi
  p="$(hyprctl getoption "${key}" 2>/dev/null || true)"
  v="$(awk '
    BEGIN{IGNORECASE=1}
    $1 ~ /^int:$/ {print $2; exit}
    $1 ~ /^int$/  {print $2; exit}
  ' <<<"${p}" 2>/dev/null || true)"
  [[ "${v}" =~ ^-?[0-9]+$ ]] && { echo "${v}"; return 0; }
  return 1
}

getopt_bool() {
  local key="$1" j v p
  j="$(hyprctl -j getoption "${key}" 2>/dev/null || true)"
  if [[ -n "${j}" ]]; then
    v="$(jq -r '(.int // .value // .data.int // .data.value // empty) | tostring' <<<"${j}" 2>/dev/null || true)"
    [[ "${v}" == "1" ]] && { echo "true"; return 0; }
    [[ "${v}" == "0" ]] && { echo "false"; return 0; }
  fi
  p="$(hyprctl getoption "${key}" 2>/dev/null || true)"
  v="$(awk '
    BEGIN{IGNORECASE=1}
    $1 ~ /^int:$/ {print $2; exit}
    $1 ~ /^int$/  {print $2; exit}
  ' <<<"${p}" 2>/dev/null || true)"
  [[ "${v}" == "1" ]] && { echo "true"; return 0; }
  [[ "${v}" == "0" ]] && { echo "false"; return 0; }
  return 1
}

restore_keywords() {
  [[ -n "${ORIG_FOLLOW_MOUSE:-}" ]] && hyprctl keyword input:follow_mouse "${ORIG_FOLLOW_MOUSE}" >/dev/null 2>&1 || true
  [[ -n "${ORIG_MOUSE_REFOCUS:-}" ]] && hyprctl keyword input:mouse_refocus "${ORIG_MOUSE_REFOCUS}" >/dev/null 2>&1 || true
  [[ -n "${ORIG_NO_WARPS:-}" ]] && hyprctl keyword cursor:no_warps "${ORIG_NO_WARPS}" >/dev/null 2>&1 || true
}

AW="$(hyprctl -j activewindow 2>/dev/null || echo '{}')"
AW_CLASS="$(jq -r '.class // ""' <<<"${AW}" 2>/dev/null || echo '')"
AW_ICLASS="$(jq -r '.initialClass // ""' <<<"${AW}" 2>/dev/null || echo '')"
AW_PID="$(jq -r '.pid // 0' <<<"${AW}" 2>/dev/null || echo 0)"

IN_GAMESCOPE=0
if [[ "${AW_CLASS}" == gamescope* || "${AW_ICLASS}" == gamescope* ]]; then
  IN_GAMESCOPE=1
else
  if [[ "${AW_PID}" =~ ^[0-9]+$ ]] && (( AW_PID > 1 )); then
    pid_chain_has_gamescope "${AW_PID}" && IN_GAMESCOPE=1 || true
  fi
fi

# Not gamescope: keep stock behavior.
if (( IN_GAMESCOPE == 0 )); then
  hyprctl dispatch workspace "${WS}" >/dev/null
  exit 0
fi

MON_JSON="$(hyprctl -j monitors 2>/dev/null)"
FOCUSED_MON="$(jq -r '.[] | select(.focused==true) | .name' <<<"${MON_JSON}" | head -n1)"

TARGET_MON_INFO="$(jq -c --arg ws "${WS}" '
  .[]
  | select(.activeWorkspace.name == $ws or ((.activeWorkspace.id|tostring) == $ws))
' <<<"${MON_JSON}" | head -n1)"

if [[ -n "${TARGET_MON_INFO}" && -n "${FOCUSED_MON}" ]]; then
  TARGET_NAME="$(jq -r '.name' <<<"${TARGET_MON_INFO}")"

  if [[ -n "${TARGET_NAME}" && "${TARGET_NAME}" != "${FOCUSED_MON}" ]]; then
    X="$(jq -r '.x' <<<"${TARGET_MON_INFO}")"
    Y="$(jq -r '.y' <<<"${TARGET_MON_INFO}")"
    W="$(jq -r '.width'  <<<"${TARGET_MON_INFO}")"
    H="$(jq -r '.height' <<<"${TARGET_MON_INFO}")"
    CX=$(( X + (W / 2) ))
    CY=$(( Y + (H / 2) ))

    # Key fix:
    # Temporarily disable follow_mouse so focusmonitor "sticks" even if the cursor is still over gamescope.
    # follow_mouse=0 means cursor movement will not change focus. :contentReference[oaicite:0]{index=0}
    # Also temporarily allow warps if cursor:no_warps is set. :contentReference[oaicite:1]{index=1}
    ORIG_FOLLOW_MOUSE=""
    ORIG_MOUSE_REFOCUS=""
    ORIG_NO_WARPS=""

    ORIG_FOLLOW_MOUSE="$(getopt_int input:follow_mouse 2>/dev/null || true)"
    ORIG_MOUSE_REFOCUS="$(getopt_bool input:mouse_refocus 2>/dev/null || true)"
    ORIG_NO_WARPS="$(getopt_bool cursor:no_warps 2>/dev/null || true)"

    trap restore_keywords EXIT

    [[ -n "${ORIG_FOLLOW_MOUSE}" ]] && hyprctl keyword input:follow_mouse 0 >/dev/null 2>&1 || true
    [[ -n "${ORIG_MOUSE_REFOCUS}" ]] && hyprctl keyword input:mouse_refocus false >/dev/null 2>&1 || true
    [[ -n "${ORIG_NO_WARPS}" ]] && hyprctl keyword cursor:no_warps false >/dev/null 2>&1 || true

    hyprctl --batch \
      "dispatch focusmonitor ${TARGET_NAME}; \
       dispatch movecursor ${CX} ${CY}; \
       dispatch focusmonitor ${TARGET_NAME}" >/dev/null

    exit 0
  fi
fi

hyprctl dispatch workspace "${WS}" >/dev/null
