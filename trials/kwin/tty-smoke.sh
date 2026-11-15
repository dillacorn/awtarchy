#!/usr/bin/env bash
# Manual, isolated KWin DRM bring-up only. NOT an Awtarchy desktop session.
set -euo pipefail

fail() { printf 'KWin smoke test: %s\n' "$*" >&2; return 1; }

main() {
    [[ ${EUID} -ne 0 ]] || { fail 'Never run as root.'; return 1; }
    [[ ${AWTARCHY_KWIN_SMOKE:-} == yes ]] || {
        fail 'Explicit opt-in required: AWTARCHY_KWIN_SMOKE=yes'; return 1;
    }
    [[ -t 0 && -t 1 ]] || { fail 'Use an interactive local TTY.'; return 1; }
    local vt=''
    vt="$(tty)" || { fail 'Could not identify active TTY.'; return 1; }
    [[ $vt =~ ^/dev/tty[0-9]+$ ]] || {
        fail "Expected a local VT, got $vt"; return 1;
    }
    [[ -z ${WAYLAND_DISPLAY:-} && -z ${DISPLAY:-} && ${XDG_SESSION_TYPE:-tty} == tty ]] || {
        fail 'Existing graphical session detected; run from a plain TTY.'; return 1;
    }
    [[ -n ${XDG_RUNTIME_DIR:-} && -d $XDG_RUNTIME_DIR && -O $XDG_RUNTIME_DIR ]] || {
        fail 'Expected an owned XDG_RUNTIME_DIR from the login session.'; return 1;
    }
    local binary
    for binary in /usr/bin/kwin_wayland /usr/bin/foot /usr/bin/python3; do
        [[ -x $binary && ! -L $binary ]] || {
            fail "Missing or unsafe executable: $binary"; return 1;
        }
    done
    command -v pgrep >/dev/null 2>&1 || {
        fail 'pgrep is required to verify compositor isolation.'; return 1;
    }
    [[ -S "$XDG_RUNTIME_DIR/bus" ]] || {
        fail 'A user D-Bus session socket is required.'; return 1;
    }
    local compositor
    for compositor in Hyprland sway kwin_wayland; do
        if pgrep -u "$(id -u)" -x "$compositor" >/dev/null 2>&1; then
            fail "Existing compositor $compositor is running; end that session normally first."
            return 1
        fi
    done

    local state="${XDG_STATE_HOME:-$HOME/.local/state}/awtarchy" private=''
    [[ ! -L $state && ( ! -e $state || -d $state ) ]] || {
        fail 'State directory is a symlink or not a directory.'; return 1;
    }
    install -d -m 0700 -- "$state" || return 1
    private="$(mktemp -d -- "$state/kwin-smoke.XXXXXX")" || return 1
    local origin
    origin="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)" || return 1
    [[ -f "$origin/prepare-session.py" && ! -L "$origin/prepare-session.py" ]] || {
        fail 'Private KWin stage helper is missing or unsafe.'; return 1;
    }
    python3 "$origin/prepare-session.py" --root "$private" --check || return 1
    python3 "$origin/prepare-session.py" --root "$private" --stage || return 1
    install -d -m 0700 -- "$private/cache" || return 1

    printf 'Starting temporary KWin DRM smoke test on %s.\n' "$vt"
    printf 'No Awtarchy shell or security lock is enabled; experimental numbered-workspace shortcuts are loaded.\n'
    printf 'Close the Foot window to ask KWin to return to your TTY.\n'
    printf 'Isolated test settings: %s\n' "$private/config"

    env -u WAYLAND_DISPLAY -u DISPLAY \
        XDG_CONFIG_HOME="$private/config" \
        XDG_DATA_HOME="$private/data" \
        XDG_CACHE_HOME="$private/cache" \
        XDG_CURRENT_DESKTOP=awtarchy-kwin-smoke \
        XDG_SESSION_DESKTOP=awtarchy-kwin-smoke \
        XDG_SESSION_TYPE=wayland \
        /usr/bin/kwin_wayland --drm --xwayland --no-lockscreen \
            --no-kactivities --exit-with-session=/usr/bin/foot
}

main "$@"
