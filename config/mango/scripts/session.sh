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

# Register the isolated, root-owned authentication agent only after Mango
# provides a real Wayland/logind user session. Never globally enable it.
if [[ -n "${XDG_SESSION_ID:-}" && -n "${XDG_RUNTIME_DIR:-}" \
    && -S "${XDG_RUNTIME_DIR}/bus" ]] && command -v systemctl >/dev/null 2>&1; then
    if ! systemctl --user import-environment \
        WAYLAND_DISPLAY MANGO_INSTANCE_SIGNATURE XDG_SESSION_ID \
        XDG_CURRENT_DESKTOP XDG_SESSION_TYPE; then
        printf 'Mango could not import the PolicyKit session environment.\n' >&2
    elif ! systemctl --user restart awtarchy-polkit-agent.service; then
        printf 'Mango terminal PolicyKit agent failed; GUI authentication may be unavailable.\n' >&2
    fi
fi

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
# Preserve Awtarchy's 60/120/180/240/540-second idle cadence and
# four-hour protected-session safety. The original guarded policy evaluates
# games, visible video, Teams, OBS, manual Keep Awake and productive jobs.
swayidle -w \
    timeout 60 "bash '$config_dir/idle.sh' bar-hide" \
        resume "bash '$config_dir/idle.sh' bar-restore" \
    timeout 120 "bash '$config_dir/idle.sh' dim" \
        resume "bash '$config_dir/idle.sh' brightness-restore" \
    timeout 180 "bash '$config_dir/idle.sh' lock" \
    timeout 240 "bash '$config_dir/idle.sh' dpms-off" \
        resume "bash '$config_dir/idle.sh' dpms-on" \
    timeout 540 "bash '$config_dir/idle.sh' suspend" \
        resume "bash '$config_dir/idle.sh' cancel-suspend" \
    timeout 14400 "bash '$config_dir/idle.sh' protected" \
        resume "bash '$config_dir/idle.sh' dpms-on" \
    before-sleep "bash '$config_dir/lock.sh' lock" &
wait
