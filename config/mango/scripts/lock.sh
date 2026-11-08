#!/usr/bin/env bash
# Preserve the native Awtarchy Quickshell locker on Mango's ext-session-lock-v1.
# If unavailable, use the verified Swaylock fallback. Never sleep unlocked.
set -euo pipefail

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
NATIVE_MANAGER="${CONFIG_HOME}/hypr/scripts/awtarchy_lock.sh"
NATIVE_PROFILE="${CONFIG_HOME}/quickshell/awtarchy-lock/shell.qml"

native_available() {
    [[ -f "$NATIVE_MANAGER" && ! -L "$NATIVE_MANAGER" \
        && -f "$NATIVE_PROFILE" && ! -L "$NATIVE_PROFILE" ]] \
        && command -v qs >/dev/null 2>&1
}

native_status() {
    bash "$NATIVE_MANAGER" status 2>/dev/null || true
}

native_lock() {
    # Skipping a Hyprland-only screenshot does not change the native lock UI.
    # The manager still polls the compositor-confirmed secure state.
    AWTARCHY_LOCK_NO_CAPTURE=1 bash "$NATIVE_MANAGER" lock \
        && bash "$NATIVE_MANAGER" wait-secure 5
}

swaylock_fallback() {
    command -v swaylock >/dev/null 2>&1 || {
        printf 'Mango lock: neither verified native lock nor Swaylock is available.\n' >&2
        return 127
    }
    swaylock -f -c 10151c
}

lock_screen() {
    if native_available; then
        if native_lock; then
            return 0
        fi
        # A starting native lock may have acquired the session-lock protocol.
        # Never start another locker or permit suspend in this ambiguous state.
        case "$(native_status)" in
            starting|secure)
                printf 'Mango native lock did not confirm readiness; refusing to substitute another locker.\n' >&2
                return 1
                ;;
        esac
        printf 'Mango native lock unavailable; attempting Swaylock fallback.\n' >&2
    fi
    swaylock_fallback
}

case "${1:-}" in
    lock|lock-prepared)
        [[ $# -eq 1 ]] || { printf 'lock accepts no extra arguments\n' >&2; false; }
        lock_screen
        ;;
    status)
        [[ $# -eq 1 ]] || false
        if native_available && [[ "$(native_status)" == secure ]]; then
            printf 'secure\n'
        elif pgrep -u "$(id -u)" -x swaylock >/dev/null 2>&1; then
            printf 'running\n'
        else
            printf 'unlocked\n'
        fi
        ;;
    hibernate|suspend)
        [[ $# -eq 1 ]] || false
        action="$1"
        lock_screen || {
            printf 'Mango lock was not confirmed; refusing %s.\n' "$action" >&2
            false
        }
        if [[ "$action" == hibernate ]]; then
            systemctl hibernate || loginctl hibernate
        else
            systemctl suspend -i
        fi
        ;;
    *)
        printf 'usage: lock.sh {lock|lock-prepared|status|suspend|hibernate}\n' >&2
        false
        ;;
esac
