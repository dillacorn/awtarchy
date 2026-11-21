#!/usr/bin/env bash
# Awtarchy Umbriel compositor manager. Preserve all other desktop configurations.
set -euo pipefail

[[ $# -eq 2 ]] || { printf 'Usage: manage.sh install-umbriel|remove-umbriel preview|apply\n' >&2; false; }
operation="$1"
mode="$2"
[[ "$operation" == install-umbriel || "$operation" == remove-umbriel ]] || {
    printf 'Unsupported Umbriel action\n' >&2; false;
}
[[ "$mode" == preview || "$mode" == apply ]] || {
    printf 'Invalid Umbriel mode\n' >&2; false;
}
[[ "$(id -u)" -ne 0 ]] || { printf 'Use a normal user, not root\n' >&2; false; }
[[ -f /etc/arch-release ]] || { printf 'Arch/CachyOS host required\n' >&2; false; }
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
[[ -f "$repo/compositors/umbriel/sync.py" &&
   -f "$repo/compositors/umbriel/native-config.toml" &&
   -f "$repo/compositors/umbriel/tty-launch.sh" &&
   ! -L "$repo/compositors/umbriel/sync.py" &&
   ! -L "$repo/compositors/umbriel/native-config.toml" &&
   ! -L "$repo/compositors/umbriel/tty-launch.sh" ]] || {
    printf 'Incomplete or unsafe Awtarchy Umbriel release source\n' >&2
    false
}
[[ "${XDG_CONFIG_HOME:-$HOME/.config}" == "$HOME/.config" ]] || {
    printf 'Umbriel setup requires the default XDG_CONFIG_HOME\n' >&2; false;
}
for command in pacman python3 git; do
    command -v "$command" >/dev/null || { printf 'Missing %s\n' "$command" >&2; false; }
done
printf '\nUmbriel: %s\n' "$operation"
printf 'Never removes or overwrites Hyprland, Sway, Mango or KWin settings.\n'
if [[ "$operation" == remove-umbriel ]]; then
    # A compositor removal is an explicitly selected and confirmed action.
    # Keep all personal configs and the separately packaged portal.
    [[ "${XDG_CURRENT_DESKTOP:-}" != Umbriel &&
       "${XDG_CURRENT_DESKTOP:-}" != umbriel ]] || {
        printf 'Cannot remove the running Umbriel session.\n' >&2; false;
    }
    if command -v pgrep >/dev/null &&
       pgrep -u "$(id -u)" -x umbriel >/dev/null 2>&1; then
        printf 'Umbriel is running on another session; aborting removal.\n' >&2
        false
    fi
    if ! pacman -Qq hyprland >/dev/null 2>&1 &&
       ! pacman -Qq sway >/dev/null 2>&1; then
        printf 'Cannot remove the last supported compositor.\n' >&2
        false
    fi
    target=""
    if pacman -Qq umbriel-git >/dev/null 2>&1; then
        target=umbriel-git
    elif pacman -Qq umbriel >/dev/null 2>&1; then
        target=umbriel
    else
        printf 'Umbriel is not installed; no package changed.\n'
        exit 0
    fi
    entry=/usr/share/wayland-sessions/umbriel.desktop
    owner="$(pacman -Qqo -- "$entry" 2>/dev/null || true)"
    [[ "$owner" == "$target" && -f "$entry" && ! -L "$entry" ]] || {
        printf 'Umbriel Ly session is not owned by the target package; preserving it.\n' >&2
        false
    }
    proposed="$(pacman -R --print --print-format '%n' -- "$target")" || {
        printf 'Pacman dependency preflight rejected Umbriel removal.\n' >&2
        false
    }
    [[ "$proposed" == "$target" ]] || {
        printf 'Unexpected package removal set; refusing.\n' >&2; false;
    }
    printf 'Umbriel package eligible for removal: %s\n' "$target"
    printf 'All configs, Awtarchy preferences, and portal packages remain intact.\n'
    if [[ "$mode" == preview ]]; then
        printf 'Preview only; no package removed.\n'
        exit 0
    fi
    # The compositor menu already provides a normal Remove/Cancel choice.
    # Direct "remove-umbriel apply" is an explicit command, so it needs no
    # second typed authorization. Keep the package/last-session safeguards.
    sudo pacman -R --noconfirm -- "$target"
    ! pacman -Qq "$target" >/dev/null 2>&1 || {
        printf 'Umbriel package still installed after removal attempt.\n' >&2; false;
    }
    printf 'Removed %s. Personal Umbriel files and shared dependencies retained.\n' "$target"
    exit 0
fi
printf 'No compositor packages or login sessions will be uninstalled.\n'
if pacman -Qq umbriel-git >/dev/null 2>&1; then
    printf 'Umbriel: umbriel-git installed\n'
elif pacman -Qq umbriel >/dev/null 2>&1; then
    printf 'Umbriel: existing umbriel package will be preserved\n'
else
    printf 'Umbriel: requires AUR package umbriel-git (yay)\n'
fi
python3 "$repo/compositors/umbriel/sync.py" preview --repo "$repo"
if [[ "$mode" == preview ]]; then
    printf 'Preview only. No packages, session entries or configs changed.\n'
    exit 0
fi
# "Install" in the compositor menu confirms the operation. A direct
# "install-umbriel apply" command explicitly requests installation.
# Keep yay/pacman review and sudo authentication where they are required.
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
for app in quickshell foot wdisplays jq python wl-clipboard cliphist xdg-desktop-portal-gtk grim slurp satty; do
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
mkdir -p "$check/umbriel/awtarchy"
cp -- "$repo/compositors/umbriel/native-config.toml" "$check/umbriel/config.toml"
cp -- "$repo/compositors/umbriel/config.toml" "$check/umbriel/awtarchy/config.toml"
# Validate all included TOML paths, not just the main config. Other source
# profiles are tested by sync.py; these stubs only let native parsing proceed.
for include in theme.toml migrated.toml capture-rules.toml floating-rules.toml; do
    : >"$check/umbriel/awtarchy/$include"
done
if ! XDG_CONFIG_HOME="$check" umbriel config validate; then
    printf 'Umbriel rejected the managed config. No user config applied.\n' >&2
    false
fi
python3 "$repo/compositors/umbriel/sync.py" apply --repo "$repo"
# Ly may use Awtarchy's curated session directory instead of the package
# directory. Register only the Umbriel package entry; never edit Ly config,
# replace an existing session file, or add duplicate compositor entries.
if [[ -f /etc/ly/config.ini && ! -L /etc/ly/config.ini ]]; then
    if ! bash "$repo/compositors/umbriel/register-ly-session.sh" apply; then
        printf 'Umbriel config is staged, but Ly registration needs attention.\n' >&2
        printf 'Review safely: bash %s/compositors/umbriel/register-ly-session.sh plan\n' "$repo" >&2
        false
    fi
else
    printf 'Ly is not configured; use the Umbriel TTY command instead.\n'
fi
printf 'Umbriel managed files staged; Ly visibility is not yet verified.\n'
printf 'Ly reads session entries when it starts. A reboot may be necessary\n'
printf 'before Umbriel appears; do not restart Ly from an active desktop.\n'
printf 'If Umbriel remains absent, run: bash %s/compositors/umbriel/diagnose-session.sh\n' "$repo"
printf 'Existing compositor configs and sessions remain installed.\n'
printf 'Reboot is recommended before first login; no automatic restart.\n'
