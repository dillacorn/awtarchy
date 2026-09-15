#!/usr/bin/env bash
# Toggle the Awtarchy Quickshell power/session menu.

set -euo pipefail
SCRIPTS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts"
"$SCRIPTS_DIR/quickshell.sh" start >/dev/null
if [[ -x "$SCRIPTS_DIR/quickshell_lockscreen_capture.sh" ]]; then
    "$SCRIPTS_DIR/quickshell_lockscreen_capture.sh" stage >/dev/null 2>&1 || true
fi
exec qs -c awtarchy ipc call powermenu toggle
