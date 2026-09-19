#!/usr/bin/env bash
# Rotate the focused monitor's Quickshell bar between horizontal and vertical.

set -euo pipefail

QS_SH="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/quickshell.sh"

if qs -c awtarchy ipc call control rotateBarFocused >/dev/null 2>&1; then
    exit 0
fi

exec "$QS_SH" rotate-focused
