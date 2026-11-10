#!/usr/bin/env bash
# Package/stage trial without changing Hyprland, GPU drivers, or managed state.
set -euo pipefail
fail() { printf 'Jay trial: %s\n' "$*" >&2; exit 1; }
[[ $# -eq 1 ]] || fail 'Usage: setup.sh --packages|--check|--install'
case "$1" in --packages|--check|--install) mode="$1" ;; *) fail 'Unknown action' ;; esac
[[ "$(id -u)" -ne 0 ]] || fail 'Do not run as root'
[[ -f /etc/arch-release ]] || fail 'Arch/CachyOS required'
src="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
home="${XDG_CONFIG_HOME:-$HOME/.config}"
jay="$home/jay"
trial="$jay/awtarchy-trial"
portal="$home/xdg-desktop-portal"
desktop="/usr/share/wayland-sessions/awtarchy-jay-trial.desktop"

if [[ "$mode" == --packages ]]; then
    command -v aur-scan >/dev/null 2>&1 || fail 'aur-scan is required'
    command -v sudo >/dev/null 2>&1 || fail 'sudo is required'
    aur-scan install jay --noconfirm
    sudo pacman -S --needed --noconfirm foot fuzzel mako swaylock grim slurp wl-clipboard cliphist xdg-desktop-portal-gtk libnotify jq python pipewire
    printf 'Packages installed; run --check next.\n'
    exit 0
fi

for d in "$home" "$jay" "$trial" "$portal"; do
    [[ ! -L "$d" && ( ! -e "$d" || -d "$d" ) ]] || fail "Unsafe destination directory: $d"
done
sources=(config.toml session.sh capture.sh jay-portals.conf)
targets=("$jay/config.toml" "$trial/session.sh" "$trial/capture.sh" "$portal/jay-portals.conf")
for i in "${!sources[@]}"; do
    a="$src/${sources[$i]}"
    b="${targets[$i]}"
    [[ -f "$a" && ! -L "$a" ]] || fail "Missing or linked trial source: $a"
    if [[ -e "$b" || -L "$b" ]]; then
        [[ -f "$b" && ! -L "$b" ]] && cmp -s "$a" "$b" || fail "Config conflict (no overwrite): $b"
    fi
done
[[ -f "$src/jay.desktop" && ! -L "$src/jay.desktop" ]] || fail 'Missing session descriptor'
if [[ -e "$desktop" || -L "$desktop" ]]; then
    [[ -f "$desktop" && ! -L "$desktop" ]] && cmp -s "$src/jay.desktop" "$desktop" || fail "Session entry conflict: $desktop"
fi
for cmd in jay foot fuzzel mako swaylock grim slurp wl-copy python3; do
    command -v "$cmd" >/dev/null 2>&1 || fail "Missing $cmd; run --packages"
done
python3 - "$src/config.toml" <<'PY'
import pathlib, sys, tomllib
d = tomllib.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
assert d['tearing']['mode'] == 'variant2'
assert d['shortcuts']['alt-1']['name'] == '1'
assert d['on-idle']['exec']['privileged'] is True
print('PASS: shipped Jay TOML parses and contains required controls')
PY
if [[ "$mode" == --check ]]; then
    printf 'PASS: dependencies, config conflicts, TOML. No changes made.\n'
    exit 0
fi
command -v sudo >/dev/null 2>&1 || fail 'sudo required for Ly Wayland session entry'
if [[ ! -e "$desktop" ]]; then sudo -v; fi
for d in "$home" "$jay" "$trial" "$portal"; do
    if [[ ! -d "$d" ]]; then mkdir -m 0700 -- "$d"; fi
done
for i in "${!sources[@]}"; do
    b="${targets[$i]}"
    if [[ ! -e "$b" ]]; then
        install -m 0644 -- "$src/${sources[$i]}" "$b"
        printf 'Installed: %s\n' "$b"
    fi
done
if [[ ! -e "$desktop" ]]; then
    sudo install -m 0644 -- "$src/jay.desktop" "$desktop"
    printf 'Installed Ly entry: %s\n' "$desktop"
fi
printf 'Jay trial staged. Reboot and select Jay (Awtarchy Trial) in Ly.\n'
