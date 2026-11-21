#!/usr/bin/env bash
# Umbriel panel position belongs to Quickshell's native layer-shell surface.
set -euo pipefail
[[ -n "${WAYLAND_DISPLAY:-}" ]] || { printf 'Umbriel Wayland session required\n' >&2; false; }
[[ $# -ge 1 ]] || { printf 'No flyout action\n' >&2; false; }
case "$1" in
    prepare|spawn|resize|clamp|position)
        # The layer-shell QML already selects its monitor, anchors, and dimensions.
        ;;
    *)
        printf 'Unsupported Umbriel flyout positioning action: %s\n' "$1" >&2
        false ;;
esac
