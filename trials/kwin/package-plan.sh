#!/usr/bin/env bash
# Read-only official pacman transaction preview for isolated KWin testing.
set -euo pipefail

main() {
    [[ ${EUID} -ne 0 ]] || {
        printf 'Run the preview as a normal user, without sudo.\n' >&2
        return 1
    }
    command -v pacman >/dev/null 2>&1 || {
        printf 'pacman is unavailable.\n' >&2
        return 1
    }
    local pkg
    for pkg in kwin xorg-xwayland python-dbus-next quickshell foot fuzzel; do
        if ! pacman -Si -- "$pkg" >/dev/null 2>&1; then
            printf 'Missing official package metadata for %s; refresh the system package database normally.\n' "$pkg" >&2
            return 1
        fi
    done

    local planned=''
    planned="$(pacman -Sp --needed --print-format '%n' -- kwin xorg-xwayland python-dbus-next quickshell foot fuzzel)" || {
        printf 'Pacman could not resolve the complete KWin transaction.\n' >&2
        return 1
    }
    printf 'Awtarchy KWin experimental package preview (read only)\n'
    printf 'Direct requests: kwin, xorg-xwayland, python-dbus-next, quickshell, foot, fuzzel\n'
    printf 'Resolved installation targets from the current local pacman database:\n'
    local count=0
    while IFS= read -r pkg; do
        [[ -n "$pkg" ]] || continue
        [[ "$pkg" =~ ^[a-zA-Z0-9@._+-]+$ ]] || {
            printf 'Unexpected transaction target: %q\n' "$pkg" >&2
            return 1
        }
        case "$pkg" in
            plasma-workspace|plasma-meta|plasma-desktop)
                printf 'Full Plasma package unexpectedly required: %s; refusing this plan.\n' "$pkg" >&2
                return 1 ;;
        esac
        printf '  %s\n' "$pkg"
        count=$((count+1))
    done <<< "$planned"
    if (( count == 0 )); then
        printf 'No installation targets; requested packages are already installed.\n'
    else
        printf 'Number of package targets: %s\n' "$count"
    fi
    printf 'Nothing was installed or removed; no pacman database was updated.\n'
}

main "$@"
