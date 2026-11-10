#!/usr/bin/env bash
# Exact Jay Default Applications toggle. Fall back to direct Foot when
# Quickshell has not started; never invoke the Hyprland launch handler.
set -euo pipefail
[[ "${XDG_CURRENT_DESKTOP:-}" == jay && -n "${WAYLAND_DISPLAY:-}" ]] || {
    printf 'Default Applications requires Jay session\n' >&2
    exit 1
}
if command -v qs >/dev/null 2>&1 &&
   qs -c awtarchy-jay ipc call control toggleDefaultApps >/dev/null 2>&1; then
    exit 0
fi
command -v foot >/dev/null 2>&1 || { printf 'Foot unavailable\n' >&2; exit 127; }
exec foot --app-id awtarchy-default-apps --title awtarchy-default-apps \
    python3 "${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/default_applications.py" tui
