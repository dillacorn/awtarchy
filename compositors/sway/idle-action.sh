#!/usr/bin/env bash
# Sway-only idle transitions. Secure Quickshell WlSessionLock, never swaylock.
set -euo pipefail

[[ "${XDG_CURRENT_DESKTOP:-}" == sway && -n "${SWAYSOCK:-}" &&
   -n "${WAYLAND_DISPLAY:-}" ]] || {
    printf 'An active Sway session is required\n' >&2
    exit 1
}
config="${XDG_CONFIG_HOME:-$HOME/.config}"
trial="$config/sway/awtarchy-trial"
lock="${AWTARCHY_SWAY_LOCK_SCRIPT:-$trial/lock.sh}"
inhibitor="${AWTARCHY_SWAY_INHIBITOR_SCRIPT:-$config/hypr/scripts/idle_inhibitor_global.sh}"
obs="${AWTARCHY_SWAY_OBS_SCRIPT:-$config/hypr/scripts/hypridle_action.sh}"
swaymsg="${AWTARCHY_SWAY_SWAYMSG:-swaymsg}"
systemctl="${AWTARCHY_SWAY_SYSTEMCTL:-systemctl}"

guard_reason() {
    # Keep Awake and Always Awake from the existing Awtarchy bar apply in Sway.
    if [[ -f "$inhibitor" ]] &&
       bash "$inhibitor" is-active >/dev/null 2>&1; then
        printf 'manual idle inhibitor\n'
        return 0
    fi
    # Shared OBS detector checks real recording/streaming/replay activity,
    # not merely whether OBS is open. It does not require Hyprland IPC.
    if [[ -f "$obs" ]] && bash "$obs" obs-active >/dev/null 2>&1; then
        printf 'active OBS output\n'
        return 0
    fi
    # Teams for Linux can legitimately hold a systemd inhibitor during a call.
    if command -v systemd-inhibit >/dev/null 2>&1 &&
       systemd-inhibit --list --no-pager 2>/dev/null |
           grep -Eqi '(teams[-_ ]?for[-_ ]?linux|Microsoft Teams)'; then
        printf 'Teams inhibitor\n'
        return 0
    fi
    return 1
}

output_power() {
    local target="$1" answer
    answer="$("$swaymsg" -r -t command "output * power $target")" || return 1
    jq -e 'type == "array" and length > 0 and all(.[]; .success == true)' \
        >/dev/null <<<"$answer"
}

case "${1:-}" in
    lock)
        if reason="$(guard_reason)"; then
            printf 'Idle lock deferred: %s\n' "$reason"
            exit 0
        fi
        bash "$lock" lock
        ;;
    dpms-off)
        if reason="$(guard_reason)"; then
            printf 'Display power-off deferred: %s\n' "$reason"
            exit 0
        fi
        # Never turn displays off without verifying the secure Quickshell lock.
        bash "$lock" lock && output_power off
        ;;
    dpms-on|resume)
        output_power on
        ;;
    suspend)
        if reason="$(guard_reason)"; then
            printf 'Idle suspend deferred: %s\n' "$reason"
            exit 0
        fi
        bash "$lock" lock || {
            printf 'Refusing to suspend without verified Quickshell session lock\n' >&2
            exit 1
        }
        # Do not use -i or --force: respect logind sleep inhibitors.
        # Nonblocking avoids stalling swayidle -w before-sleep event handling.
        "$systemctl" --no-block suspend
        ;;
    pre-sleep)
        # Lock even for an external/manual system sleep request.
        bash "$lock" lock
        ;;
    check)
        if reason="$(guard_reason)"; then
            printf 'protected: %s\n' "$reason"
        else
            printf 'eligible (subject to native Sway idle inhibitors)\n'
        fi
        ;;
    *)
        printf 'Usage: idle-action.sh lock|dpms-off|dpms-on|resume|suspend|pre-sleep|check\n' >&2
        exit 2
        ;;
esac
