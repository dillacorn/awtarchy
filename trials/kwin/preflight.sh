#!/usr/bin/env bash
# Read-only KWin standalone feasibility survey for Awtarchy.
# Never installs, starts, removes or rewrites configuration.
set -euo pipefail

main() {
    if [[ ${EUID} -eq 0 ]]; then
        printf 'ERROR: Run as a normal user (no sudo).\n' >&2
        return 1
    fi

    if ! command -v pacman >/dev/null 2>&1; then
        printf 'ERROR: pacman is required for an Arch/CachyOS survey.\n' >&2
        return 1
    fi

    printf 'Awtarchy KWin survey (read only)\n'
    printf 'Desktop session: %s\n' "${XDG_CURRENT_DESKTOP:-unset}"
    printf 'Session type: %s\n' "${XDG_SESSION_TYPE:-unset}"
    printf '\nInstalled packages:\n'

    local pkg state
    for pkg in kwin xorg-xwayland libkscreen kglobalacceld plasma-workspace plasma-meta \
               quickshell foot xdg-desktop-portal-kde xdg-desktop-portal-hyprland \
               xdg-desktop-portal-wlr xdg-desktop-portal-gtk hyprland sway; do
        if pacman -Qq -- "$pkg" >/dev/null 2>&1; then
            state=installed
        else
            state=absent
        fi
        printf '  %-34s %s\n' "$pkg" "$state"
    done

    printf '\nOfficial repository metadata:\n'
    for pkg in kwin xorg-xwayland; do
        if pacman -Si -- "$pkg" >/dev/null 2>&1; then
            printf '  %s: available in configured sync databases\n' "$pkg"
        else
            printf '  %s: unavailable or sync database stale\n' "$pkg"
        fi
    done

    printf '\nExecutables:\n'
    for pkg in kwin_wayland kwin_wayland_wrapper kscreen-doctor quickshell qs foot; do
        if command -v "$pkg" >/dev/null 2>&1; then
            printf '  %-24s present\n' "$pkg"
        else
            printf '  %-24s absent\n' "$pkg"
        fi
    done

    printf '\nPortal preference files (presence only):\n'
    local p
    for p in \
        "${XDG_CONFIG_HOME:-$HOME/.config}/xdg-desktop-portal/hyprland-portals.conf" \
        "${XDG_CONFIG_HOME:-$HOME/.config}/xdg-desktop-portal/sway-portals.conf" \
        "${XDG_CONFIG_HOME:-$HOME/.config}/xdg-desktop-portal/awtarchy-kwin-portals.conf"; do
        if [[ -L "$p" ]]; then
            printf '  %s: symlink (not followed)\n' "$p"
        elif [[ -f "$p" ]]; then
            printf '  %s: present\n' "$p"
        else
            printf '  %s: absent\n' "$p"
        fi
    done

    printf '\nNo writes performed. Awtarchy KWin integration is not yet installable.\n'
}

main "$@"
