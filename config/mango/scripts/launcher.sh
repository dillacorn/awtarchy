#!/usr/bin/env bash
# Cold-start safe Quickshell launcher for the MangoWM desktop.
set -euo pipefail
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
if ! qs -c awtarchy-mango ipc call launcher toggle >/dev/null 2>&1; then
    bash "$config_home/mango/scripts/quickshell.sh" start >/dev/null
    qs -c awtarchy-mango ipc call launcher toggle
fi
