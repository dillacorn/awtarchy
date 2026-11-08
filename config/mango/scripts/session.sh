#!/usr/bin/env bash
# Independent Mango session. Keep Hyprland services/configs untouched.
set -euo pipefail
[[ -n "${MANGO_INSTANCE_SIGNATURE:-}" && -n "${WAYLAND_DISPLAY:-}" ]] || {
    printf 'Mango session signature or Wayland display missing.\n' >&2
    false
}
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/mango/scripts"
[[ -d "$config_dir" && ! -L "$config_dir" ]] || {
    printf 'Mango scripts directory missing or linked.\n' >&2
    false
}

# Keep the original Awtwall persisted wallpaper backend where available.
bash "$config_dir/wallpaper.sh" >/dev/null 2>&1 &

# A shell failure must not suppress idle-lock safety or terminate the session.
if ! bash "$config_dir/quickshell.sh" start; then
    printf 'Mango Quickshell startup failed; using the compositor session without the shell.\n' >&2
fi

# Temporary secure locker. Awtarchy's custom protected-idle policy remains
# a migration blocker. swaylock -f returns after the compositor has locked.
if ! command -v swayidle >/dev/null 2>&1; then
    printf 'Mango session has no swayidle; automatic lock is unavailable.\n' >&2
    false
fi
swayidle -w \
    timeout 600 "bash '$config_dir/lock.sh' lock" \
    before-sleep "bash '$config_dir/lock.sh' lock" &
wait
