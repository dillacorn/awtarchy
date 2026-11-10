#!/usr/bin/env bash
# Click feedback only. Jay input modes are compositor-owned, never faked by
# touching the mode label or calling Hyprland's submap dispatcher.
set -euo pipefail
[[ "${XDG_CURRENT_DESKTOP:-}" == jay && -n "${WAYLAND_DISPLAY:-}" ]] || {
    printf 'Jay mode control requires active Jay session\n' >&2
    exit 1
}
[[ $# -eq 1 && "$1" == help ]] || {
    printf 'Usage: mode-help.sh help\n' >&2
    exit 2
}
message="SUPER+ALT+N: noalt; SUPER+ALT+M: mouse; SUPER+ALT+V: VM. Press the active shortcut again to reset."
if command -v notify-send >/dev/null 2>&1; then
    notify-send "Jay input modes" "$message"
else
    printf '%s\n' "$message"
fi
