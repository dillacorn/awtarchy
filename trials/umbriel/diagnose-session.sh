#!/usr/bin/env bash
# Read-only Umbriel and Ly session discovery diagnostic.
set -euo pipefail

printf '\n=== PACKAGES ===\n'
for package in umbriel-git umbriel ly; do
    pacman -Q "$package" 2>&1 || true
done

printf '\n=== UMBRIEL COMMANDS ===\n'
for binary in umbriel start-umbriel; do
    command -v "$binary" || true
done

printf '\n=== PACKAGE SESSION FILE ===\n'
entry=/usr/share/wayland-sessions/umbriel.desktop
if [[ -f "$entry" && ! -L "$entry" ]]; then
    stat -c 'Modified: %y\nPath: %n' -- "$entry"
    grep -E '^(Name|Exec|DesktopNames|Type|TryExec|Hidden|NoDisplay)=' -- "$entry" || true
    pacman -Qo -- "$entry" 2>&1 || true
else
    printf 'Missing/unsafe: %s\n' "$entry"
fi

printf '\n=== OTHER UMBRIEL SESSION FILES ===\n'
for dir in /usr/local/share/wayland-sessions "$HOME/.local/share/wayland-sessions"; do
    if [[ -d "$dir" && ! -L "$dir" ]]; then
        find "$dir" -maxdepth 1 -type f -name '*umbriel*.desktop' -print
    fi
done

printf '\n=== LY SESSION SOURCES ===\n'
for config in /etc/ly/config.lua /etc/ly/config.ini; do
    if [[ -f "$config" && ! -L "$config" ]]; then
        printf '%s\n' "$config"
        grep -nE '^[[:space:]]*waylandsessions[[:space:]]*=' -- "$config" || true
    fi
done

printf '\n=== LY SERVICE STATE ===\n'
if command -v systemctl >/dev/null 2>&1; then
    systemctl show ly.service --no-pager -p ActiveState -p ActiveEnterTimestamp 2>&1 || true
fi

printf '\n=== CONCLUSION BOUNDARY ===\n'
printf 'Ly loads session directories when its interface initializes.\n'
printf 'This report does not prove the running Ly process has re-scanned them.\n'
printf 'Never restart Ly from an active graphical session just to refresh its list.\n'
