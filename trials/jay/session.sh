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

# Use a proven Wayland-compatible PolicyKit agent until the trusted
# Awtarchy terminal authentication agent has a verified Jay window backend.
# Do not start the Hyprland user service here.
if command -v lxqt-policykit-agent >/dev/null 2>&1; then
    lxqt-policykit-agent >/dev/null 2>&1 &
else
    printf 'Jay trial: lxqt-policykit-agent missing; GUI authentication unavailable.\n' >&2
fi
# Start the Jay copy of Awtarchy's existing Quickshell UI. If the
# compositor-specific bridge fails, the native Jay bar remains available
# with ALT+SHIFT+B, and a Mako fallback can still display notifications.
mode_state="${XDG_CONFIG_HOME:-$HOME/.config}/jay/awtarchy-trial/mode-state.sh"
if [[ -f "$mode_state" && ! -L "$mode_state" ]]; then
    bash "$mode_state" default
fi
manager="${XDG_CONFIG_HOME:-$HOME/.config}/jay/awtarchy-trial/quickshell.sh"
if [[ -f "$manager" && ! -L "$manager" ]] && bash "$manager" start; then
    printf 'Jay trial: Quickshell IPC started; runtime parity is unverified.\n'
else
    printf 'Jay trial: Quickshell failed to start; use ALT+SHIFT+B for Jay bar.\n' >&2
    if command -v mako >/dev/null 2>&1; then mako >/dev/null 2>&1 & fi
fi
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
