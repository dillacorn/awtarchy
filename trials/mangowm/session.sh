#!/usr/bin/env bash
# Minimal independent shell. Hyprland-specific Quickshell must not be started.
set -euo pipefail
[[ -n "${MANGO_INSTANCE_SIGNATURE:-}" ]] || { printf 'Not in MangoWM\n' >&2; exit 1; }
dir="${XDG_CONFIG_HOME:-$HOME/.config}/mango/awtarchy-trial"
swaybg -c '#10151c' &
mako &
waybar -c "$dir/waybar.json" -s "$dir/waybar.css" &
swayidle -w timeout 600 'swaylock -f -c 10151c' \
    before-sleep 'swaylock -f -c 10151c' &
wait
