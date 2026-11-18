#!/usr/bin/env bash
# Manual, isolated KWin DRM bring-up only. NOT an Awtarchy desktop session.
set -euo pipefail
umask 077

fail() { printf 'KWin smoke test: %s\n' "$*" >&2; return 1; }

valid_system_executable() {
    # Arch officially packages command aliases such as /usr/bin/python3 as
    # symlinks to versioned, executable files. Reject broken/non-executable
    # targets, not symlinks themselves. /usr/bin is root-owned.
    local binary="$1"
    [[ -f "$binary" && -x "$binary" ]]
}

main() {
    [[ ${EUID} -ne 0 ]] || { fail 'Never run as root.'; return 1; }
    [[ ${AWTARCHY_KWIN_SMOKE:-} == yes ]] || {
        fail 'Explicit opt-in required: AWTARCHY_KWIN_SMOKE=yes'; return 1;
    }
    # Ly normally launches Wayland sessions without interactive stdin/stdout,
    # so the TTY-only check is replaced by a separate, explicit --ly path.
    local vt=''
    case "${1:-}" in
        '')
            [[ $# -eq 0 ]] || { fail 'Unexpected trial arguments'; return 2; }
            [[ -t 0 && -t 1 ]] || { fail 'Use an interactive local TTY.'; return 1; }
            vt="$(tty)" || { fail 'Could not identify active TTY.'; return 1; }
            [[ $vt =~ ^/dev/tty[0-9]+$ ]] || {
                fail "Expected a local VT, got $vt"; return 1;
            }
            [[ ${XDG_SESSION_TYPE:-tty} == tty ]] || {
                fail 'TTY mode expects a plain login terminal.'; return 1;
            }
            ;;
        --ly)
            [[ $# -eq 1 && ${XDG_SESSION_TYPE:-} == wayland ]] || {
                fail 'Ly mode expects one Wayland login session.'; return 1;
            }
            vt="Ly"
            ;;
        *)
            fail 'Usage: tty-smoke.sh [--ly]'
            return 2
            ;;
    esac
    [[ -z ${WAYLAND_DISPLAY:-} && -z ${DISPLAY:-} ]] || {
        fail 'Existing graphical display detected; refusing nested KWin.'; return 1;
    }
    [[ -n ${XDG_RUNTIME_DIR:-} && -d $XDG_RUNTIME_DIR && -O $XDG_RUNTIME_DIR ]] || {
        fail 'Expected an owned XDG_RUNTIME_DIR from the login session.'; return 1;
    }
    local binary
    for binary in /usr/bin/kwin_wayland /usr/bin/foot /usr/bin/fuzzel /usr/bin/python3 /usr/bin/qs; do
        valid_system_executable "$binary" || {
            fail "Missing or unsafe executable: $binary"; return 1;
        }
    done
    /usr/bin/python3 -c 'import dbus_next' >/dev/null 2>&1 || {
        fail 'python-dbus-next is required for isolated workspace state.'; return 1;
    }
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
    [[ -f "$origin/bridge-client.py" && ! -L "$origin/bridge-client.py" ]] || {
        fail 'KWin bridge client script is missing or unsafe.'; return 1;
    }
    [[ -f "$origin/probe-session.sh" && ! -L "$origin/probe-session.sh" ]] || {
        fail 'KWin probe session script is missing or unsafe.'; return 1;
    }
    bash -n "$origin/probe-session.sh" || return 1
    [[ -f "$origin/prepare-session.py" && ! -L "$origin/prepare-session.py" ]] || {
        fail 'Private KWin stage helper is missing or unsafe.'; return 1;
    }
    python3 "$origin/prepare-session.py" --root "$private" --check || return 1
    python3 "$origin/prepare-session.py" --root "$private" --stage || return 1
    [[ -f "$origin/state-bridge.py" && ! -L "$origin/state-bridge.py" ]] || {
        fail 'KWin workspace bridge source missing or unsafe.'; return 1;
    }
    install -d -m 0700 -- "$private/cache" "$private/runtime" || return 1

    # Claim the private D-Bus receiver before KWin scripts publish their
    # initial workspace state. Never start an unrelated user service.
    local bridge_pid='' attempt
    stop_bridge() {
        if [[ -n "$bridge_pid" ]] && kill -0 "$bridge_pid" 2>/dev/null; then
            kill -TERM "$bridge_pid" 2>/dev/null || :
            wait "$bridge_pid" 2>/dev/null || :
        fi
    }
    trap stop_bridge EXIT
    /usr/bin/python3 "$origin/state-bridge.py" --state-dir "$private/runtime" \
        > "$private/bridge.log" 2>&1 &
    bridge_pid=$!
    for (( attempt=0; attempt<40; attempt++ )); do
        [[ -f "$private/runtime/ready" && ! -L "$private/runtime/ready" ]] && break
        if ! kill -0 "$bridge_pid" 2>/dev/null; then
            fail 'KWin D-Bus bridge terminated; see private bridge.log.'
            return 1
        fi
        sleep 0.05
    done
    [[ -f "$private/runtime/ready" ]] || {
        fail 'Timed out waiting for KWin D-Bus bridge initialization.'
        return 1
    }

    printf 'Starting temporary KWin DRM smoke test on %s.\n' "$vt"
    printf 'No Awtarchy shell or security lock is enabled; experimental numbered-workspace shortcuts are loaded.\n'
    printf 'A small temporary Quickshell panel and a Foot terminal will open.\n'
    printf 'Close the Foot window to ask KWin to return to your TTY.\n'
    printf 'Isolated test settings: %s\n' "$private/config"

    env -u WAYLAND_DISPLAY -u DISPLAY \
        XDG_CONFIG_HOME="$private/config" \
        XDG_DATA_HOME="$private/data" \
        XDG_CACHE_HOME="$private/cache" \
        AWTARCHY_KWIN_STATE_FILE="$private/runtime/workspace-state.json" \
        XDG_CURRENT_DESKTOP=awtarchy-kwin-smoke \
        XDG_SESSION_DESKTOP=awtarchy-kwin-smoke \
        XDG_SESSION_TYPE=wayland \
        /usr/bin/kwin_wayland --drm --xwayland --no-lockscreen \
            --no-kactivities --exit-with-session="$origin/probe-session.sh"
}

main "$@"
