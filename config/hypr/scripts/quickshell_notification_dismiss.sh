#!/usr/bin/env bash
# Hide the first visible Awtarchy Quickshell popup without deleting its history entry.

set -euo pipefail

SCRIPTS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts"

if qs -c awtarchy ipc call notifications hideFirstPopup >/dev/null 2>&1; then
    exit 0
fi

"$SCRIPTS_DIR/quickshell.sh" start >/dev/null
exec qs -c awtarchy ipc call notifications hideFirstPopup
