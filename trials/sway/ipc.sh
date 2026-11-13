#!/usr/bin/env bash
# Cold-start safe compositor-local Quickshell IPC.
set -euo pipefail
[[ "${XDG_CURRENT_DESKTOP:-}" == sway && -n "${WAYLAND_DISPLAY:-}" ]] || {
    printf 'Sway IPC requires active Sway session\n' >&2; exit 1;
}
[[ $# -eq 2 ]] || { printf 'usage: ipc.sh TARGET METHOD\n' >&2; exit 2; }
target="$1"
method="$2"
case "$target:$method" in
    launcher:toggle|powermenu:begin|clipboard:toggle|notifications:toggle|notifications:hideFirstPopup|quicksettings:toggle|themes:toggle) ;;
    *) printf 'Unsupported Sway IPC target: %s/%s\n' "$target" "$method" >&2; exit 2 ;;
esac
manager="${XDG_CONFIG_HOME:-$HOME/.config}/sway/awtarchy-trial/quickshell.sh"
[[ -f "$manager" && ! -L "$manager" ]] || { printf 'Sway Quickshell manager missing\n' >&2; exit 1; }

# A zero exit status from qs does not necessarily mean an IPC target exists.
# Match the explicit string returned by our registered control handler.
ping() {
    local response
    response="$(qs -c awtarchy-sway ipc call control ping 2>/dev/null)" || return 1
    [[ "$response" == "ok" ]]
}

if ! ping; then
    bash "$manager" start || {
        printf 'Sway Quickshell IPC: manager could not start the shell\n' >&2
        exit 1
    }
    ping || {
        printf 'Sway Quickshell IPC: control handler unavailable after startup\n' >&2
        exit 1
    }
fi

response="$(qs -c awtarchy-sway ipc call "$target" "$method" 2>&1)" || {
    printf 'Sway Quickshell IPC: %s/%s call failed: %s\n' "$target" "$method" "$response" >&2
    exit 1
}
case "$response" in
    *"Target not found."*|*"Function not found."*|*"Too few arguments."*|*"Too many arguments."*)
        printf 'Sway Quickshell IPC: %s/%s unavailable: %s\n' "$target" "$method" "$response" >&2
        exit 1 ;;
esac
[[ -z "$response" ]] || printf '%s\n' "$response"
