#!/usr/bin/bash
# Root-owned Ly session wrapper, configured per login user.
set -euo pipefail
[[ -n "${HOME:-}" && "$HOME" == /* ]] || {
    printf 'Missing absolute login HOME for Sway trial\n' >&2; exit 1;
}
configuration="${XDG_CONFIG_HOME:-$HOME/.config}/sway/awtarchy-trial/config"
[[ -f "$configuration" && ! -L "$configuration" ]] || {
    printf 'Missing isolated Awtarchy Sway configuration: %s\n' "$configuration" >&2; exit 1;
}
export XDG_CURRENT_DESKTOP=sway
export XDG_SESSION_DESKTOP=sway
export XDG_SESSION_TYPE=wayland
exec /usr/bin/sway --config "$configuration"
