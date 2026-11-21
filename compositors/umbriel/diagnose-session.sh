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

printf '\n=== AWTARCHY LY SESSION DIRECTORY ===\n'
dir=/etc/ly/awtarchy-wayland-sessions
if [[ -d "$dir" && ! -L "$dir" ]]; then
    stat -c 'Owner UID: %u | Mode: %a | Path: %n' -- "$dir"
    for desktop in "$dir"/*.desktop; do
        [[ -e "$desktop" || -L "$desktop" ]] || continue
        printf '\n%s\n' "$desktop"
        if [[ -L "$desktop" ]]; then
            printf 'Linked to: %s\n' "$(readlink -- "$desktop")"
        fi
        if [[ -f "$desktop" ]]; then
            grep -E '^(Name|Exec|DesktopNames)=' -- "$desktop" || true
        fi
    done
else
    printf 'Missing or unsafe: %s\n' "$dir"
fi

printf '\n=== LY SERVICE STATE ===\n'
if command -v systemctl >/dev/null 2>&1; then
    systemctl show ly.service --no-pager -p ActiveState -p ActiveEnterTimestamp 2>&1 || true
fi

printf '\n=== CONCLUSION BOUNDARY ===\n'
printf 'Ly loads session directories when its interface initializes.\n'
printf 'This report does not prove the running Ly process has re-scanned them.\n'
printf 'Never restart Ly from an active graphical session just to refresh its list.\n'

printf '\n=== INSTALLED UMBRIEL PROFILE ===\n'
native="$HOME/.config/umbriel/config.toml"
managed="$HOME/.config/umbriel/awtarchy"
shell_dir="$HOME/.config/quickshell/awtarchy-umbriel"
for file in "$native" "$managed/config.toml" "$managed/session.sh" \
            "$managed/quickshell.sh" "$managed/workspace-events.py" \
            "$shell_dir/shell.qml" "$shell_dir/UmbrielBridge.qml"; do
    if [[ -f "$file" && ! -L "$file" ]]; then
        printf 'PRESENT: %s\n' "$file"
    else
        printf 'MISSING/UNSAFE: %s\n' "$file"
    fi
done
if [[ -f "$native" && ! -L "$native" ]]; then
    if grep -Fq '"awtarchy/config.toml"' "$native"; then
        printf 'Awtarchy native include: present\n'
    else
        printf 'Awtarchy native include: MISSING (defaults may load instead)\n'
    fi
fi
if [[ -f "$shell_dir/UmbrielBridge.qml" && ! -L "$shell_dir/UmbrielBridge.qml" ]]; then
    if grep -Fq '/umbriel/awtarchy-trial/' "$shell_dir/UmbrielBridge.qml"; then
        printf 'Umbriel Quickshell bridge: OBSOLETE trial helper path detected\n'
    fi
fi
printf '\n=== EFFECTIVE CONFIG VALIDATION (READ ONLY) ===\n'
if command -v umbriel >/dev/null 2>&1; then
    XDG_CONFIG_HOME="$HOME/.config" umbriel config validate 2>&1 || true
else
    printf 'Umbriel binary is not available\n'
fi
printf '\n=== MOST RECENT UMBRIEL / QUICKSHELL LOGS ===\n'
for log_file in "${XDG_CACHE_HOME:-$HOME/.cache}/umbriel/umbriel.log" \
                "${XDG_CACHE_HOME:-$HOME/.cache}/awtarchy/quickshell-umbriel.log"; do
    if [[ -f "$log_file" && ! -L "$log_file" ]]; then
        printf '\n%s\n' "$log_file"
        tail -n 35 -- "$log_file" || true
    else
        printf 'MISSING: %s\n' "$log_file"
    fi
done
printf '\nLog entries may contain application names or personal paths; review before sharing.\n'
