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
require "$CONFIG" '[colors-dark]'
require "$CONFIG" 'alpha=0.85'
if grep -Fxq '[colors]' "$CONFIG"; then
    printf 'FAIL: obsolete Foot [colors] section\n' >&2
    exit 1
fi
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
require "$ROOT/config/hypr/scripts/quickshell_theme_apply.sh" 'foot_theme_live.py'
require "$ROOT/config/hypr/scripts/foot_theme_live.py" 'def broadcast(colors:'
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


# Theme switching must update all 18 ANSI/foreground/background entries,
# preserve the existing terminal opacity, and leave optional Alacritty alone.
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/config/foot/themes" "$tmp/config/hypr/themes" "$tmp/config/alacritty" "$tmp/fakebin"
cp -- "$CONFIG" "$tmp/config/foot/foot.ini"
cp -- "$ROOT"/config/foot/themes/*.ini "$tmp/config/foot/themes/"
cp -- "$ROOT"/config/hypr/themes/* "$tmp/config/hypr/themes/"
printf '%s\n' '[window]' 'opacity = 0.85' >"$tmp/config/alacritty/alacritty.toml"
printf '#!/usr/bin/env bash\nexit 0\n' >"$tmp/fakebin/hyprctl"
printf '#!/usr/bin/env bash\nexit 1\n' >"$tmp/fakebin/systemctl"
chmod 0755 "$tmp/fakebin/hyprctl" "$tmp/fakebin/systemctl"

for theme in carbon_night catppuccin-frappé crimson_red electric_blue gruvbox iron_forge obsidian_night pink pipboy; do
    palette="$tmp/config/foot/themes/${theme}.ini"
    [[ -f "$palette" ]] || { printf 'FAIL: missing Foot palette: %s\n' "$theme" >&2; exit 1; }
    [[ "$(grep -Ec '^(background|foreground|regular[0-7]|bright[0-7])=[0-9a-f]{6}$' "$palette")" -eq 18 ]] || {
        printf 'FAIL: incomplete Foot palette: %s\n' "$theme" >&2
        exit 1
    }
    XDG_CONFIG_HOME="$tmp/config" XDG_STATE_HOME="$tmp/state" \
        PATH="$tmp/fakebin:$PATH" \
        bash "$ROOT/config/hypr/scripts/quickshell_theme_apply.sh" "$theme"
    while IFS= read -r entry; do
        [[ "$entry" == \#* || -z "$entry" ]] && continue
        grep -Fxq -- "$entry" "$tmp/config/foot/foot.ini" || {
            printf 'FAIL: switched Foot palette did not match %s: %s\n' "$theme" "$entry" >&2
            exit 1
        }
    done <"$palette"
    grep -Fxq 'alpha=0.85' "$tmp/config/foot/foot.ini" || {
        printf 'FAIL: Foot opacity changed while switching themes\n' >&2
        exit 1
    }
done
grep -Fxq 'opacity = 0.85' "$tmp/config/alacritty/alacritty.toml" || {
    printf 'FAIL: Foot theme switching touched optional Alacritty settings\n' >&2
    exit 1
}

# Test actual updater theme inference without installing or touching user configs.
# Only source its extracted function definitions, not the installer.
theme_functions="$tmp/theme-functions.sh"
sed -n \
    -e '/^valid_theme_name() {/,/^}/p' \
    -e '/^infer_prior_alacritty_theme() {/,/^}/p' \
    -e '/^infer_active_theme() {/,/^}/p' \
    "$RUNTIME" >"$theme_functions"
# shellcheck source=/dev/null
source "$theme_functions"
HOME_DIR="$tmp/migration-home"
ACTIVE_THEME_FILE="$tmp/migration-active-theme"
mkdir -p "$HOME_DIR/.config/alacritty" "$HOME_DIR/.config/SpeedCrunch" "$HOME_DIR/.config/foot"
alacritty_conf="$HOME_DIR/.config/alacritty/alacritty.toml"

printf '%s\n' carbon_night >"$ACTIVE_THEME_FILE"
for theme in carbon_night catppuccin-frappé crimson_red electric_blue gruvbox iron_forge obsidian_night pink pipboy; do
    palette="$ROOT/config/foot/themes/${theme}.ini"
    old_scheme="$(sed -n 's|^# Derived from alacritty/alacritty-theme/themes/\(.*\.toml\)\.$|\1|p' "$palette")"
    [[ -n "$old_scheme" ]] || { printf 'FAIL: missing original Alacritty theme mapping: %s\n' "$theme" >&2; exit 1; }
    printf '[general]\nimport = ["~/.config/alacritty/themes/themes/%s"]\n' "$old_scheme" >"$alacritty_conf"
    selected="$(infer_active_theme "$ROOT")"
    [[ "$selected" == "$theme" ]] || {
        printf 'FAIL: Foot migration selected %s instead of Alacritty theme %s\n' "$selected" "$theme" >&2
        exit 1
    }
done

printf '[general]\nimport = ["~/.config/alacritty/custom-theme.toml"]\n' >"$alacritty_conf"
[[ "$(infer_active_theme "$ROOT")" == carbon_night ]] || {
    printf 'FAIL: an unknown Alacritty theme displaced saved Awtarchy theme\n' >&2
    exit 1
}
cp "$CONFIG" "$HOME_DIR/.config/foot/foot.ini"
printf '[general]\nimport = ["~/.config/alacritty/themes/themes/gruvbox_dark.toml"]\n' >"$alacritty_conf"
[[ "$(infer_active_theme "$ROOT")" == carbon_night ]] || {
    printf 'FAIL: optional Alacritty displaced an existing Foot theme\n' >&2
    exit 1
}
rm -f -- "$ACTIVE_THEME_FILE"
printf 'Display\\ColorSchemeName=gruvbox\n' >"$HOME_DIR/.config/SpeedCrunch/SpeedCrunch.ini"
[[ "$(infer_active_theme "$ROOT")" == gruvbox ]] || {
    printf 'FAIL: former SpeedCrunch theme fallback changed\n' >&2
    exit 1
}

if command -v foot >/dev/null 2>&1; then
    foot --check-config --config="$CONFIG"
    printf 'PASS: Foot configuration validated with installed Foot\n'
else
    printf 'SKIP: Foot binary unavailable; native config validation needs the Arch test machine\n'
fi

printf 'PASS: Foot terminal migration and optional Alacritty preservation contracts\n'
