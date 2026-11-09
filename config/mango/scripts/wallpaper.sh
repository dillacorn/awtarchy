#!/usr/bin/env bash
# Restore AwtWall's saved per-output images with a Mango-compatible wallpaper
# backend. Do not call AwtWall --restore: it may launch saved Hyprpaper.
# Leave AwtWall's state and all Hyprland services/configuration untouched.
set -euo pipefail

[[ -n "${MANGO_INSTANCE_SIGNATURE:-}" && "${XDG_CURRENT_DESKTOP:-}" == mango &&
   -n "${WAYLAND_DISPLAY:-}" ]] || {
    printf 'Mango wallpaper: compositor session is unavailable\n' >&2
    exit 1
}

config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
saved="$HOME/.config/awtwall/backend_state.tsv"
seed="$HOME/Pictures/wallpapers/awtarchy_geology.png"
provider="" daemon=""

if command -v awww >/dev/null 2>&1 &&
   command -v awww-daemon >/dev/null 2>&1; then
    provider=awww
    daemon=awww-daemon
elif command -v swww >/dev/null 2>&1 &&
     command -v swww-daemon >/dev/null 2>&1; then
    provider=swww
    daemon=swww-daemon
fi

if [[ -z "$provider" ]]; then
    if [[ -f "$seed" ]] && command -v swaybg >/dev/null 2>&1; then
        swaybg -i "$seed" -m fill
    else
        printf 'Mango wallpaper: no native image backend available\n' >&2
        exit 1
    fi
    exit
fi

command -v jq >/dev/null 2>&1 && command -v mmsg >/dev/null 2>&1 || {
    printf 'Mango wallpaper: missing Mango IPC or jq\n' >&2
    exit 1
}

monitors="$(mmsg get all-monitors)" || exit 1
jq -e '.monitors | type == "array" and all(.[]; (.name | type == "string"))' \
   >/dev/null <<<"$monitors" || {
    printf 'Mango wallpaper: invalid output inventory\n' >&2
    exit 1
}
mapfile -t connected < <(jq -r '.monitors[].name' <<<"$monitors")
(( ${#connected[@]} > 0 )) || {
    printf 'Mango wallpaper: no active outputs\n' >&2
    exit 1
}

has_output() {
    local item
    for item in "${connected[@]}"; do
        [[ "$item" == "$1" ]] && return 0
    done
    return 1
}

if ! timeout 2 "$provider" query >/dev/null 2>&1; then
    "$daemon" >/dev/null 2>&1 &
    for _ in {1..16}; do
        if timeout 2 "$provider" query >/dev/null 2>&1; then
            break
        fi
        sleep 0.15
    done
fi
timeout 2 "$provider" query >/dev/null 2>&1 || {
    printf 'Mango wallpaper: image daemon did not start\n' >&2
    exit 1
}

apply_image() {
    local display="$1" image="$2"
    [[ "$display" =~ ^[A-Za-z0-9_.-]+$ && "$image" == /* &&
       -f "$image" ]] || return 1
    has_output "$display" || return 1
    "$provider" img --outputs "$display" --resize crop \
        --transition-type none "$image"
}

restored=0
if [[ -f "$saved" && ! -L "$saved" && -r "$saved" ]]; then
    while IFS=$'\t' read -r output field image || [[ -n "$output" ]]; do
        [[ -n "$output" && "$output" != backend ]] || continue
        if [[ -z "$image" ]]; then
            image="$field"  # Backwards-compatible two-column state.
        fi
        [[ -n "$image" ]] || continue
        if apply_image "$output" "$image"; then
            (( restored += 1 ))
        fi
    done <"$saved"
fi

if (( restored == 0 )); then
    [[ -f "$seed" ]] || {
        printf 'Mango wallpaper: no valid saved or seed image exists\n' >&2
        exit 1
    }
    for output in "${connected[@]}"; do
        apply_image "$output" "$seed" || exit 1
    done
fi
