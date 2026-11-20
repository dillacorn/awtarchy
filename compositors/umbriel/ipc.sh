#!/usr/bin/env bash
# Dedicated Umbriel Quickshell IPC, never calls a Hyprland or Sway backend.
set -euo pipefail
[[ -n "${WAYLAND_DISPLAY:-}" ]] || { printf 'Umbriel Wayland session required\n' >&2; false; }
umbriel outputs --json >/dev/null 2>&1 || {
    printf 'Umbriel compositor IPC unavailable\n' >&2; false;
}
[[ $# -eq 2 ]] || { printf 'Usage: ipc.sh TARGET METHOD\n' >&2; false; }
case "$1:$2" in
    launcher:toggle|powermenu:begin|clipboard:toggle|notifications:toggle|notifications:hideFirstPopup|quicksettings:toggle|themes:toggle) ;;
    *) printf 'Unsupported Umbriel Quickshell call: %s/%s\n' "$1" "$2" >&2; false ;;
esac
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
manager="$config_home/umbriel/awtarchy-trial/quickshell.sh"
[[ -f "$manager" && ! -L "$manager" ]] || {
    printf 'Missing Umbriel Quickshell manager\n' >&2; false;
}
ping() {
    local result=""
    result="$(qs -c awtarchy-umbriel ipc call control ping 2>/dev/null)" || return 1
    [[ "$result" == ok ]]
}
if ! ping; then
    bash "$manager" start || { printf 'Quickshell startup failed\n' >&2; false; }
    ping || { printf 'Umbriel control IPC unavailable\n' >&2; false; }
fi
qs -c awtarchy-umbriel ipc call "$1" "$2"
