#!/usr/bin/env bash
# Deliver a Power Menu action captured synchronously by Hyprland's temporary
# pre-map submap. Retry until the QML Power Menu has armed its input surface.

set -euo pipefail

QS_BIN="${QS_BIN:-qs}"
RETRY_DELAY="${AWTARCHY_POWER_MENU_KEY_RETRY_DELAY:-0.01}"
RETRY_COUNT="${AWTARCHY_POWER_MENU_KEY_RETRY_COUNT:-300}"

main() {
    local action="${1:-}"
    local accepted=""
    local attempt

    case "$action" in
        l|h|r|s|o|z|escape) ;;
        *)
            printf 'quickshell_power_menu_key.sh: invalid action: %s\n' "$action" >&2
            return 2
            ;;
    esac

    for ((attempt = 0; attempt < RETRY_COUNT; ++attempt)); do
        accepted="$("$QS_BIN" -c awtarchy ipc call powermenu fastKey "$action" 2>/dev/null | tail -n1 || true)"
        if [[ "$accepted" == true ]]; then
            return 0
        fi
        sleep "$RETRY_DELAY"
    done

    printf 'quickshell_power_menu_key.sh: Power Menu did not accept action: %s\n' "$action" >&2
    return 1
}

main "$@"
