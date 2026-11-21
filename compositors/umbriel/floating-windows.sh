#!/usr/bin/env bash
# Keep Quickshell floating-only control isolated to Umbriel.
set -euo pipefail
[[ "${XDG_CURRENT_DESKTOP,,}" == umbriel && -n "${WAYLAND_DISPLAY:-}" ]] || {
    printf 'Umbriel session required\n' >&2
    false
}
script="${XDG_CONFIG_HOME:-$HOME/.config}/umbriel/awtarchy/floating-windows.py"
[[ -f "$script" && ! -L "$script" ]] || {
    printf 'Umbriel floating helper missing\n' >&2
    false
}
python3 "$script" "$@"
