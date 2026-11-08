#!/usr/bin/env bash
# Cold-start safe Awtarchy power-menu handler for MangoWM.
set -euo pipefail
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
response="$(qs -c awtarchy-mango ipc call powermenu begin 2>/dev/null | tail -n1 || true)"
if [[ "$response" != true && "$response" != false ]]; then
    bash "$config_home/mango/scripts/quickshell.sh" start >/dev/null
    qs -c awtarchy-mango ipc call powermenu begin
fi
