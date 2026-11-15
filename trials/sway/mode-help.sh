#!/usr/bin/env bash
# Click feedback only. Sway input modes are compositor-owned, never faked by
# touching the mode label or calling Hyprland's submap dispatcher.
set -euo pipefail
[[ "${XDG_CURRENT_DESKTOP:-}" == sway && -n "${WAYLAND_DISPLAY:-}" ]] || {
    printf 'Sway mode control requires active Sway session\n' >&2
    exit 1
}
[[ $# -eq 1 && "$1" == help ]] || {
    printf 'Usage: mode-help.sh help\n' >&2
    exit 2
}
message="Sway trial input modes require a native configuration review; no parity is claimed yet."
if command -v notify-send >/dev/null 2>&1; then
    notify-send "Sway input modes" "$message"
else
    printf '%s\n' "$message"
fi
