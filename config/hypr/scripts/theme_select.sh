#!/usr/bin/env bash
# Awtarchy theme picker rendered by Quickshell.

set -euo pipefail

SCRIPTS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts"

if qs -c awtarchy ipc call themes toggle >/dev/null 2>&1; then
    exit 0
fi

"$SCRIPTS_DIR/quickshell.sh" start >/dev/null
exec qs -c awtarchy ipc call themes toggle
