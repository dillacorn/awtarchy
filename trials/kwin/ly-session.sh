#!/usr/bin/env bash
# Root-owned Ly session wrapper, executed as the logged-in user.
set -euo pipefail

main() {
    [[ "$(id -u)" -ne 0 && -n "${HOME:-}" && "$HOME" == /* ]] || {
        printf 'Awtarchy KWin Ly: expected an ordinary login user.\n' >&2
        return 1
    }
    [[ $# -eq 0 ]] || { printf 'Unexpected KWin Ly arguments.\n' >&2; return 2; }
    local source="${XDG_DATA_HOME:-$HOME/.local/share}/awtarchy-kwin-trial/tty-smoke.sh"
    [[ -f "$source" && ! -L "$source" && -O "$source" ]] || {
        printf 'Missing or unsafe user KWin trial: %s\n' "$source" >&2
        return 1
    }
    [[ -z "${WAYLAND_DISPLAY:-}" && -z "${DISPLAY:-}" ]] || {
        printf 'KWin Ly: existing graphical display; refusing nested launch.\n' >&2
        return 1
    }
    # Ly desktop entries may inherit XDG_SESSION_TYPE=tty from their login VT.
    # The selected .desktop is explicitly a Wayland compositor session.
    export XDG_CURRENT_DESKTOP=awtarchy-kwin-smoke
    export XDG_SESSION_DESKTOP=awtarchy-kwin-smoke
    export XDG_SESSION_TYPE=wayland
    # Preserve this attempt's output even after the next successful Ly login
    # overwrites ~/.local/state/ly-session.log.
    local state="${XDG_STATE_HOME:-$HOME/.local/state}/awtarchy"
    [[ ! -L "$state" && ( ! -e "$state" || ( -d "$state" && -O "$state" ) ) ]] || {
        printf 'KWin Ly: unsafe session log directory: %s\n' "$state" >&2
        return 1
    }
    install -d -m 0700 -- "$state" || return 1
    local log=''
    log="$(mktemp -- "$state/kwin-ly.XXXXXXXX.log")" || return 1
    chmod 0600 -- "$log" || return 1
    if AWTARCHY_KWIN_SMOKE=yes bash "$source" --ly >"$log" 2>&1; then
        printf 'KWin Ly session ended normally. Log: %s\n' "$log"
    else
        local status=$?
        printf 'KWin Ly session failed (status %s). Log: %s\n' "$status" "$log" >&2
        return "$status"
    fi
}

main "$@"
