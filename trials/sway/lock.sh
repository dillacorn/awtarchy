#!/usr/bin/env bash
# Reuse Awtarchy's secure Quickshell WlSessionLock + PAM implementation.
# The visual shell is compositor-neutral. Swaylock remains an emergency
# fallback, never a pretend replacement for session-lock confirmation.
set -euo pipefail

[[ "${XDG_CURRENT_DESKTOP:-}" == sway && -n "${WAYLAND_DISPLAY:-}" && -n "${SWAYSOCK:-}" ]] || {
    printf 'An active Sway session is required for locking\n' >&2
    exit 1
}

config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
manager="$config_home/hypr/scripts/awtarchy_lock.sh"

lock_fallback() {
    command -v swaylock >/dev/null 2>&1 || {
        printf 'No secure Quickshell lock manager or swaylock fallback available\n' >&2
        return 1
    }
    printf 'Quickshell lock manager missing; invoking secure swaylock fallback\n' >&2
    swaylock -f -c 10151c
}

if [[ -L "$manager" || ( -e "$manager" && ! -f "$manager" ) ]]; then
    printf 'Unsafe Awtarchy Quickshell lock manager path\n' >&2
    exit 1
fi

lock_action="${1:-}"
case "$lock_action" in
    lock|lock-prepared)
        [[ $# -eq 1 ]] || { printf 'Unexpected lock arguments\n' >&2; exit 2; }
        if [[ ! -f "$manager" ]]; then
            lock_fallback
        else
            # Do not claim a compositor-secure lock merely because Quickshell
            # started. Wait for WlSessionLock.secure from the actual locker.
            bash "$manager" lock
            bash "$manager" wait-secure 5
        fi
        ;;
    suspend|hibernate)
        [[ $# -eq 1 ]] || { printf 'Unexpected power arguments\n' >&2; exit 2; }
        [[ -f "$manager" ]] || {
            printf 'Refusing power transition without verified Quickshell lock\n' >&2
            exit 1
        }
        # The shared manager waits for secure WlSessionLock before sleeping.
        bash "$manager" "$lock_action"
        ;;
    status)
        [[ $# -eq 1 ]] || { printf 'Unexpected status arguments\n' >&2; exit 2; }
        [[ -f "$manager" ]] || {
            printf 'unverified\n'
            exit 1
        }
        bash "$manager" status
        ;;
    wait-secure)
        [[ $# -le 2 ]] || { printf 'Unexpected wait-secure arguments\n' >&2; exit 2; }
        [[ -f "$manager" ]] || {
            printf 'Secure Quickshell lock manager unavailable\n' >&2
            exit 1
        }
        bash "$manager" wait-secure "${2:-5}"
        ;;
    *)
        printf 'usage: lock.sh lock|lock-prepared|suspend|hibernate|status|wait-secure\n' >&2
        exit 2
        ;;
esac
