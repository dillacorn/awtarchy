#!/usr/bin/env bash
# Sway-only startup. The Hyprland shell/profile and agent remain untouched.
set -euo pipefail
[[ "${XDG_CURRENT_DESKTOP:-}" == sway && -n "${SWAYSOCK:-}" && -n "${WAYLAND_DISPLAY:-}" ]] || {
    printf 'Not an active Sway Wayland session\n' >&2; exit 1;
}
if command -v dbus-update-activation-environment >/dev/null 2>&1; then
    dbus-update-activation-environment --systemd WAYLAND_DISPLAY SWAYSOCK XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP XDG_SESSION_TYPE || true
fi
systemctl --user import-environment WAYLAND_DISPLAY SWAYSOCK XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP XDG_SESSION_TYPE || true
if command -v lxqt-policykit-agent >/dev/null 2>&1; then
    lxqt-policykit-agent >/dev/null 2>&1 &
fi
trial="${XDG_CONFIG_HOME:-$HOME/.config}/sway/awtarchy-trial"
manager="$trial/quickshell.sh"
if [[ -f "$manager" && ! -L "$manager" ]] && bash "$manager" start; then
    printf 'Sway trial Quickshell control endpoint reports ready\n'
else
    printf 'Sway trial Quickshell failed; enable Sway fallback bar.\n' >&2
    swaymsg bar mode dock >/dev/null 2>&1 || true
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
    fi
fi
