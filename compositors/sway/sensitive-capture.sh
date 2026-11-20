#!/usr/bin/env bash
# Sway has no tested equivalent to Hyprland's per-surface screenshot exclusion.
# Awtarchy VPN/private UI MUST fail closed rather than expose credentials
# through an active screen share.
set -euo pipefail
[[ "${XDG_CURRENT_DESKTOP:-}" == sway ]] || {
    printf 'Sway-only capture safeguard invoked outside Sway\n' >&2
    exit 1
}
printf 'Sway: VPN/private panel cannot open: secure capture exclusion is unavailable.\n' >&2
exit 1
