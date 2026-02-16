#!/usr/bin/env bash
# github.com/dillacorn/awtarchy/tree/main/config/hypr/scripts
# ~/.config/hypr/scripts/wlogout_toggle.sh
# 
# Toggle wlogout and warn if Caps Lock is active.

set -euo pipefail

# If wlogout is running, close it.
if pgrep -x wlogout >/dev/null; then
    pkill -x wlogout
    exit 0
fi

# Check Caps Lock state.
if [[ "$(hyprctl devices -j | jq -r '.keyboards[] | select(.main == true) | .capsLock')" == "true" ]]; then
    hyprctl notify -1 3000 "rgb(ff0000)" "Caps Lock is ON — disable it or use lowercase"
fi

# Launch wlogout.
wlogout
