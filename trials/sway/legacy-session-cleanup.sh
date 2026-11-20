#!/usr/bin/env bash
# Remove only Awtarchy's exact legacy duplicate Sway Ly entry.
# Keep the package-owned sway.desktop and all unrecognized/custom entries.
set -euo pipefail
[[ $# -eq 2 && ( "$1" == plan || "$1" == apply ) ]] || {
    printf 'Usage: legacy-session-cleanup.sh plan|apply /absolute/checkout\n' >&2
    exit 2
}
mode="$1"
repo="$2"
source_file="$repo/trials/sway/sway.desktop"
legacy=/usr/share/wayland-sessions/awtarchy-sway-trial.desktop
native=/usr/share/wayland-sessions/sway.desktop
[[ "$repo" == /* && -d "$repo" && ! -L "$repo" &&
   -f "$source_file" && ! -L "$source_file" ]] || {
    printf 'Invalid Awtarchy Sway session source\n' >&2
    exit 1
}
[[ -f "$native" && ! -L "$native" ]] || {
    printf 'Missing package-provided Sway session; refusing migration\n' >&2
    exit 1
}
if [[ ! -e "$legacy" && ! -L "$legacy" ]]; then
    printf 'Sway uses one native Ly entry; no duplicate to remove.\n'
    exit 0
fi
if [[ ! -f "$legacy" || -L "$legacy" ]] ||
   pacman -Qo -- "$legacy" >/dev/null 2>&1 ||
   ! cmp -s -- "$source_file" "$legacy"; then
    printf 'PRESERVE: unrecognized/modified Sway session entry: %s\n' "$legacy" >&2
    printf 'Cannot promise a single Ly entry until this custom file is reviewed.\n' >&2
    exit 1
fi
if [[ "$mode" == plan ]]; then
    printf 'WOULD REMOVE: exact redundant Awtarchy Sway entry; native Sway session is retained.\n'
    exit 0
fi
# Verify exact identity again before removing the legacy file.
[[ -f "$legacy" && ! -L "$legacy" ]] &&
    ! pacman -Qo -- "$legacy" >/dev/null 2>&1 &&
    cmp -s -- "$source_file" "$legacy" || {
        printf 'Sway session entry changed during migration; refusing.\n' >&2
        exit 1
    }
sudo rm -- "$legacy"
[[ ! -e "$legacy" && ! -L "$legacy" ]] || {
    printf 'Legacy Sway entry still present after cleanup.\n' >&2
    exit 1
}
printf 'Removed exact duplicate entry. Ly will show the package-provided Sway session.\n'
