#!/usr/bin/env bash
# Rotate the focused monitor's Quickshell bar between horizontal and vertical.

set -euo pipefail

QS_SH="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/quickshell.sh"
if [[ -n "${MANGO_INSTANCE_SIGNATURE:-}" ]]; then
    QS_SH="${XDG_CONFIG_HOME:-$HOME/.config}/mango/scripts/quickshell.sh"
fi

if qs -c "${QUICKSHELL_CONFIG_NAME:-awtarchy}" ipc call control rotateBarFocused >/dev/null 2>&1; then
    exit 0
fi

exec "$QS_SH" rotate-focused
