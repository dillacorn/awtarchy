#!/usr/bin/env bash
set -euo pipefail

# ~/.config/hypr/scripts/waybar_ready_sound.sh
# Wait until Waybar is visible (layer-shell surface exists), then play a sound once.
# Retries pw-play long enough to survive pipewire/wireplumber startup races.
#
# Tunables:
#   WAIT_SECS        (default 30)     time to wait for Waybar visibility
#   INTERVAL_SECS    (default 0.02)   polling interval
#   AUDIO_WAIT_SECS  (default 60)     time to keep retrying sound AFTER Waybar is visible
#   AUDIO_INTERVAL   (default 0.20)   retry interval for pw-play
#   SOUND_FILE       (default ~/.config/hypr/sounds/awtarchy-login.mp3)

WAIT_SECS="${WAIT_SECS:-30}"
INTERVAL_SECS="${INTERVAL_SECS:-0.02}"
AUDIO_WAIT_SECS="${AUDIO_WAIT_SECS:-60}"
AUDIO_INTERVAL="${AUDIO_INTERVAL:-0.20}"
SOUND_FILE="${SOUND_FILE:-$HOME/.config/hypr/sounds/awtarchy-login.mp3}"

have() { command -v "$1" >/dev/null 2>&1; }
is_active() { systemctl --user is-active --quiet "$1" 2>/dev/null; }
is_waybar_up() { pgrep -x waybar >/dev/null 2>&1; }

is_waybar_visible() {
  is_waybar_up || return 1
  have hyprctl || return 0

  if have jq; then
    hyprctl layers -j 2>/dev/null \
      | jq -e '.. | objects | (.namespace? // empty) | select(type=="string") | select(test("^waybar"; "i"))' \
      >/dev/null 2>&1
    return $?
  fi

  hyprctl layers 2>/dev/null | grep -Eqi 'namespace: *waybar|waybar'
}

try_play() {
  have pw-play || return 1
  [[ -f "$SOUND_FILE" ]] || return 1
  pw-play "$SOUND_FILE" >/dev/null 2>&1
}

wait_waybar_end=$(( $(date +%s) + WAIT_SECS ))
while (( $(date +%s) < wait_waybar_end )); do
  if is_waybar_visible; then
    # After waybar is visible, keep trying until audio is actually ready.
    audio_end=$(( $(date +%s) + AUDIO_WAIT_SECS ))
    while (( $(date +%s) < audio_end )); do
      # Prefer real readiness signals when available, but still rely on pw-play success.
      # (Some setups don't run wireplumber as a user unit.)
      if is_active pipewire.service 2>/dev/null && is_active wireplumber.service 2>/dev/null; then
        try_play && exit 0
      else
        try_play && exit 0
      fi
      sleep "$AUDIO_INTERVAL"
    done
    exit 0
  fi
  sleep "$INTERVAL_SECS"
done

exit 0
