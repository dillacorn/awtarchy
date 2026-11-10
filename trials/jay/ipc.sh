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
if ! qs -c awtarchy-jay ipc call "$target" "$method" >/dev/null 2>&1; then
    bash "$manager" start
    qs -c awtarchy-jay ipc call "$target" "$method"
fi
