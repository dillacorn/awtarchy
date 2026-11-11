#!/usr/bin/env bash
# Sway has swaymsg IPC but dynamic Awtarchy placement is not yet ported.
# Prevent any Hyprland dispatcher from running in a Sway session.
set -euo pipefail
[[ "${XDG_CURRENT_DESKTOP:-}" == sway ]] || {
    printf 'Sway position backend invoked outside Sway\n' >&2; exit 1;
}
printf 'Sway: requested live floating-window placement is not implemented; using compositor initial window rules\n' >&2
exit 1
