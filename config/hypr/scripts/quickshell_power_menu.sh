#!/usr/bin/env bash
# Toggle the Awtarchy Quickshell power/session menu.

set -euo pipefail

SCRIPTS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts"
QS_BIN="${QS_BIN:-qs}"
RETURN_SUBMAP="${1:-reset}"
case "$RETURN_SUBMAP" in
    reset|noalt) ;;
    *) RETURN_SUBMAP="reset" ;;
esac

submap_restored=0

restore_input_submap() {
    if (( submap_restored )); then
        return 0
    fi
    submap_restored=1
    hyprctl dispatch "hl.dsp.submap(\"${RETURN_SUBMAP}\")" >/dev/null 2>&1 || true
}

trap restore_input_submap EXIT

main() {
    local opened=""

    "$SCRIPTS_DIR/quickshell.sh" start >/dev/null

    # The compositor-owned temporary submap retains rapid follow-up actions
    # while Quickshell starts. Secure capture is intentionally deferred until
    # the Lock action itself so the Power Menu can appear immediately.
    for _ in {1..20}; do
        opened="$("$QS_BIN" -c awtarchy ipc call powermenu begin 2>/dev/null | tail -n1 || true)"
        if [[ "$opened" == true || "$opened" == false ]]; then
            break
        fi
        sleep 0.01
    done

    restore_input_submap
}

main "$@"
