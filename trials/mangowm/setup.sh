#!/usr/bin/env bash
# Explicit, conflict-safe trial staging; never removes Hyprland or packages.
set -euo pipefail
mode="${1:-}"
[[ "$#" -eq 1 && ( "$mode" == --check || "$mode" == --install ) ]] || {
    printf 'Usage: bash trials/mangowm/setup.sh --check|--install\n' >&2; exit 2;
}
[[ "$(id -u)" -ne 0 ]] || { printf 'Do not run as root\n' >&2; exit 1; }
src="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
home="${XDG_CONFIG_HOME:-$HOME/.config}"
mango_dir="$home/mango"
trial_dir="$mango_dir/awtarchy-trial"
portal_dir="$home/xdg-desktop-portal"
[[ ! -L "$mango_dir" && ! -L "$portal_dir" && ! -L "$trial_dir" ]] || {
    printf 'Refusing linked config directory\n' >&2; exit 1;
}
sources=(config.conf session.sh power.sh capture.sh waybar.json waybar.css mango-portals.conf)
targets=("$mango_dir/config.conf" "$trial_dir/session.sh" "$trial_dir/power.sh"
    "$trial_dir/capture.sh" "$trial_dir/waybar.json" "$trial_dir/waybar.css"
    "$portal_dir/mango-portals.conf")
# Check ALL conflicts before first write.
for i in "${!sources[@]}"; do
    a="$src/${sources[$i]}"
    b="${targets[$i]}"
    [[ -f "$a" && ! -L "$a" ]] || { printf 'Missing/linked source %s\n' "$a" >&2; exit 1; }
    if [[ -e "$b" || -L "$b" ]]; then
        [[ ! -L "$b" && -f "$b" ]] && cmp -s "$a" "$b" || {
            printf 'Refusing to overwrite existing config: %s\n' "$b" >&2; exit 1;
        }
    fi
done
required=(mango mmsg waybar fuzzel mako swaybg swayidle swaylock grim slurp)
missing=()
for binary in "${required[@]}"; do
    command -v "$binary" >/dev/null 2>&1 || missing+=("$binary")
done
if (( ${#missing[@]} > 0 )); then
    printf 'Missing trial programs: %s\n' "${missing[*]}" >&2; exit 1;
fi
mango -c "$src/config.conf" -p || { printf 'Mango rejected config; nothing installed\n' >&2; exit 1; }
if [[ "$mode" == --check ]]; then
    printf 'PASS: prerequisites, destination conflicts, mango -p\n'
    exit 0
fi
install -d -m 0700 -- "$mango_dir" "$trial_dir" "$portal_dir"
for i in "${!sources[@]}"; do
    b="${targets[$i]}"
    if [[ ! -e "$b" ]]; then
        install -m 0644 -- "$src/${sources[$i]}" "$b"
        printf 'Installed: %s\n' "$b"
    fi
done
printf 'Mango trial staged. Select Mango at login; Hyprland is unchanged.\n'
