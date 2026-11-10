#!/usr/bin/env bash
# Read-only runtime probe from the Jay session.
set -euo pipefail
[[ "${XDG_CURRENT_DESKTOP:-}" == jay && -n "${WAYLAND_DISPLAY:-}" ]] || {
    printf 'FAIL: Not inside Jay\n' >&2
    exit 1
}
printf '=== Compositor ===\n'
jay pid
printf '\n=== Outputs and modes ===\n'
jay randr show --modes
printf '\n=== Workspaces ===\n'
jay tree query || true
printf '\n=== Idle ===\n'
jay idle status || true
printf '\n=== PipeWire/Portal ===\n'
systemctl --user is-active pipewire xdg-desktop-portal || true
if [[ -f /usr/share/xdg-desktop-portal/portals/jay.portal ]]; then
    printf 'Jay portal descriptor found.\n'
else
    printf 'WARN: Missing packaged Jay portal descriptor; screen sharing may fail.\n'
fi
printf '\nRuntime still requires actual screen-share, game tearing, lock/unlock and display reboot testing.\n'
