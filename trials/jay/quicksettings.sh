#!/usr/bin/env bash
# Jay-only Quick Settings adapter. Never calls Hyprland or changes its state.
set -euo pipefail
[[ "${XDG_CURRENT_DESKTOP:-}" == jay && -n "${WAYLAND_DISPLAY:-}" ]] || {
    printf 'Jay Quick Settings requires an active Jay Wayland session\n' >&2
    exit 1
}
config="${XDG_CONFIG_HOME:-$HOME/.config}"
python3 "$config/jay/awtarchy-trial/quicksettings.py" "$@"
