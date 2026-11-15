#!/usr/bin/env bash
# Awtarchy KWin experimental TTY shortcut; no production session is enabled.
set -euo pipefail

main() {
    if (( $# )); then
        [[ -x /usr/bin/kwin_wayland ]] || {
            printf 'Native kwin_wayland is unavailable.\n' >&2
            return 127
        }
        /usr/bin/kwin_wayland "$@"
        return $?
    fi
    [[ -n ${HOME:-} && $HOME == /* ]] || {
        printf 'KWin trial: missing login HOME.\n' >&2
        return 1
    }
    local trial="${XDG_DATA_HOME:-$HOME/.local/share}/awtarchy-kwin-trial"
    [[ -f "$trial/tty-smoke.sh" && ! -L "$trial/tty-smoke.sh" &&
        -O "$trial/tty-smoke.sh" ]] || {
        printf 'KWin trial source missing or unsafe: %s\n' "$trial" >&2
        return 1
    }
    AWTARCHY_KWIN_SMOKE=yes bash "$trial/tty-smoke.sh"
}

main "$@"
