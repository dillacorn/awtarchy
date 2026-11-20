#!/usr/bin/env bash
# Register Umbriel in Awtarchy's optional Ly session directory without
# modifying the Ly configuration or creating a second compositor entry.
set -euo pipefail

[[ $# -eq 1 && ( "$1" == plan || "$1" == apply ) ]] || {
    printf 'Usage: register-ly-session.sh plan|apply\n' >&2
    exit 2
}
mode="$1"
source=/usr/share/wayland-sessions/umbriel.desktop
config=/etc/ly/config.ini
native=/usr/share/wayland-sessions
custom=/etc/ly/awtarchy-wayland-sessions
target="$custom/umbriel.desktop"

[[ "$(id -u)" -ne 0 ]] || {
    printf 'Run as a normal user; sudo is used only for the approved link.\n' >&2
    exit 1
}
[[ -f "$source" && ! -L "$source" ]] || {
    printf 'Missing or unsafe package Umbriel entry: %s\n' "$source" >&2
    exit 1
}
owner="$(pacman -Qqo -- "$source" 2>/dev/null)" || {
    printf 'Umbriel session entry is not owned by a package; preserving system.\n' >&2
    exit 1
}
[[ "$owner" == umbriel-git || "$owner" == umbriel ]] || {
    printf 'Unexpected Umbriel entry owner: %s\n' "$owner" >&2
    exit 1
}
grep -Fxq 'Name=Umbriel' "$source" &&
grep -Fxq 'Exec=start-umbriel' "$source" || {
    printf 'Unexpected Umbriel desktop entry; review its contents before registration.\n' >&2
    exit 1
}
command -v start-umbriel >/dev/null 2>&1 || {
    printf 'Umbriel package session launcher is missing.\n' >&2
    exit 1
}
[[ -f "$config" && ! -L "$config" ]] || {
    printf 'Ly config not found or is a symlink: %s\n' "$config" >&2
    exit 1
}
# Parse only literal INI values; never evaluate shell/config content.
wayland_dirs="$(awk -F= '
    /^[[:space:]]*waylandsessions[[:space:]]*=/ {
        value=substr($0,index($0,"=")+1)
        sub(/[[:space:]]*[#;].*$/, "", value)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
        print value
    }' "$config")"
[[ -n "$wayland_dirs" && "$wayland_dirs" != *$'\n'* ]] || {
    printf 'Cannot identify one unambiguous Ly Wayland session path.\n' >&2
    exit 1
}
case ":$wayland_dirs:" in
    *":$native:"*)
        printf 'Ly already scans the package session directory; no extra Umbriel entry needed.\n'
        exit 0 ;;
esac
[[ "$wayland_dirs" == "$custom" ]] || {
    printf 'Ly uses another session directory: %s\n' "$wayland_dirs" >&2
    printf 'Preserving the custom configuration; no session link added.\n' >&2
    exit 1
}
[[ -d /etc/ly && ! -L /etc/ly && -d "$custom" && ! -L "$custom" ]] || {
    printf 'Ly custom session directory missing, linked or unsafe: %s\n' "$custom" >&2
    exit 1
}
[[ "$(stat -c %u -- /etc/ly)" == 0 &&
   "$(stat -c %u -- "$custom")" == 0 ]] || {
    printf 'Ly session directory is not root-owned; refusing privileged registration.\n' >&2
    exit 1
}
# Another desktop file may already supply Umbriel under a different name.
# Do not create a duplicate, even when the file is a legitimate symlink.
for file in "$custom"/*.desktop; do
    [[ -e "$file" || -L "$file" ]] || continue
    if [[ "$file" == "$target" ]]; then
        if [[ -L "$file" && "$(readlink -- "$file")" == "$source" ]]; then
            printf 'Ly already has one managed Umbriel entry: %s\n' "$target"
            exit 0
        fi
        printf 'PRESERVE: destination already exists: %s\n' "$file" >&2
        exit 1
    fi
    [[ -f "$file" ]] || continue
    if grep -Eiq '^[[:space:]]*(Name|DesktopNames)[[:space:]]*=[[:space:]]*Umbriel[[:space:]]*$' "$file" ||
       grep -Eq '^[[:space:]]*Exec[[:space:]]*=[[:space:]]*(/usr/bin/)?start-umbriel[[:space:]]*$' "$file"; then
        printf 'PRESERVE: Umbriel appears under another Ly session entry: %s\n' "$file" >&2
        exit 1
    fi
done
if [[ "$mode" == plan ]]; then
    printf 'WOULD LINK: %s -> %s\n' "$target" "$source"
    printf 'No Ly config or other compositor session will be modified.\n'
    exit 0
fi

[[ -t 0 && -t 1 && -r /dev/tty && -w /dev/tty ]] || {
    printf 'Interactive approval required to add Umbriel to Ly.\n' >&2
    exit 1
}
printf 'Type Umbriel to add the single package-owned Ly entry: ' >/dev/tty
IFS= read -r approval </dev/tty || :
[[ "$approval" == Umbriel ]] || {
    printf 'Canceled; nothing changed.\n'
    exit 1
}
# no-clobber link: unexpected concurrent creation must never be overwritten.
sudo ln -s -- "$source" "$target"
[[ -L "$target" && "$(readlink -- "$target")" == "$source" ]] || {
    printf 'Umbriel Ly entry could not be verified after registration.\n' >&2
    exit 1
}
printf 'Registered Umbriel in the existing Ly session directory.\n'
printf 'Reboot before selecting Umbriel; do not restart Ly from your active desktop.\n'
