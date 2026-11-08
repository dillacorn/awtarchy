#!/usr/bin/env bash
set -euo pipefail
[[ -n "${MANGO_INSTANCE_SIGNATURE:-}" ]] || { printf 'Not in MangoWM\n' >&2; exit 1; }
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/mango/scripts"
# Run the Awtarchy shell. Do not start a competing Waybar/Mako notification daemon.
bash "$config_dir/quickshell.sh" start
if command -v awww-daemon >/dev/null 2>&1; then
    awww-daemon >/dev/null 2>&1 &
    if [[ -f "$HOME/.config/awtwall/backend_state.tsv" ]]; then
        awtwall --restore >/dev/null 2>&1 || true
    fi
fi
# Temporarily use native Wayland idle handling until protected-idle policy ports.
swayidle -w timeout 600 'bash ~/.config/hypr/scripts/awtarchy_lock.sh lock'     before-sleep 'bash ~/.config/hypr/scripts/awtarchy_lock.sh lock' &
wait
