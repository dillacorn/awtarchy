#!/usr/bin/env bash
# Refresh ONLY the recognized stock root-owned Sway Ly session launcher.
# Never overwrite custom session entrypoints or touch Hyprland's launcher.
set -euo pipefail

[[ $# -eq 2 ]] || {
    printf 'Usage: session-wrapper-update.sh plan|apply /absolute/checkout\n' >&2
    exit 2
}
mode="$1"
repo="$2"
[[ "$mode" == plan || "$mode" == apply ]] || {
    printf 'Expected plan or apply\n' >&2
    exit 2
}
[[ "$repo" == /* && -d "$repo/.git" && ! -L "$repo" ]] || {
    printf 'Unsafe Sway trial checkout\n' >&2
    exit 1
}
[[ "$(git -C "$repo" branch --show-current)" == SwayWM_Migration_Trial_Investigation ]] || {
    printf 'Not the registered Sway trial branch\n' >&2
    exit 1
}

source="$repo/trials/sway/session-launch.sh"
target=/usr/local/bin/awtarchy-sway-session
[[ -f "$source" && ! -L "$source" ]] && bash -n "$source" || {
    printf 'Invalid Sway session launcher source\n' >&2
    exit 1
}
[[ -d /usr/local/bin && ! -L /usr/local/bin ]] || {
    printf 'Unsafe Sway session launcher directory\n' >&2
    exit 1
}
if [[ ! -f "$target" || -L "$target" ||
      "$(stat -c %u -- "$target" 2>/dev/null)" != 0 ]]; then
    printf 'PRESERVE: Sway Ly launcher missing, linked or not root-owned\n'
    exit 0
fi
if pacman -Qo -- "$target" >/dev/null 2>&1; then
    printf 'PRESERVE: Sway Ly launcher is package-managed\n'
    exit 0
fi
if cmp -s -- "$source" "$target"; then
    printf 'Sway Ly session launcher is current\n'
    exit 0
fi
# These are the exact Git blob hashes of original unmodified Awtarchy Sway
# launchers. Never infer ownership from the filename alone.
stock_hash="$(git hash-object --no-filters -- "$target")"
case "$stock_hash" in
    77c9d91310dc7b1b70989ac620ab2a90b04a9427|9c5e76d6156fec32f311eb218b265adb664cfb6d)
        ;;
    *)
        printf 'PRESERVE: Sway Ly launcher was customized; no root file modified\n'
        exit 0
        ;;
esac

if [[ "$mode" == plan ]]; then
    printf 'WOULD UPDATE: root-owned Sway Ly launcher (recognized stock version; backup)\n'
    exit 0
fi

# Apply is called only after interactive update-sway authorization.
# Re-check source/target identity before the privileged copy.
[[ "$(git hash-object --no-filters -- "$target")" == "$stock_hash" ]] || {
    printf 'Sway Ly launcher changed during update; refusing\n' >&2
    exit 1
}
backup="$target.backup-$(date -u +%Y%m%d-%H%M%S-%N)"
[[ ! -e "$backup" && ! -L "$backup" ]] || {
    printf 'Sway Ly launcher backup already exists; refusing\n' >&2
    exit 1
}
sudo install -m 0644 -- "$target" "$backup"
sudo install -m 0755 -- "$source" "$target"
if ! cmp -s -- "$source" "$target"; then
    printf 'Sway Ly launcher verification failed; backup: %s\n' "$backup" >&2
    exit 1
fi
printf 'UPDATED: Sway Ly session launcher. New sessions inherit Qt5 and Qt6 themes; current Sway session stays running.\n'
