#!/usr/bin/env bash
# Final automatic suspend action: secure lock before any system sleep.
set -euo pipefail
manager="${XDG_CONFIG_HOME:-$HOME/.config}/mango/scripts/lock.sh"
[[ -f "$manager" && ! -L "$manager" ]] || {
    printf 'Mango secure lock manager unavailable; refusing suspend.\n' >&2
    false
}
bash "$manager" suspend
