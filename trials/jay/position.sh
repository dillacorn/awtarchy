#!/usr/bin/env bash
# Jay has initial-window position/size rules, but not Hyprland's live move IPC.
# Prevent any Hyprland dispatcher from running in a Jay session.
set -euo pipefail
[[ "${XDG_CURRENT_DESKTOP:-}" == jay ]] || {
    printf 'Jay position backend invoked outside Jay\n' >&2; exit 1;
}
printf 'Jay: requested live floating-window placement is not implemented; using compositor initial window rules\n' >&2
exit 1
