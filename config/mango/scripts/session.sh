#!/usr/bin/env bash
# Mango startup without any Hyprland compositor IPC.
set -euo pipefail
[[ -n "${MANGO_INSTANCE_SIGNATURE:-}" ]] || {
    printf 'Not in MangoWM\n' >&2
    return 1 2>/dev/null || false
}
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/mango/scripts"
home_config="${XDG_CONFIG_HOME:-$HOME/.config}"
export QUICKSHELL_CONFIG_NAME=awtarchy-mango
export XDG_CURRENT_DESKTOP=mango
export XDG_SESSION_DESKTOP=mango
export XDG_SESSION_TYPE=wayland

if command -v dbus-update-activation-environment >/dev/null 2>&1; then
    dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP \
        XDG_SESSION_DESKTOP XDG_SESSION_TYPE MANGO_INSTANCE_SIGNATURE >/dev/null 2>&1 || true
fi

# Restore clipboard history used by Awtarchy's Quickshell clipboard menu.
if command -v wl-paste >/dev/null 2>&1 && command -v cliphist >/dev/null 2>&1; then
    wl-paste --type text --watch cliphist store &
    wl-paste --type image --watch cliphist store &
fi

if command -v awww-daemon >/dev/null 2>&1; then
    awww-daemon >/dev/null 2>&1 &
fi
if command -v awtwall >/dev/null 2>&1 && [[ -s "$home_config/awtwall/backend_state.tsv" ]]; then
    awtwall --restore >/dev/null 2>&1 || true
elif command -v awww >/dev/null 2>&1; then
    awww img "$HOME/Pictures/wallpapers/awtarchy_geology.png" >/dev/null 2>&1 || true
fi

if command -v nwg-look >/dev/null 2>&1; then
    nwg-look -a >/dev/null 2>&1 &
fi
bash "$config_dir/quickshell.sh" start

# Keep Awtarchy's existing WlSessionLock implementation.
swayidle -w timeout 600 'bash ~/.config/hypr/scripts/awtarchy_lock.sh lock' \
    before-sleep 'bash ~/.config/hypr/scripts/awtarchy_lock.sh lock' &
wait
