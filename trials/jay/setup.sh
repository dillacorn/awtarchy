#!/usr/bin/env bash
# Isolated Jay session; deliberate staging with preflight of every destination.
set -euo pipefail
fail() { printf 'Jay trial: %s\n' "$*" >&2; exit 1; }
[[ $# -eq 1 ]] || fail 'Usage: setup.sh --packages|--check|--install'
case "$1" in --packages|--check|--install) mode="$1" ;; *) fail 'Unknown action' ;; esac
[[ "$(id -u)" -ne 0 ]] || fail 'Do not run as root'
[[ -f /etc/arch-release ]] || fail 'Arch/CachyOS required'
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
src="$root/trials/jay"
home="${XDG_CONFIG_HOME:-$HOME/.config}"
jay="$home/jay"
trial="$jay/awtarchy-trial"
shell_dir="$home/quickshell/awtarchy-jay"
portal="$home/xdg-desktop-portal"
desktop="/usr/share/wayland-sessions/awtarchy-jay-trial.desktop"
system_portal="/usr/share/xdg-desktop-portal/portals/jay.portal"

if [[ "$mode" == --packages ]]; then
    command -v aur-scan >/dev/null 2>&1 || fail 'aur-scan is required'
    command -v sudo >/dev/null 2>&1 || fail 'sudo is required'
    aur-scan install jay --noconfirm
    sudo pacman -S --needed --noconfirm quickshell qt6-multimedia qt6-multimedia-ffmpeg foot fuzzel mako swaylock grim slurp wl-clipboard cliphist xdg-desktop-portal-gtk libnotify jq python pipewire lxqt-policykit playerctl
    printf 'Packages installed; run --check next.\n'
    exit 0
fi

for d in "$home" "$jay" "$trial" "$portal" "$home/quickshell"; do
    [[ ! -L "$d" && ( ! -e "$d" || -d "$d" ) ]] || fail "Unsafe destination directory: $d"
done
for bin in jay qs foot fuzzel mako swaylock grim slurp wl-copy python3 jq flock; do
    command -v "$bin" >/dev/null 2>&1 || fail "Missing $bin (run --packages)"
done

# Render both code paths before touching any installed files.
temp="$(mktemp -d)"
trap 'rm -rf -- "$temp"' EXIT
python3 "$src/render-quickshell.py" --source "$root/config/quickshell/awtarchy" \
    --dest "$temp/awtarchy-jay" --bridge-dir "$src" || fail 'Quickshell QML bridge generation failed'
python3 "$src/render-manager.py" --source "$root/config/hypr/scripts/quickshell.sh" \
    --dest "$temp/quickshell.sh" || fail 'Quickshell manager port failed'
bash -n "$temp/quickshell.sh"

sources=(config.toml session.sh capture.sh jay-portals.conf monitor-info.py application-state.sh cursor-theme.sh position.sh runtime-rules.sh quicksettings.sh quicksettings.py keyboard-state.py mode-state.sh lock.sh lock-capture.sh ipc.sh launcher.sh power.sh clipboard.sh notifications.sh quick-settings.sh)
targets=("$jay/config.toml" "$trial/session.sh" "$trial/capture.sh" "$portal/jay-portals.conf" "$trial/monitor-info.py" "$trial/application-state.sh" "$trial/cursor-theme.sh" "$trial/position.sh" "$trial/runtime-rules.sh" "$trial/quicksettings.sh" "$trial/quicksettings.py" "$trial/keyboard-state.py" "$trial/mode-state.sh" "$trial/lock.sh" "$trial/lock-capture.sh" "$trial/ipc.sh" "$trial/launcher.sh" "$trial/power.sh" "$trial/clipboard.sh" "$trial/notifications.sh" "$trial/quick-settings.sh")
for i in "${!sources[@]}"; do
    a="$src/${sources[$i]}" b="${targets[$i]}"
    [[ -f "$a" && ! -L "$a" ]] || fail "Missing/linked source: $a"
    if [[ -e "$b" || -L "$b" ]]; then
        [[ -f "$b" && ! -L "$b" ]] && cmp -s "$a" "$b" || fail "Configuration conflict (not overwritten): $b"
    fi
done
manager_target="$trial/quickshell.sh"
if [[ -e "$manager_target" || -L "$manager_target" ]]; then
    [[ -f "$manager_target" && ! -L "$manager_target" ]] &&
        cmp -s "$temp/quickshell.sh" "$manager_target" || fail 'Jay Quickshell manager conflict'
fi
if [[ -e "$shell_dir" || -L "$shell_dir" ]]; then
    [[ -d "$shell_dir" && ! -L "$shell_dir" ]] || fail 'Jay Quickshell profile path conflict'
    for file in "$temp/awtarchy-jay/"*; do
        dest="$shell_dir/${file##*/}"
        [[ -f "$dest" && ! -L "$dest" ]] && cmp -s "$file" "$dest" ||
            fail "Jay Quickshell UI conflict or missing file: $dest"
    done
    [[ "$(find "$shell_dir" -mindepth 1 -maxdepth 1 -type f | wc -l)" -eq "$(find "$temp/awtarchy-jay" -mindepth 1 -maxdepth 1 -type f | wc -l)" ]] || fail 'Existing Jay Quickshell profile has extra files'
fi
for pair in "$src/jay.desktop:$desktop" "$src/jay.portal:$system_portal"; do
    a="${pair%%:*}" b="${pair#*:}"
    [[ -f "$a" && ! -L "$a" ]] || fail "Missing source: $a"
    if [[ -e "$b" || -L "$b" ]]; then
        [[ -f "$b" && ! -L "$b" ]] || fail "Unsafe system target: $b"
        if [[ "$b" == "$desktop" ]]; then
            cmp -s "$a" "$b" || fail 'Ly session entry conflict'
        fi
        # A package-installed portal descriptor may use equivalent formatting;
        # do not overwrite it or require it to match this fallback byte-for-byte.
    fi
done
python3 - "$src/config.toml" <<'PY'
import sys, tomllib
from pathlib import Path
data = tomllib.loads(Path(sys.argv[1]).read_text())
assert data['tearing']['mode'] == 'variant2'
assert data['vrr']['mode'] == 'variant1'
assert data['clients'][0]['match']['tag'] == 'awtarchy-jay-shell'
assert not data['show-bar']
assert data['on-idle']['exec']['privileged'] is True
PY
if [[ "$mode" == --check ]]; then
    printf 'PASS: Jay trial static stage, generated Quickshell, config collisions, privileges\n'
    exit 0
fi
command -v sudo >/dev/null 2>&1 || fail 'sudo required for Ly and portal fallback'
if [[ ! -e "$desktop" || ! -e "$system_portal" ]]; then sudo -v; fi
for d in "$home" "$jay" "$trial" "$portal" "$home/quickshell"; do
    [[ -d "$d" ]] || mkdir -m 0700 -- "$d"
done
for i in "${!sources[@]}"; do
    [[ -e "${targets[$i]}" ]] || {
        case "${sources[$i]}" in
            *.sh) file_mode=0755 ;;
            *) file_mode=0644 ;;
        esac
        install -m "$file_mode" -- "$src/${sources[$i]}" "${targets[$i]}"
    }
done
[[ -e "$manager_target" ]] || install -m 0755 -- "$temp/quickshell.sh" "$manager_target"
if [[ ! -d "$shell_dir" ]]; then
    mkdir -m 0700 -- "$shell_dir"
    cp -a -- "$temp/awtarchy-jay/." "$shell_dir/"
fi
if [[ ! -e "$desktop" ]]; then sudo install -m 0644 -- "$src/jay.desktop" "$desktop"; fi
if [[ ! -e "$system_portal" ]]; then sudo install -m 0644 -- "$src/jay.portal" "$system_portal"; fi
printf 'Jay staged (NOT full feature parity). Reboot and choose Jay (Awtarchy Trial) in Ly only after reviewing current trial limitations.\n'
