#!/usr/bin/env bash
# Jay-only session startup. Do not spawn the Hyprland-specific Quickshell profile.
set -euo pipefail
[[ "${XDG_CURRENT_DESKTOP:-}" == jay && -n "${WAYLAND_DISPLAY:-}" ]] || {
    printf 'Jay trial: this is not a Jay Wayland session.\n' >&2
    exit 1
}
if command -v dbus-update-activation-environment >/dev/null 2>&1; then
    dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP XDG_SESSION_TYPE XDG_SESSION_ID || true
fi
systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP XDG_SESSION_TYPE XDG_SESSION_ID || true
if command -v mako >/dev/null 2>&1; then mako >/dev/null 2>&1 & fi
if command -v wl-paste >/dev/null 2>&1 && command -v cliphist >/dev/null 2>&1; then
    wl-paste --type text --watch cliphist store >/dev/null 2>&1 &
    wl-paste --type image --watch cliphist store >/dev/null 2>&1 &
fi
if command -v awww-daemon >/dev/null 2>&1 && command -v awww >/dev/null 2>&1; then
    awww-daemon >/dev/null 2>&1 &
    if command -v awtwall >/dev/null 2>&1 && [[ -s "$HOME/.config/awtwall/backend_state.tsv" ]]; then
        awtwall --restore >/dev/null 2>&1 &
    elif [[ -f "$HOME/Pictures/wallpapers/awtarchy_geology.png" ]]; then
        ( sleep 1; awww img "$HOME/Pictures/wallpapers/awtarchy_geology.png" ) >/dev/null 2>&1 &
    fi
fi
# This fallback runs only inside Jay, leaving the Awtarchy Hyprland agent intact.
if command -v lxqt-policykit-agent >/dev/null 2>&1; then
    lxqt-policykit-agent >/dev/null 2>&1 &
fi
