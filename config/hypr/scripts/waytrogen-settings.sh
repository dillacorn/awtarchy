#!/usr/bin/env bash
# github.com/dillacorn/awtarchy/tree/main/config/hypr/scripts
# ~/.config/hypr/scripts/waytrogen-applies_only_once.sh
# 
# Write Waytrogen prefs ONCE. Does NOT pick/apply a wallpaper. Never touches swww.
# Optionally require Waytrogen to be installed.

set -euo pipefail

# Behavior: set to "true" to require Waytrogen; "false" to skip the check
DO_REQUIRE_WAYTROGEN="true"

# No IMG path here anymore
DIR="$HOME/Pictures/wallpapers"

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/waytrogen"
SENTINEL="${STATE_DIR}/defaults_applied"
mkdir -p "$STATE_DIR"
[[ -f "$SENTINEL" ]] && exit 0

command -v dconf >/dev/null || { echo "dconf not found"; exit 1; }
[[ $DO_REQUIRE_WAYTROGEN == "true" ]] && command -v waytrogen >/dev/null || true

# Write prefs to dconf (Waytrogen reads these later)
dconf write /org/Waytrogen/Waytrogen/wallpaper-folder "'$DIR'"
dconf write /org/Waytrogen/Waytrogen/changer 'uint32 1'   # 1 = Swww on your build
dconf write /org/Waytrogen/Waytrogen/monitor 'uint32 0'   # 0 = All

# Do NOT write saved-wallpapers (no forced image selection)

# Optional mirrors (no daemon control); set transitions to 90 FPS
dconf write /org/Waytrogen/Waytrogen/swww-scaling-filter         'uint32 0'  || true
dconf write /org/Waytrogen/Waytrogen/swww-transition-type        'uint32 11' || true
dconf write /org/Waytrogen/Waytrogen/swww-transition-step        '90.0'      || true
dconf write /org/Waytrogen/Waytrogen/swww-transition-duration    '1.0'       || true
dconf write /org/Waytrogen/Waytrogen/swww-transition-fps         'uint32 90' || true
dconf write /org/Waytrogen/Waytrogen/swww-transition-angle       '45.0'      || true
dconf write /org/Waytrogen/Waytrogen/swww-transition-position    "'center'"  || true
dconf write /org/Waytrogen/Waytrogen/swww-transition-wave-width  '200.0'     || true
dconf write /org/Waytrogen/Waytrogen/swww-transition-wave-height '200.0'     || true
dconf write /org/Waytrogen/Waytrogen/swww-invert-y               'false'     || true

: > "$SENTINEL"
exit 0
