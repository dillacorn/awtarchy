#!/usr/bin/bash
# Root-owned Ly session wrapper, configured per login user.
set -euo pipefail
[[ -n "${HOME:-}" && "$HOME" == /* ]] || {
    printf 'Missing absolute login HOME for Sway trial\n' >&2; exit 1;
}
configuration="${XDG_CONFIG_HOME:-$HOME/.config}/sway/awtarchy-trial/config"
[[ -f "$configuration" && ! -L "$configuration" ]] || {
    printf 'Missing isolated Awtarchy Sway configuration: %s\n' "$configuration" >&2; exit 1;
}
export XDG_CURRENT_DESKTOP=sway
export XDG_SESSION_DESKTOP=sway
export XDG_SESSION_TYPE=wayland
# Match the supported Hyprland desktop appearance environment. Sway is
# launched by Ly, so these variables must be inherited by the compositor
# before it launches apps; "exec export" inside the Sway config cannot do it.
# Keep the user's existing qt5ct/qt6ct, Kvantum, GTK and icon preferences.
export GDK_BACKEND='wayland,x11,*'
export QT_QPA_PLATFORM='wayland;xcb'
export CLUTTER_BACKEND=wayland
export QT_AUTO_SCREEN_SCALE_FACTOR=1
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
export QT_QPA_PLATFORMTHEME=qt5ct
export QT6CT_PLATFORM_PLUGIN=qt6ct
export MOZ_ENABLE_WAYLAND=1
export GDK_SCALE=1
export QT_SCALE_FACTOR=1
export XCURSOR_SIZE=24
export GTK_THEME=Materia-dark
export XCURSOR_THEME=Bibata-Modern-Ice
export GAMESCOPE_WSI=vk_wayland
exec /usr/bin/sway --config "$configuration"
