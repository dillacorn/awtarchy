#!/usr/bin/env bash
# No Hyprland session-lock shortcuts. The Sway trial uses secure swaylock -f.
set -euo pipefail
[[ "${XDG_CURRENT_DESKTOP:-}" == sway && -n "${WAYLAND_DISPLAY:-}" ]] || {
    printf 'Sway session required for locking\n' >&2; exit 1;
}
lock_now() {
    command -v swaylock >/dev/null 2>&1 || {
        printf 'swaylock is unavailable; refusing lock/power transition\n' >&2
        return 127
    }
    swaylock -f -c 10151c
}
case "${1:-}" in
    lock|lock-prepared)
        [[ $# -eq 1 ]] || { printf 'Unexpected lock arguments\n' >&2; exit 2; }
        lock_now ;;
    suspend|hibernate)
        [[ $# -eq 1 ]] || { printf 'Unexpected power arguments\n' >&2; exit 2; }
        lock_now || { printf 'Lock failed; refusing power operation\n' >&2; exit 1; }
        if [[ "$1" == suspend ]]; then systemctl suspend; else systemctl hibernate; fi ;;
    status)
        printf 'unverified\n'; exit 1 ;;
    wait-secure)
        # Without a session-lock protocol query, do not claim the secure
        # state merely because a process named swaylock exists.
        printf 'Sway lock confirmation not independently available\n' >&2
        exit 1 ;;
    *) printf 'usage: lock.sh lock|lock-prepared|suspend|hibernate|status|wait-secure\n' >&2; exit 2 ;;
esac
