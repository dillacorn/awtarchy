#!/usr/bin/env bash
# Apply wdisplays' saved output profiles inside this Mango session only.
# Never change Hyprland or overwrite a user-owned kanshi configuration.
set -euo pipefail

[[ -n "${MANGO_INSTANCE_SIGNATURE:-}" && -n "${WAYLAND_DISPLAY:-}" ]] || {
    printf 'Mango kanshi: compositor session unavailable\n' >&2
    exit 1
}

config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
profile="${WDISPLAYS_KANSHI_CONFIG:-$config_home/kanshi/config}"
local_rules="$config_home/mango/monitors-local.conf"

# A fresh user without a saved wdisplays profile needs no daemon.
[[ -e "$profile" || -L "$profile" ]] || exit 0

if [[ ! -f "$profile" || -L "$profile" || ! -r "$profile" ]]; then
    printf 'Mango kanshi: refusing non-regular or linked profile: %s\n' "$profile" >&2
    exit 1
fi

# Two output owners create re-application races after hotplug/config reload.
# Keep the existing Mango profile untouched; require one source of truth.
if [[ -e "$local_rules" || -L "$local_rules" ]]; then
    printf 'Mango kanshi: both saved kanshi and monitors-local.conf exist; refusing conflicting output controllers\n' >&2
    exit 1
fi

command -v kanshi >/dev/null 2>&1 || {
    printf 'Mango kanshi: installed kanshi package is missing; saved display configuration was not applied\n' >&2
    exit 1
}

# Remain attached to Mango's lifecycle. The parent session backgrounds this
# long-running process, and terminating that session ends the daemon.
kanshi -c "$profile"
