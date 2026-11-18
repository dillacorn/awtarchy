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
    AWTARCHY_KWIN_SMOKE=yes bash "$source" --ly
}

main "$@"
