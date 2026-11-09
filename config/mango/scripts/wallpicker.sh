#!/usr/bin/env bash
# Mango-specific AwtWall TUI launcher. Do not alter Hyprland's wallpicker.
set -euo pipefail

[[ -n "${MANGO_INSTANCE_SIGNATURE:-}" && "${XDG_CURRENT_DESKTOP:-}" == mango ]] || {
    printf 'Mango wallpicker requires a Mango session\n' >&2
    exit 1
}
command -v awtwall >/dev/null 2>&1 || {
    printf 'Missing AwtWall executable\n' >&2
    exit 1
}
# Hyprpaper is compositor-specific even if its executable is installed.
# Select AwtWall's supported swww backend for the Mango session. AwtWall's
# wallpaper directory, selection, transition, and UI remain user-controlled.
if ! { { command -v awww >/dev/null && command -v awww-daemon >/dev/null; } ||
       { command -v swww >/dev/null && command -v swww-daemon >/dev/null; }; }; then
    printf 'Mango wallpicker requires awww/awww-daemon or swww/swww-daemon\n' >&2
    exit 1
fi
exec awtwall --backend swww --resume
