#!/usr/bin/env bash
set -euo pipefail

state="${HOME}/.config/awtwall/backend_state.tsv"
img="${HOME}/Pictures/wallpapers/awtarchy_geology.png"

if [[ -s "$state" ]]; then
    exec awtwall --restore
fi

if command -v awww >/dev/null 2>&1; then
    pgrep -x awww-daemon >/dev/null 2>&1 || {
        awww-daemon >/dev/null 2>&1 &
        sleep 0.2
    }
    exec awww img "$img"
fi

if command -v swww >/dev/null 2>&1; then
    pgrep -x swww-daemon >/dev/null 2>&1 || {
        swww-daemon >/dev/null 2>&1 &
        sleep 0.2
    }
    exec swww img "$img"
fi

if command -v hyprpaper >/dev/null 2>&1; then
    pgrep -x hyprpaper >/dev/null 2>&1 || {
        hyprpaper >/dev/null 2>&1 &
        sleep 0.3
    }
    exec hyprctl hyprpaper wallpaper ",$img,cover"
fi

printf 'awtarchy-wallpaper-init: no still-image wallpaper backend found for first-run seed wallpaper\n' >&2
exit 1
