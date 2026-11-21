#!/usr/bin/env bash
# Umbriel-only startup. No modifications to Hyprland, Sway or Mango sessions.
set -euo pipefail
[[ -n "${WAYLAND_DISPLAY:-}" ]] || { printf 'Umbriel session requires Wayland\n' >&2; false; }
command -v umbriel >/dev/null 2>&1 || { printf 'Umbriel binary missing\n' >&2; false; }
umbriel outputs --json >/dev/null 2>&1 || {
    printf 'Cannot reach running Umbriel IPC; refusing shell startup\n' >&2
    false
}
export QT_QPA_PLATFORMTHEME=qt5ct:qt6ct
export QT6CT_PLATFORM_PLUGIN=qt6ct
export GDK_BACKEND=wayland,x11
export MOZ_ENABLE_WAYLAND=1
session_env=(WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE
             QT_QPA_PLATFORMTHEME QT6CT_PLATFORM_PLUGIN GDK_BACKEND MOZ_ENABLE_WAYLAND)
if command -v dbus-update-activation-environment >/dev/null 2>&1; then
    dbus-update-activation-environment --systemd "${session_env[@]}" || true
fi
# start-umbriel has already imported graphical session values to systemd.
trial="${XDG_CONFIG_HOME:-$HOME/.config}/umbriel/awtarchy-trial"
# Publish the verified initial input mode before Quickshell reads bar state.
if [[ -f "$trial/mode-control.py" && ! -L "$trial/mode-control.py" ]]; then
    python3 "$trial/mode-control.py" sync || \
        printf 'Umbriel input mode state unavailable\n' >&2
fi
if [[ ! -L "$trial/quickshell.sh" && -f "$trial/quickshell.sh" ]]; then
    bash "$trial/quickshell.sh" start || {
        printf 'Umbriel Quickshell failed; inspect ~/.cache/awtarchy/quickshell-umbriel.log\n' >&2
    }
fi
if command -v wl-paste >/dev/null && command -v cliphist >/dev/null; then
    wl-paste --type text --watch cliphist store >/dev/null 2>&1 &
    wl-paste --type image --watch cliphist store >/dev/null 2>&1 &
fi
if command -v awww-daemon >/dev/null; then
    awww-daemon >/dev/null 2>&1 &
    awtwall_launcher="$trial/awtwall.sh"
    if [[ -f "$awtwall_launcher" && ! -L "$awtwall_launcher" &&
          -s "$HOME/.config/awtwall/backend_state.tsv" ]]; then
        bash "$awtwall_launcher" --restore >/dev/null 2>&1 &
    fi
fi
