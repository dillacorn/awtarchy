#!/usr/bin/env bash
# Sway-only one-shot login sound. Use Awtarchy's exact iconic login MP3.
# Invoked only from the Sway startup script after Quickshell reports ready.
set -euo pipefail

[[ "${XDG_CURRENT_DESKTOP:-}" == sway && -n "${SWAYSOCK:-}" &&
   -n "${WAYLAND_DISPLAY:-}" ]] || exit 0

trial="${XDG_CONFIG_HOME:-$HOME/.config}/sway/awtarchy-trial"
sound="$trial/awtarchy-login.mp3"
settings="$trial/screenshot_sound.sh"
[[ -f "$sound" && ! -L "$sound" ]] || exit 0
[[ -f "$settings" && ! -L "$settings" ]] || exit 0
command -v pw-play >/dev/null 2>&1 || exit 0

runtime="${XDG_RUNTIME_DIR:-}"
[[ -n "$runtime" && -d "$runtime" && ! -L "$runtime" ]] || exit 0
lock="$runtime/awtarchy-sway-login-sound.lock"
[[ ! -L "$lock" && ( ! -e "$lock" || ( -f "$lock" && -O "$lock" ) ) ]] || exit 0
command -v flock >/dev/null 2>&1 || exit 0
exec 9>"$lock"
flock -n 9 || exit 0

# Consult the same saved sound preference as Hyprland.
allowed() { bash "$settings" is-enabled login >/dev/null 2>&1; }
allowed || exit 0

audio_ready() {
    command -v wpctl >/dev/null 2>&1 || return 0
    local sink
    sink="$(wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null)" || return 1
    [[ "$sink" == *'node.name = "'* && "$sink" != *'node.name = "auto_null"'* ]]
}

usb_refresh_active() {
    local file="/run/awtarchy/usb-refresh/$(id -u).active"
    [[ -r "$file" ]] || return 1
    local pid
    pid="$(tr -dc '0-9' <"$file" 2>/dev/null || true)"
    [[ "$pid" =~ ^[0-9]+$ && -d "/proc/$pid" ]]
}

# A late USB/default audio sink should not lose the login sound.
max_wait="${LOGIN_SOUND_WAIT_SECS:-20}"
[[ "$max_wait" =~ ^[0-9]+$ && "$max_wait" -le 60 ]] || max_wait=20
deadline=$(( $(date +%s) + max_wait ))
while (( $(date +%s) <= deadline )); do
    allowed || exit 0
    if ! usb_refresh_active && audio_ready &&
       pw-play "$sound" >/dev/null 2>&1; then
        exit 0
    fi
    sleep 0.15
done
# Audio availability must never block Sway session startup.
