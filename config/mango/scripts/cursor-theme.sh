#!/usr/bin/env bash
# Keep the shared Quickshell cursor preference consistent between both sessions.
set -euo pipefail
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
original="${CONFIG_HOME}/hypr/scripts/quickshell_cursor_theme.sh"
syncer="${CONFIG_HOME}/mango/scripts/cursor-variant.py"
mango_config="${CONFIG_HOME}/mango/config.conf"
state="${CACHE_HOME}/awtarchy/quickshell-state.json"
[[ -f "$original" && ! -L "$original" && -f "$syncer" && ! -L "$syncer" ]] || {
    printf 'Mango cursor helper is unavailable.\n' >&2
    return 1 2>/dev/null || false
}
case "${1:-status}" in
    status)
        bash "$original" status
        ;;
    set)
        [[ $# -eq 2 ]] || { printf 'usage: cursor-theme.sh set <variant>\n' >&2; false; }
        bash "$original" set "$2"
        python3 "$syncer" --config "$mango_config" --state "$state" --apply
        ;;
    reapply)
        [[ $# -eq 1 ]] || { printf 'usage: cursor-theme.sh reapply\n' >&2; false; }
        bash "$original" reapply
        python3 "$syncer" --config "$mango_config" --state "$state" --apply
        ;;
    *)
        printf 'usage: cursor-theme.sh {status|set <variant>|reapply}\n' >&2
        false
        ;;
esac
