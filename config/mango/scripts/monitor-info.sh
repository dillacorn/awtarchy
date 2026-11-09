#!/usr/bin/env bash
# Read-only Mango output identity for Awtarchy's existing DDC/CI controller map.
# Emit exactly one tab-separated record: connector / make / model / serial / desc.
set -euo pipefail

[[ "${XDG_CURRENT_DESKTOP:-}" == mango && -n "${MANGO_INSTANCE_SIGNATURE:-}" ]] || {
    printf 'monitor-info: not in a Mango compositor session\n' >&2
    exit 1
}
command -v mmsg >/dev/null && command -v jq >/dev/null && command -v wlr-randr >/dev/null || {
    printf 'monitor-info: mmsg, jq and wlr-randr are required\n' >&2
    exit 1
}
[[ $# -le 1 ]] || exit 2

connector="${1:-}"
if [[ -z "$connector" ]]; then
    connector="$(mmsg get all-monitors | jq -er '
        .monitors | map(select(.active == true)) |
        if length == 1 then .[0].name else empty end
    ')" || exit 1
fi
[[ "$connector" =~ ^[A-Za-z0-9_.-]+$ ]] || {
    printf 'monitor-info: unsupported output identifier\n' >&2
    exit 1
}

wlr-randr | awk -v target="$connector" '
    /^[^[:space:]]/ {
        if (active) {
            printf "%s\t%s\t%s\t%s\t%s\n", name, make, model, serial, description
            found=1
            exit
        }
        active=($1 == target)
        if (active) {
            name=$1; make=""; model=""; serial=""
            description=$0
            sub(/^[^[:space:]]+[[:space:]]+/, "", description)
            gsub(/^"|"$/, "", description)
        }
        next
    }
    active && /^  Make:/ {
        make=$0; sub(/^ *Make:[[:space:]]*/, "", make); next
    }
    active && /^  Model:/ {
        model=$0; sub(/^ *Model:[[:space:]]*/, "", model); next
    }
    active && /^  Serial:/ {
        serial=$0; sub(/^ *Serial:[[:space:]]*/, "", serial); next
    }
    END {
        if (!found && active) {
            printf "%s\t%s\t%s\t%s\t%s\n", name, make, model, serial, description
            found=1
        }
        if (!found) exit 1
    }
'
