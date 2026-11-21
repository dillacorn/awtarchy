#!/usr/bin/env bash
# Quickshell entrypoint for Umbriel's independent native block_capture rules.
set -euo pipefail
[[ "${XDG_CURRENT_DESKTOP,,}" == umbriel && -n "${WAYLAND_DISPLAY:-}" ]] || {
    printf 'Umbriel Screen Share Guard requires an active session\n' >&2
    false
}
helper="${XDG_CONFIG_HOME:-$HOME/.config}/umbriel/awtarchy/screenshare-guard.py"
[[ -f "$helper" && ! -L "$helper" ]] || {
    printf 'Missing Umbriel Screen Share Guard backend\n' >&2
    false
}
python3 "$helper" "$@"
