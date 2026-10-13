#!/usr/bin/env bash
# Static integration checks for the initial Foot testing stage.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME="$ROOT/local/share/awtarchy/awtarchy-runtime.sh"
HYPR="$ROOT/config/hypr/hyprland.lua"
HELPER="$ROOT/config/hypr/scripts/default_terminal.sh"
LAUNCHER="$ROOT/config/quickshell/awtarchy/Launcher.qml"
CONFIG="$ROOT/config/foot/foot.ini"

require() {
    grep -Fq -- "$2" "$1" || {
        printf 'FAIL: missing %s in %s\n' "$2" "$1" >&2
        return 1
    }
}

[[ -f "$CONFIG" ]] || { printf 'FAIL: Foot profile is missing\n' >&2; exit 1; }
require "$RUNTIME" 'Terminal Apps:foot '
require "$RUNTIME" 'config_dirs=(hypr quickshell alacritty foot '
require "$RUNTIME" '.config/foot/*'
require "$RUNTIME" '"alacritty", "foot",'
require "$HYPR" 'local terminal = "foot"'
require "$HYPR" "local yazi = \"foot -f 'JetBrainsMono Nerd Font Mono:size=12' yazi\""
require "$HELPER" 'for candidate in foot footclient kitty alacritty'
require "$LAUNCHER" 'command: ["foot", ...entry.command]'
require "$CONFIG" 'font=NotoSansM Nerd Font Mono:size=12'
require "$CONFIG" 'pad=22x22'
require "$CONFIG" 'alpha=0.85'

if command -v foot >/dev/null 2>&1; then
    foot --check-config --config="$CONFIG"
    printf 'PASS: Foot configuration validated with installed Foot\n'
else
    printf 'SKIP: Foot binary unavailable; native config validation needs the Arch test machine\n'
fi

printf 'PASS: Foot testing-stage integration contracts\n'
