#!/usr/bin/env bash
# Isolated Umbriel trial. Never updates another compositor or the release state.
set -euo pipefail

[[ $# -eq 2 ]] || { printf 'Usage: manage.sh install-umbriel|update-umbriel preview|apply\n' >&2; false; }
operation="$1"
mode="$2"
[[ "$operation" == install-umbriel || "$operation" == update-umbriel ]] || {
    printf 'Unsupported Umbriel trial action\n' >&2; false;
}
[[ "$mode" == preview || "$mode" == apply ]] || {
    printf 'Invalid Umbriel trial mode\n' >&2; false;
}
[[ "$(id -u)" -ne 0 ]] || { printf 'Use a normal user, not root\n' >&2; false; }
[[ -f /etc/arch-release ]] || { printf 'Arch/CachyOS host required\n' >&2; false; }
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
[[ -d "$repo/.git" && ! -L "$repo" &&
   "$(git -C "$repo" branch --show-current)" == feature/umbriel-quickshell-trial &&
   "$(git -C "$repo" remote get-url origin)" == https://github.com/dillacorn/awtarchy.git &&
   -z "$(git -C "$repo" status --porcelain --untracked-files=no)" ]] || {
    printf 'Expected clean, exact Awtarchy Umbriel trial checkout\n' >&2; false;
}
[[ "${XDG_CONFIG_HOME:-$HOME/.config}" == "$HOME/.config" ]] || {
    printf 'Custom XDG_CONFIG_HOME is not yet supported by this isolated trial\n' >&2; false;
}
for command in pacman python3 git; do
    command -v "$command" >/dev/null || { printf 'Missing %s\n' "$command" >&2; false; }
done
printf '\nUmbriel trial: %s\n' "$operation"
printf 'Never removes or overwrites Hyprland, Sway, Mango or KWin settings.\n'
printf 'No compositor packages or login sessions will be uninstalled.\n'
if pacman -Qq umbriel-git >/dev/null 2>&1; then
    printf 'Umbriel: umbriel-git installed\n'
elif pacman -Qq umbriel >/dev/null 2>&1; then
    printf 'Umbriel: existing umbriel package will be preserved\n'
else
    printf 'Umbriel: requires AUR package umbriel-git (yay)\n'
fi
python3 "$repo/trials/umbriel/sync.py" preview --repo "$repo"
if [[ "$mode" == preview ]]; then
    printf 'Preview only. No packages, session entries or configs changed.\n'
    exit 0
fi
[[ -t 0 && -t 1 && -r /dev/tty && -w /dev/tty ]] || {
    printf 'Umbriel installation requires an interactive terminal\n' >&2; false;
}
if [[ "${AWTARCHY_COMPOSITOR_MENU_APPROVED:-}" != "$operation" ]]; then
    printf 'Type %s to authorize installation: ' "$operation" >/dev/tty
    IFS= read -r approval </dev/tty || :
    [[ "$approval" == "$operation" ]] || { printf 'Canceled\n'; false; }
fi
# This build is evolving. Use the exact existing AUR package without
# automatically patching its PKGBUILD, switching GPU drivers, or reinstalling
# any package that already provides Umbriel.
if ! pacman -Qq umbriel-git >/dev/null 2>&1 &&
   ! pacman -Qq umbriel >/dev/null 2>&1; then
    command -v yay >/dev/null 2>&1 || {
        printf 'yay required for umbriel-git AUR install; no config changes made.\n' >&2
        false
    }
    yay -S --needed umbriel-git
    pacman -Qq umbriel-git >/dev/null 2>&1 || {
        printf 'umbriel-git installation not verified.\n' >&2
        false
    }
fi
for app in quickshell foot fuzzel jq python wl-clipboard cliphist xdg-desktop-portal-gtk; do
    if ! pacman -Qq "$app" >/dev/null 2>&1; then
        sudo pacman -S --needed -- "$app"
    fi
done
for bin in umbriel start-umbriel qs; do
    command -v "$bin" >/dev/null 2>&1 || {
        printf 'Umbriel package lacks required command: %s\n' "$bin" >&2
        false
    }
done
entry=/usr/share/wayland-sessions/umbriel.desktop
[[ -f "$entry" && ! -L "$entry" ]] &&
    pacman -Qo -- "$entry" >/dev/null 2>&1 || {
        printf 'Umbriel package-owned Ly entry missing. No duplicate will be installed.\n' >&2
        false
    }
# Validate the exact TOML include under a private XDG_CONFIG_HOME first,
# rather than applying config and hoping Umbriel will parse it at login.
check="$(mktemp -d)"
trap 'rm -rf -- "$check"' EXIT
mkdir -p "$check/umbriel/awtarchy-trial"
cp -- "$repo/trials/umbriel/native-config.toml" "$check/umbriel/config.toml"
cp -- "$repo/trials/umbriel/config.toml" "$check/umbriel/awtarchy-trial/config.toml"
if ! XDG_CONFIG_HOME="$check" umbriel config validate; then
    printf 'Umbriel rejected the trial config. No user config applied.\n' >&2
    false
fi
python3 "$repo/trials/umbriel/sync.py" apply --repo "$repo"
printf '\nUmbriel trial staged. Next login: select package-owned Umbriel in Ly.\n'
printf 'Existing compositor configs and sessions remain installed.\n'
printf 'Reboot is recommended before first login; no automatic restart.\n'
