#!/usr/bin/env bash
# ~/.config/hypr/scripts/waybar_restore_resume.sh
#
# hypridle on-resume:
# - Only restores if idle previously stopped it (marker says "running")
# - Retries because monitors can reappear in stages after sleep

set -euo pipefail

CONF="${XDG_CONFIG_HOME:-$HOME/.config}"
SCRIPTS_DIR="${CONF}/hypr/scripts"
WAYBAR_SH="${WAYBAR_SH:-${SCRIPTS_DIR}/waybar.sh}"

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
IDLE_MARKER="${IDLE_MARKER:-${RUNTIME_DIR}/waybar.idle_restore}"

need() { command -v "$1" >/dev/null 2>&1 || { printf 'waybar_restore_resume: missing: %s\n' "$1" >&2; exit 127; }; }
need hyprctl
need jq

[[ -x "$WAYBAR_SH" ]] || { printf 'waybar_restore_resume: missing executable: %s\n' "$WAYBAR_SH" >&2; exit 1; }

manager_running() {
  [[ "$("$WAYBAR_SH" status 2>/dev/null || true)" == "running" ]]
}

wait_for_monitors_stable() {
  local last="-1" stable="0" len

  for ((t=0; t<120; t++)); do
    len="$(hyprctl monitors -j 2>/dev/null | jq 'length' 2>/dev/null || echo 0)"

    if [[ "$len" -ge 1 ]]; then
      if [[ "$len" == "$last" ]]; then
        stable=$((stable + 1))
      else
        stable="0"
      fi
      last="$len"

      if [[ "$stable" -ge 5 ]]; then
        return 0
      fi
    fi

    sleep 0.1
  done

  return 0
}

if [[ "$(cat "$IDLE_MARKER" 2>/dev/null || true)" == "running" ]]; then
  wait_for_monitors_stable

  "$WAYBAR_SH" start || true
  sleep 0.25
  "$WAYBAR_SH" start || true
  sleep 0.25
  "$WAYBAR_SH" start || true

  if manager_running; then
    rm -f "$IDLE_MARKER" 2>/dev/null || true
  fi
fi
