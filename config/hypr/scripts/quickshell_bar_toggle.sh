#!/usr/bin/env bash
# Toggle Quickshell bar auto-hide on the focused or requested monitor.

set -euo pipefail

QS_SH="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/quickshell.sh"
if [[ -n "${MANGO_INSTANCE_SIGNATURE:-}" ]]; then
    QS_SH="${XDG_CONFIG_HOME:-$HOME/.config}/mango/scripts/quickshell.sh"
fi

case "${1:-}" in
    --mon)
        [[ -n "${2:-}" ]] || {
            printf 'usage: quickshell_bar_toggle.sh --mon <MON>\n' >&2
            exit 2
        }
        exec "$QS_SH" toggle-autohide-mon "$2"
        ;;
    ""|--focused|-f)
        if qs -c "${QUICKSHELL_CONFIG_NAME:-awtarchy}" ipc call control toggleBarAutoHideFocused >/dev/null 2>&1; then
            exit 0
        fi
        exec "$QS_SH" toggle-autohide-focused
        ;;
    *)
        printf 'usage: quickshell_bar_toggle.sh [--focused] | --mon <MON>\n' >&2
        exit 2
        ;;
esac
