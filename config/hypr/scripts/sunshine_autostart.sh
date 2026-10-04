#!/usr/bin/env bash
# github.com/dillacorn/awtarchy/tree/main/config/hypr/scripts
# ~/.config/hypr/scripts/sunshine_autostart.sh
#
# Controls Sunshine startup on future desktop logins.
# This helper never starts, stops, or restarts Sunshine.

set -euo pipefail

SERVICE="app-dev.lizardbyte.app.Sunshine.service"

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

have() {
  command -v "$1" >/dev/null 2>&1
}

require_service() {
  have systemctl || die "systemctl is required to manage Sunshine autostart."
  systemctl --user cat "$SERVICE" >/dev/null 2>&1 \
    || die "Sunshine user service is unavailable. Install the official Sunshine package first."
}

status_value() {
  local state=""
  require_service
  state="$(systemctl --user is-enabled "$SERVICE" 2>/dev/null || true)"
  case "$state" in
    enabled|enabled-runtime)
      printf '%s\n' enabled
      ;;
    disabled|disabled-runtime|indirect|static|generated|transient|"")
      printf '%s\n' disabled
      ;;
    *)
      printf '%s\n' "$state"
      ;;
  esac
}

action="${1:-status}"
(( $# <= 1 )) || die "Usage: sunshine_autostart.sh [status|enable|disable]"

case "$action" in
  status)
    printf 'Sunshine autostart: %s\n' "$(status_value)"
    ;;
  enable)
    require_service
    systemctl --user daemon-reload
    systemctl --user enable "$SERVICE"
    printf '%s\n' "Sunshine autostart enabled for future desktop logins."
    printf '%s\n' "Sunshine was not started."
    ;;
  disable)
    require_service
    systemctl --user disable "$SERVICE"
    printf '%s\n' "Sunshine autostart disabled for future desktop logins."
    printf '%s\n' "A currently running Sunshine process was not stopped."
    ;;
  *)
    die "Unknown action: ${action}. Use status, enable, or disable."
    ;;
esac
