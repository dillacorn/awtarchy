#!/usr/bin/env bash
# Verified compositor lock fallback during the Mango migration trial.
# The user-owned Hyprland Quickshell lockscreen remains unchanged.
set -euo pipefail

lock_screen() {
    command -v swaylock >/dev/null 2>&1 || {
        printf 'Mango lock requires swaylock.\n' >&2
        return 127
    }
    if pgrep -u "$(id -u)" -x swaylock >/dev/null 2>&1; then
        return 0
    fi
    # --daemonize returns only after ext-session-lock-v1 acquisition.
    swaylock -f -c 10151c
}

wait_secure() {
    local seconds="${1:-5}" count
    [[ "$seconds" =~ ^[1-9][0-9]*$ && "$seconds" -le 30 ]] || return 2
    for ((count=0; count<seconds*10; count++)); do
        if pgrep -u "$(id -u)" -x swaylock >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.1
    done
    return 1
}

case "${1:-}" in
    lock|lock-prepared)
        [[ $# -eq 1 ]] || { printf 'lock accepts no extra arguments\n' >&2; false; }
        lock_screen
        ;;
    wait-secure)
        [[ $# -le 2 ]] || { printf 'wait-secure [seconds]\n' >&2; false; }
        wait_secure "${2:-5}"
        ;;
    status)
        if pgrep -u "$(id -u)" -x swaylock >/dev/null 2>&1; then
            printf 'secure\n'
        else
            printf 'unlocked\n'
        fi
        ;;
    hibernate|suspend)
        action="$1"
        lock_screen && wait_secure 5 || {
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
        printf 'usage: lock.sh {lock|lock-prepared|wait-secure [seconds]|status|suspend|hibernate}\n' >&2
        false
        ;;
esac
