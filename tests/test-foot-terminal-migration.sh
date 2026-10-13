#!/usr/bin/env bash
# Static integration checks for Awtarchy's full Foot terminal transition.
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
require "$RUNTIME" 'config_dirs=(hypr quickshell foot '
require "$RUNTIME" '.config/foot/*'
require "$RUNTIME" '"alacritty", "foot",'
require "$HYPR" 'local terminal = "foot"'
grep -Fxq -- "local yazi = \"foot -f 'JetBrainsMono Nerd Font Mono:size=12' yazi\"" "$HYPR" || {
    printf '%s\n' 'FAIL: the Foot Yazi command is malformed' >&2
    exit 1
}
if command -v lua >/dev/null 2>&1; then
    HYPR_TO_CHECK="$HYPR" lua -e 'assert(loadfile(os.getenv("HYPR_TO_CHECK")))'
    printf 'PASS: Hyprland Lua syntax validated\n'
fi
require "$HELPER" 'exec foot --app-id="$window_class"'
require "$LAUNCHER" 'command: ["foot", ...entry.command]'
require "$CONFIG" 'font=NotoSansM Nerd Font Mono:size=12'
require "$CONFIG" 'pad=22x22'
require "$CONFIG" 'alpha=0.85'
# Alacritty Graphics may remain installed as an optional user-managed terminal.
# The Foot migration must never uninstall it or remove its existing config.
if grep -Fq 'remove_retired_alacritty_packages' "$RUNTIME"; then
    printf 'FAIL: Awtarchy must not uninstall Alacritty during the Foot migration\n' >&2
    exit 1
fi
require "$RUNTIME" 'if rel.startswith(".config/alacritty/") and ni is None:'
require "$RUNTIME" 'if ! pacman -Qq foot >/dev/null 2>&1; then'
require "$RUNTIME" 'pacman_install_one foot'
require "$CONFIG" 'alpha=0.85'
require "$ROOT/config/hypr/scripts/quickshell_theme_apply.sh" 'FOOT_CONF="$CONFIG_HOME/foot/foot.ini"'
require "$ROOT/config/hypr/scripts/quickshell_theme_catalog.sh" '"foot": path.name,'
if grep -Eq '^[[:space:]]*alacritty-graphics([[:space:]]|$)' "$RUNTIME"; then
    printf 'FAIL: Alacritty Graphics remains in the package catalog\n' >&2
    exit 1
fi
require "$RUNTIME" 'local -a required=(quickshell foot upower'
require "$ROOT/config/hypr/scripts/awtarchy-polkit-agent/launcher.sh" 'FOOT="/usr/bin/foot"'

for quicksettings in "$ROOT/config/hypr/scripts/hypr_quicksettings.sh" "$ROOT/config/hypr/scripts/hypr_quicksettings_core.sh"; do
    require "$quicksettings" 'exec foot --app-id="$TERM_CLASS"'
    if grep -Eiq 'alacritty|exec kitty|exec xterm' "$quicksettings"; then
        printf 'FAIL: retired terminal launch path still exists: %s\n' "$quicksettings" >&2
        exit 1
    fi
done
require "$ROOT/config/hypr/scripts/hypr_quicksettings_core.sh" "printf -v launch_cmd 'foot --app-id wallpicker %q --resume'"


if command -v foot >/dev/null 2>&1; then
    foot --check-config --config="$CONFIG"
    printf 'PASS: Foot configuration validated with installed Foot\n'
else
    printf 'SKIP: Foot binary unavailable; native config validation needs the Arch test machine\n'
fi

printf 'PASS: Foot terminal migration and optional Alacritty preservation contracts\n'
