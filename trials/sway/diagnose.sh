#!/usr/bin/env bash
# Read-only first-session Sway diagnostic summary.
set -euo pipefail
[[ "${XDG_CURRENT_DESKTOP:-}" == sway && -n "${SWAYSOCK:-}" ]] || {
    printf 'Run Sway diagnosis from a Sway session\n' >&2; exit 1;
}
printf 'Sway runtime:\n'
swaymsg -r -t get_version
printf '\nSway configured outputs:\n'
swaymsg -r -t get_outputs
printf '\nSway workspaces:\n'
swaymsg -r -t get_workspaces
printf '\nQuickshell IPC control ping:\n'
qs -c awtarchy-sway ipc call control ping
printf '\nWindow manager: ALT+mouse, ALT+TAB, ALT+SHIFT+B, SUPER+P still require manual validation.\n'
