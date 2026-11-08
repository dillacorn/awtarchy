#!/usr/bin/env bash
# Reuse Awtarchy's saved Awtwall wallpaper across Wayland compositors.
set -euo pipefail
state="$HOME/.config/awtwall/backend_state.tsv"
image="$HOME/Pictures/wallpapers/awtarchy_geology.png"

if [[ -s "$state" ]] && command -v awtwall >/dev/null 2>&1; then
    awtwall --restore
elif [[ -f "$image" ]]; then
    if command -v awww >/dev/null 2>&1 && command -v awww-daemon >/dev/null 2>&1; then
        awww-daemon >/dev/null 2>&1 &
        sleep 0.2
        awww img "$image"
    elif command -v swww >/dev/null 2>&1 && command -v swww-daemon >/dev/null 2>&1; then
        swww-daemon >/dev/null 2>&1 &
        sleep 0.2
        swww img "$image"
    elif command -v swaybg >/dev/null 2>&1; then
        swaybg -i "$image" -m fill
    else
        printf 'No supported Mango wallpaper backend is installed.\n' >&2
        false
    fi
else
    printf 'No saved wallpaper or Awtarchy seed image found.\n' >&2
    false
fi
