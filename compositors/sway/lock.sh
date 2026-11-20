#!/usr/bin/env bash
# Reuse Awtarchy's secure Quickshell WlSessionLock + PAM implementation.
# No swaylock fallback is permitted. Locking and sleep must fail closed
# if the real Quickshell WlSessionLock cannot be verified.
set -euo pipefail

[[ "${XDG_CURRENT_DESKTOP:-}" == sway && -n "${WAYLAND_DISPLAY:-}" && -n "${SWAYSOCK:-}" ]] || {
    printf 'An active Sway session is required for locking\n' >&2
    exit 1
}

config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
manager="$config_home/sway/awtarchy-trial/lock-manager.sh"

if [[ -L "$manager" || ( -e "$manager" && ! -f "$manager" ) ]]; then
    printf 'Unsafe Awtarchy Quickshell lock manager path\n' >&2
    exit 1
fi

lock_action="${1:-}"
case "$lock_action" in
    lock|lock-prepared)
        [[ $# -eq 1 ]] || { printf 'Unexpected lock arguments\n' >&2; exit 2; }
        [[ -f "$manager" ]] || {
            printf 'Refusing lock: secure Quickshell manager is unavailable.\n' >&2
            exit 1
        }
        # Never claim a compositor-secure lock merely because Quickshell
        # started. Wait for WlSessionLock.secure from the actual locker.
        bash "$manager" "$lock_action"
        bash "$manager" wait-secure 5
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
