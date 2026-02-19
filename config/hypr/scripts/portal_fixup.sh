#!/usr/bin/env bash
set -euo pipefail

# ~/.config/hypr/scripts/portal_fixup.sh
# Goal:
# - ensure the systemd --user environment has the *current* Hyprland/Wayland vars
# - clear any portal "failed" state
# - restart portal units cleanly (restart, not start)

# ---- env sanity (don't invent WAYLAND_DISPLAY / HYPRLAND_INSTANCE_SIGNATURE here) ----
export XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-Hyprland}"
export XDG_SESSION_DESKTOP="${XDG_SESSION_DESKTOP:-Hyprland}"
export XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-wayland}"

# Push into dbus activation + systemd --user env
if command -v dbus-update-activation-environment >/dev/null 2>&1; then
  dbus-update-activation-environment --systemd \
    WAYLAND_DISPLAY \
    XDG_CURRENT_DESKTOP \
    XDG_SESSION_DESKTOP \
    XDG_SESSION_TYPE \
    HYPRLAND_INSTANCE_SIGNATURE || true
fi

systemctl --user import-environment \
  WAYLAND_DISPLAY \
  XDG_CURRENT_DESKTOP \
  XDG_SESSION_DESKTOP \
  XDG_SESSION_TYPE \
  HYPRLAND_INSTANCE_SIGNATURE || true

# Clear failed/crash-loop flags
systemctl --user reset-failed \
  xdg-desktop-portal.service \
  xdg-desktop-portal-hyprland.service \
  xdg-desktop-portal-gtk.service 2>/dev/null || true

# Restart cleanly (lets systemd decide ordering)
systemctl --user restart xdg-desktop-portal-hyprland.service 2>/dev/null || true
systemctl --user restart xdg-desktop-portal-gtk.service 2>/dev/null || true
systemctl --user restart xdg-desktop-portal.service 2>/dev/null || true

exit 0
