#!/usr/bin/env bash
set -euo pipefail

# login_sound_when_ready.sh
# Wait for: portal unit + waybar + pipewire + wireplumber, then play a login sound once.
#
# Env overrides:
#   PORTAL_UNIT   (default xdg-desktop-portal-gtk.service)
#   WAIT_SECS     (default 90)
#   INTERVAL_SECS (default 0.1)
#   SOUND_FILE    (default ~/.config/hypr/sounds/awtarchy-login.mp3)

PORTAL_UNIT="${PORTAL_UNIT:-xdg-desktop-portal-gtk.service}"
WAIT_SECS="${WAIT_SECS:-90}"
INTERVAL_SECS="${INTERVAL_SECS:-0.1}"
SOUND_FILE="${SOUND_FILE:-$HOME/.config/hypr/sounds/awtarchy-login.mp3}"

have() { command -v "$1" >/dev/null 2>&1; }

is_active() { systemctl --user is-active --quiet "$1" 2>/dev/null; }
is_portal_ready() { is_active "$PORTAL_UNIT"; }
is_waybar_up() { pgrep -x waybar >/dev/null 2>&1; }

# Audio stack (Arch Hyprland typical)
is_pipewire_ready() { is_active pipewire.service; }
is_wireplumber_ready() { is_active wireplumber.service; }

play_sound() {
  have pw-play || return 1
  [[ -f "$SOUND_FILE" ]] || return 1

  pw-play "$SOUND_FILE" >/dev/null 2>&1 && return 0
  sleep 0.2
  pw-play "$SOUND_FILE" >/dev/null 2>&1 && return 0
  return 1
}

end_epoch=$(( $(date +%s) + WAIT_SECS ))

ready_portal=0
ready_waybar=0
ready_pw=0
ready_wp=0

while (( $(date +%s) < end_epoch )); do
  is_portal_ready      && ready_portal=1
  is_waybar_up         && ready_waybar=1
  is_pipewire_ready    && ready_pw=1
  is_wireplumber_ready && ready_wp=1

  if (( ready_portal && ready_waybar && ready_pw && ready_wp )); then
    play_sound || true
    exit 0
  fi

  sleep "$INTERVAL_SECS"
done

exit 0
