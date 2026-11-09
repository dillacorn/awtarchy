#!/usr/bin/env bash
# Awtarchy theme picker rendered by Quickshell.

set -euo pipefail

SCRIPTS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts"
if [[ -n "${MANGO_INSTANCE_SIGNATURE:-}" ]]; then
    SCRIPTS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/mango/scripts"
fi

if qs -c "${QUICKSHELL_CONFIG_NAME:-awtarchy}" ipc call themes toggle >/dev/null 2>&1; then
    exit 0
fi

"$SCRIPTS_DIR/quickshell.sh" start >/dev/null
exec qs -c "${QUICKSHELL_CONFIG_NAME:-awtarchy}" ipc call themes toggle
