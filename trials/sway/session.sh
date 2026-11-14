#!/usr/bin/env bash
# Sway-only startup. The Hyprland shell/profile and agent remain untouched.
set -euo pipefail
[[ "${XDG_CURRENT_DESKTOP:-}" == sway && -n "${SWAYSOCK:-}" && -n "${WAYLAND_DISPLAY:-}" ]] || {
    printf 'Not an active Sway Wayland session\n' >&2; exit 1;
}
# Also cover the live Sway Quickshell launcher and D-Bus activation;
# the privileged Ly wrapper adopts this for every app on the next login.
export QT_QPA_PLATFORMTHEME=qt5ct:qt6ct
# Update D-Bus/systemd-launched desktop apps as well as direct Sway exec
# children. The root-owned Ly session wrapper exports the Qt/GTK theme first.
# Missing variables are ignored by these environment import helpers.
session_environment=(
    WAYLAND_DISPLAY SWAYSOCK XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP
    XDG_SESSION_TYPE QT_QPA_PLATFORM QT_QPA_PLATFORMTHEME
    QT6CT_PLATFORM_PLUGIN QT_AUTO_SCREEN_SCALE_FACTOR
    QT_WAYLAND_DISABLE_WINDOWDECORATION GTK_THEME XCURSOR_THEME
    XCURSOR_SIZE GDK_BACKEND CLUTTER_BACKEND MOZ_ENABLE_WAYLAND
)
if command -v dbus-update-activation-environment >/dev/null 2>&1; then
    dbus-update-activation-environment --systemd "${session_environment[@]}" || true
fi
systemctl --user import-environment "${session_environment[@]}" || true
if command -v lxqt-policykit-agent >/dev/null 2>&1; then
    lxqt-policykit-agent >/dev/null 2>&1 &
fi
trial="${XDG_CONFIG_HOME:-$HOME/.config}/sway/awtarchy-trial"
manager="$trial/quickshell.sh"
# Align folder-opening XDG MIME with the existing Awtarchy file-manager
# preference. Only inode/directory is changed, with a backup; any explicit
# desktop-specific override and all unrelated associations are preserved.
if [[ -f "$trial/mime-parity.py" && ! -L "$trial/mime-parity.py" ]]; then
    python3 "$trial/mime-parity.py" apply ||
        printf 'Sway: unable to align directory MIME default; leaving user associations unchanged.\n' >&2
fi
if [[ -f "$manager" && ! -L "$manager" ]] && bash "$manager" start; then
    printf 'Sway trial Quickshell control endpoint reports ready\n'
else
    # A separate swaybar/mako fallback masks broken Quickshell startup and
    # lets another notification daemon claim org.freedesktop.Notifications.
    # Leave the compositor and terminal usable; the user can fix the shell.
    printf 'Sway trial Quickshell failed; inspect the Sway Quickshell log.\n' >&2
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
