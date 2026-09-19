#!/usr/bin/env bash
# Toggle the Awtarchy Quickshell clipboard history UI.

set -euo pipefail

SCRIPTS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts"

if qs -c awtarchy ipc call clipboard toggle >/dev/null 2>&1; then
    exit 0
fi

"$SCRIPTS_DIR/quickshell.sh" start >/dev/null
exec qs -c awtarchy ipc call clipboard toggle
