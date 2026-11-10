#!/usr/bin/env bash
# Jay has no tested equivalent to Hyprland's per-surface screenshot exclusion.
# Awtarchy VPN/private UI MUST fail closed rather than expose credentials
# through an active screen share.
set -euo pipefail
[[ "${XDG_CURRENT_DESKTOP:-}" == jay ]] || {
    printf 'Jay-only capture safeguard invoked outside Jay\n' >&2
    exit 1
}
printf 'Jay: VPN/private panel cannot open: secure capture exclusion is unavailable.\n' >&2
exit 1
