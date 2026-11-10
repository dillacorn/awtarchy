#!/usr/bin/env bash
# Privileged Jay session lock with verified secure state before power transition.
set -euo pipefail
[[ "${XDG_CURRENT_DESKTOP:-}" == jay && -n "${WAYLAND_DISPLAY:-}" ]] || {
    printf 'Jay lock requires a live Jay Wayland session\n' >&2; exit 1;
}
status() {
    qs -c awtarchy-lock ipc call lock state 2>/dev/null | tail -n1 || true
}
wait_secure() {
    local i
    for ((i=0;i<100;i++)); do
        [[ "$(status)" == secure ]] && return 0
        sleep 0.05
    done
    return 1
}
lock_now() {
    [[ "$(status)" == secure ]] && return 0
    # The Jay compositor grants ext-session-lock only to privileged clients.
    # Keep the original Awtarchy WlSessionLock QML, without Hyprland captures.
    if command -v jay >/dev/null 2>&1 && command -v qs >/dev/null 2>&1; then
        nohup jay run-privileged qs -c awtarchy-lock >/dev/null 2>&1 &
        if wait_secure; then return 0; fi
    fi
    # Only a compositor-confirmed swaylock fallback can protect suspend.
    command -v swaylock >/dev/null 2>&1 || return 1
    swaylock -f -c 10151c
}
case "${1:-}" in
    lock|lock-prepared) [[ $# -eq 1 ]] || exit 2; lock_now ;;
    wait-secure) [[ $# -le 2 ]] || exit 2; wait_secure ;;
    status) [[ $# -eq 1 ]] || exit 2; status ;;
    suspend|hibernate)
        [[ $# -eq 1 ]] || exit 2
        lock_now || { printf 'Jay: lock not confirmed, refusing %s\n' "$1" >&2; exit 1; }
        if [[ "$1" == suspend ]]; then systemctl suspend; else systemctl hibernate; fi
        ;;
    *) printf 'usage: lock.sh {lock|lock-prepared|wait-secure|status|suspend|hibernate}\n' >&2; exit 2 ;;
esac
