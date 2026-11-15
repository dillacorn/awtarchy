#!/usr/bin/env bash
# Child session for the disposable KWin DRM smoke test.
# A small Quickshell panel + Foot; closing Foot ends the child session.
set -euo pipefail

[[ "${XDG_CURRENT_DESKTOP:-}" == awtarchy-kwin-smoke &&
   "${XDG_SESSION_TYPE:-}" == wayland &&
   -n "${WAYLAND_DISPLAY:-}" ]] || {
    printf 'KWin probe: not an isolated Wayland test session.\n' >&2
    return 1 2>/dev/null || false
}
[[ -n "${XDG_CONFIG_HOME:-}" ]] || {
    printf 'KWin probe: isolated config is unavailable.\n' >&2
    return 1 2>/dev/null || false
}
config="$XDG_CONFIG_HOME/quickshell/awtarchy-kwin-smoke/shell.qml"
[[ -f "$config" && ! -L "$config" && -O "$config" ]] || {
    printf 'KWin probe: missing private Quickshell panel.\n' >&2
    return 1 2>/dev/null || false
}
for binary in /usr/bin/foot /usr/bin/qs /usr/bin/python3; do
    [[ -x "$binary" ]] || {
        printf 'KWin probe: missing %s\n' "$binary" >&2
        return 1 2>/dev/null || false
    }
done

origin="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
[[ -f "$origin/bridge-client.py" && ! -L "$origin/bridge-client.py" ]] || {
    printf 'KWin probe: private bridge client is missing.\n' >&2
    return 1 2>/dev/null || false
}
# The receiver started before KWin, but needs this child's exact Wayland
# socket for launching allowlisted applications.
python3 "$origin/bridge-client.py" "$WAYLAND_DISPLAY" || {
    printf 'KWin probe: workspace bridge refused the active Wayland socket.\n' >&2
    return 1 2>/dev/null || false
}

shell_pid=''
cleanup() {
    if [[ -n $shell_pid ]] && kill -0 "$shell_pid" 2>/dev/null; then
        kill -TERM "$shell_pid" 2>/dev/null || :
        wait "$shell_pid" 2>/dev/null || :
    fi
}
trap cleanup EXIT

/usr/bin/qs -c awtarchy-kwin-smoke &
shell_pid=$!

printf 'KWin probe: Quickshell panel process %s; opening Foot.\n' "$shell_pid"
/usr/bin/foot
