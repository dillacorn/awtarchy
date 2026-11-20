#!/usr/bin/env bash
# Sway-only Quickshell bar brightness adapter.
# Use branch-matched, isolated copies of the Awtarchy DDC scripts so a Sway
# update never needs to replace the user's managed Hyprland configuration.
set -euo pipefail

[[ "${XDG_CURRENT_DESKTOP:-}" == "sway" && -n "${SWAYSOCK:-}" ]] || {
    printf 'Sway brightness requires an active Sway session\n' >&2
    exit 1
}
trial="${XDG_CONFIG_HOME:-$HOME/.config}/sway/awtarchy-trial"
bar="$trial/ddc_brightness.sh"
controller="$trial/hypr-ddc-brightness.sh"
for script in "$bar" "$controller"; do
    [[ -f "$script" && ! -L "$script" && -x "$script" ]] || {
        printf 'Missing Sway brightness helper: %s\n' "$script" >&2
        exit 1
    }
done
export HYPR_BRIGHTNESS_SCRIPT="$controller"
exec bash "$bar" "$@"
