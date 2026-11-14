#!/usr/bin/env bash
# Share Awtarchy's saved UI settings, with Sway-specific shell lifecycle.
set -euo pipefail
config="${XDG_CONFIG_HOME:-$HOME/.config}"
shared="$config/hypr/scripts/quickshell_application_state.sh"
manager="$config/sway/awtarchy-trial/quickshell.sh"
[[ -f "$shared" && ! -L "$shared" && -f "$manager" && ! -L "$manager" ]] || {
    printf 'Sway: shared state backend missing or linked\n' >&2; exit 1;
}
HYPR_QUICKSHELL_SCRIPT="$manager" bash "$shared" "$@"
