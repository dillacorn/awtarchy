#!/usr/bin/env bash
# Isolated Sway profile install; no Hyprland or unknown custom file overwritten.
set -euo pipefail
fail() { printf 'Sway trial setup: %s\n' "$*" >&2; return 1; }
[[ $# -eq 1 ]] || { fail 'Usage: setup.sh --check|--install'; exit 2; }
case "$1" in --check|--install) action="$1" ;; *) fail 'Unknown action'; exit 2 ;; esac
[[ "$(id -u)" != 0 && -f /etc/arch-release ]] || { fail 'Use a normal Arch/CachyOS user'; exit 1; }
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
src="$repo/trials/sway"
config="${XDG_CONFIG_HOME:-$HOME/.config}"
trial="$config/sway/awtarchy-trial"
shell_dir="$config/quickshell/awtarchy-sway"
portal="$config/xdg-desktop-portal/sway-portals.conf"
for directory in "$config" "$config/sway" "$trial" "$config/quickshell" "$shell_dir" "$config/xdg-desktop-portal"; do
    [[ ! -L "$directory" && ( ! -e "$directory" || -d "$directory" ) ]] || { fail "Unsafe directory: $directory"; exit 1; }
done
for bin in sway swaymsg qs foot python3 jq flock swaylock grim slurp wl-copy; do
    command -v "$bin" >/dev/null 2>&1 || { fail "Missing package tool $bin"; exit 1; }
done
temp="$(mktemp -d)"
trap 'rm -rf -- "$temp"' EXIT
python3 "$src/render-quickshell.py" --source "$repo/config/quickshell/awtarchy" --dest "$temp/awtarchy-sway" --bridge-dir "$src" || { fail 'Quickshell render failed'; exit 1; }
python3 "$src/render-manager.py" --source "$repo/config/hypr/scripts/quickshell.sh" --dest "$temp/quickshell.sh" || { fail 'Quickshell manager render failed'; exit 1; }
bash -n "$temp/quickshell.sh" || { fail 'Rendered manager syntax invalid'; exit 1; }
sway -C -c "$src/config" || { fail 'Sway configuration rejected; nothing changed'; exit 1; }
sources=(config session.sh ipc.sh launcher.sh power.sh clipboard.sh notifications.sh quick-settings.sh application-state.sh cursor-theme.sh default-apps.sh mode-state.sh mode-help.sh lock.sh lock-capture.sh sensitive-capture.sh runtime-rules.sh position.sh capture.sh keyboard-state.py quicksettings.sh quicksettings.py monitor-info.py workspace-state.py theme-apply.sh theme-colors.sh toggle-utility.py diagnose.sh ddc.sh sway-portals.conf)
targets=()
for name in "${sources[@]}"; do
    [[ -f "$src/$name" && ! -L "$src/$name" ]] || { fail "Missing source $name"; exit 1; }
    if [[ "$name" == sway-portals.conf ]]; then target="$portal"; else target="$trial/$name"; fi
    targets+=("$target")
    if [[ -e "$target" || -L "$target" ]]; then
        [[ -f "$target" && ! -L "$target" ]] || { fail "Unsafe destination $target"; exit 1; }
        if [[ "$name" == config ]]; then
            grep -Fqx '# Awtarchy Sway dual-compositor trial. Does not touch Hyprland.' "$target" || { fail 'Unknown existing Sway config'; exit 1; }
        fi
    fi
done
# Stage exact branch-matched controller sources into the isolated Sway tree.
# Never overwrite installed Hyprland helper scripts or unknown Sway files.
ddc_sources=(ddc_brightness.sh hypr-ddc-brightness.sh)
for name in "${ddc_sources[@]}"; do
    source="$repo/config/hypr/scripts/$name"
    target="$trial/$name"
    [[ -f "$source" && ! -L "$source" ]] || { fail "Unsafe brightness source: $source"; exit 1; }
    [[ ! -e "$target" && ! -L "$target" || ( -f "$target" && ! -L "$target" ) ]] || {
        fail "Unsafe brightness destination: $target"; exit 1;
    }
done
for file in "$temp/quickshell.sh" "$temp/awtarchy-sway/"*; do
    if [[ "$file" == "$temp/quickshell.sh" ]]; then target="$trial/quickshell.sh"; else target="$shell_dir/${file##*/}"; fi
    [[ ! -e "$target" && ! -L "$target" || ( -f "$target" && ! -L "$target" ) ]] || { fail "Unsafe generated destination: $target"; exit 1; }
done
if [[ "$action" == --check ]]; then
    printf 'PASS: Sway config accepted, isolated UI generated, paths checked\n'
    exit 0
fi
for directory in "$config" "$config/sway" "$trial" "$config/quickshell" "$shell_dir" "$config/xdg-desktop-portal"; do
    [[ -d "$directory" ]] || mkdir -m 0700 -- "$directory"
done
for i in "${!sources[@]}"; do
    name="${sources[$i]}"
    target="${targets[$i]}"
    [[ ! -e "$target" ]] || continue
    case "$name" in *.sh) perms=0755 ;; *) perms=0644 ;; esac
    install -m "$perms" -- "$src/$name" "$target"
done
for name in "${ddc_sources[@]}"; do
    [[ -e "$trial/$name" ]] || install -m 0755 -- "$repo/config/hypr/scripts/$name" "$trial/$name"
done
[[ -e "$trial/quickshell.sh" ]] || install -m 0755 -- "$temp/quickshell.sh" "$trial/quickshell.sh"
for file in "$temp/awtarchy-sway/"*; do
    target="$shell_dir/${file##*/}"
    [[ -e "$target" ]] || install -m 0644 -- "$file" "$target"
done
printf 'PASS: Sway trial staged, existing compositor and personal files preserved\n'
