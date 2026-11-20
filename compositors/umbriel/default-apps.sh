#!/usr/bin/env bash
# One exact floating default-app selector in an Umbriel session.
set -euo pipefail
[[ "${XDG_CURRENT_DESKTOP,,}" == umbriel && -n "${WAYLAND_DISPLAY:-}" ]] || {
    printf 'Umbriel session required\n' >&2
    false
}
script="${XDG_CONFIG_HOME:-$HOME/.config}/umbriel/awtarchy-trial/toggle-utility.py"
[[ -f "$script" && ! -L "$script" ]] || {
    printf 'Missing native default-app selector helper\n' >&2
    false
}
python3 "$script" default-apps
