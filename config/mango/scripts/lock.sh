#!/usr/bin/env bash
# Verified compositor lock fallback during the Mango migration trial.
# The user-owned Hyprland Quickshell lockscreen remains unchanged.
set -euo pipefail

lock_screen() {
    command -v swaylock >/dev/null 2>&1 || {
        printf 'Mango lock requires swaylock.\n' >&2
        return 127
    }
    # Never trust the PID of a lock on another graphical session.
    # --daemonize returns only after ext-session-lock-v1 acquisition.
    swaylock -f -c 10151c
}

case "${1:-}" in
    lock|lock-prepared)
        [[ $# -eq 1 ]] || { printf 'lock accepts no extra arguments\n' >&2; false; }
        lock_screen
        ;;
    wait-secure)
        printf 'Mango lock -f itself confirms security. No separate readiness query exists.\n' >&2
        false
        ;;
    status)
        if pgrep -u "$(id -u)" -x swaylock >/dev/null 2>&1; then
            printf 'running\n'
        else
            printf 'unlocked\n'
        fi
        ;;
    hibernate|suspend)
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
