#!/usr/bin/env bash
# Cold-start safe compositor-local Quickshell IPC.
set -euo pipefail
[[ "${XDG_CURRENT_DESKTOP:-}" == jay && -n "${WAYLAND_DISPLAY:-}" ]] || {
    printf 'Jay IPC requires active Jay session\n' >&2; exit 1;
}
[[ $# -eq 2 ]] || { printf 'usage: ipc.sh TARGET METHOD\n' >&2; exit 2; }
target="$1"
method="$2"
case "$target:$method" in
    launcher:toggle|powermenu:begin|clipboard:toggle|notifications:toggle|quicksettings:toggle) ;;
    *) printf 'Unsupported Jay IPC target: %s/%s\n' "$target" "$method" >&2; exit 2 ;;
esac
manager="${XDG_CONFIG_HOME:-$HOME/.config}/jay/awtarchy-trial/quickshell.sh"
[[ -f "$manager" && ! -L "$manager" ]] || { printf 'Jay Quickshell manager missing\n' >&2; exit 1; }

# A zero exit status from qs does not necessarily mean an IPC target exists.
# Match the explicit string returned by our registered control handler.
ping() {
    local response
    response="$(qs -c awtarchy-jay ipc call control ping 2>/dev/null)" || return 1
    [[ "$response" == "ok" ]]
}

if ! ping; then
    bash "$manager" start || {
        printf 'Jay Quickshell IPC: manager could not start the shell\n' >&2
        exit 1
    }
    ping || {
        printf 'Jay Quickshell IPC: control handler unavailable after startup\n' >&2
        exit 1
    }
fi

response="$(qs -c awtarchy-jay ipc call "$target" "$method" 2>&1)" || {
    printf 'Jay Quickshell IPC: %s/%s call failed: %s\n' "$target" "$method" "$response" >&2
    exit 1
}
case "$response" in
    *"Target not found."*|*"Function not found."*|*"Too few arguments."*|*"Too many arguments."*)
        printf 'Jay Quickshell IPC: %s/%s unavailable: %s\n' "$target" "$method" "$response" >&2
        exit 1 ;;
esac
[[ -z "$response" ]] || printf '%s\n' "$response"
