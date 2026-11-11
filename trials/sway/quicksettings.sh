#!/usr/bin/env bash
# Sway-only Quick Settings adapter. Never calls Hyprland or changes its state.
set -euo pipefail
[[ "${XDG_CURRENT_DESKTOP:-}" == sway && -n "${WAYLAND_DISPLAY:-}" ]] || {
    printf 'Sway Quick Settings requires an active Sway Wayland session\n' >&2
    exit 1
}
config="${XDG_CONFIG_HOME:-$HOME/.config}"
python3 "$config/sway/awtarchy-trial/quicksettings.py" "$@"
