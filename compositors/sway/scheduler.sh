#!/usr/bin/env bash
# Compositor-independent sched-ext bridge for Sway and Umbriel. Import only
# the established Awtarchy scheduler functions; never run Hyprland IPC.
set -euo pipefail

trial="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
core="$trial/hypr_quicksettings_core.sh"
entry="$trial/hypr_quicksettings.sh"
for file in "$core" "$entry"; do
    [[ -f "$file" && ! -L "$file" && -r "$file" ]] || {
        printf 'Missing private scheduler source: %s\n' "$file" >&2
        false
    }
done
grep -Fxq 'main "$@"' "$core"
grep -Fxq 'scxctl_auth_state_cached() {' "$entry"
grep -Fxq 'case "${1:-}" in' "$entry"
# Load only declarations/functions, not either Hyprland command dispatcher.
# shellcheck disable=SC1090
source <(sed '/^main "\$@"$/d' "$core")
SCHED_EXT_AUTH_STATE_FILE="$STATE_DIR/scxctl_authorized"
# shellcheck disable=SC1090
source <(awk '
    /^scxctl_auth_state_cached\(\) \{$/ { copy=1 }
    copy && /^case "\$\{1:-\}" in$/ { exit }
    copy { print }
' "$entry")
hypr_notify() { :; } # No Hyprland-only notification IPC.

scheduler_status_json() {
    command -v jq >/dev/null 2>&1 || {
        printf 'sched-ext requires jq\n' >&2
        return 127
    }
    local scheduler profiles_json profile custom autopower summary schedulers_json
    local authorized=false available=false
    sched_ext_state_load
    refresh_sched_ext
    (( EUID == 0 )) && authorized=true
    scxctl_auth_state_cached && authorized=true
    command -v scxctl >/dev/null 2>&1 && available=true
    schedulers_json='[]'
    for scheduler in "${SCHED_EXT_ITEMS[@]}"; do
        profiles_json="$(sched_ext_profiles_for "$scheduler" | jq -Rsc 'split("\n") | map(select(length > 0))')"
        profile="${SCHED_EXT_PROFILE_MAP[$scheduler]:-Default}"
        custom="$(sched_ext_normalize_args "${SCHED_EXT_CUSTOM_ARGS_MAP[$scheduler]:-}")"
        autopower="${SCHED_EXT_LAVD_AUTOPOWER_MAP[$scheduler]:-0}"
        summary="$(sched_ext_config_summary "$scheduler")"
        schedulers_json="$(jq -c \
            --arg scheduler "$scheduler" --arg profile "$profile" \
            --arg custom "$custom" --arg autopower "$autopower" \
            --arg summary "$summary" --argjson profiles "$profiles_json" '
            . + [{
                name:$scheduler, profile:$profile, profiles:$profiles,
                custom_args:$custom, autopower:($autopower == "1"), summary:$summary
            }]' <<<"$schedulers_json")"
    done
    jq -cn --arg running "$SCHED_EXT_RUNNING" --arg mode "$SCHED_EXT_MODE" \
        --arg enabled "$SCHED_EXT_ENABLED" --arg last_selected "$SCHED_EXT_LAST_SELECTED" \
        --arg restore_enabled "$SCHED_EXT_RESTORE_ENABLED" \
        --arg available "$available" --arg authorized "$authorized" \
        --argjson schedulers "$schedulers_json" '{
            running:$running, mode:$mode, enabled:($enabled == "1"),
            last_selected:$last_selected, restore_enabled:($restore_enabled == "1"),
            available:($available == "true"), authorized:($authorized == "true"),
            schedulers:$schedulers
        }'
}

case "${1:-}" in
    --status-json)
        [[ $# -eq 1 ]]
        scheduler_status_json
        ;;
    --action)
        [[ $# -ge 2 ]] || false
        case "$2" in
            scheduler-start|scheduler-stop|scheduler-profile|scheduler-args|scheduler-autopower|scheduler-reset)
                shift
                machine_action "$@"
                ;;
            *) printf 'Unsupported scheduler action\n' >&2; false ;;
        esac
        ;;
    --restore-scheduler)
        [[ $# -eq 1 ]]
        machine_scheduler_restore
        ;;
    --authorize-scheduler-stdin)
        [[ $# -eq 1 ]]
        machine_scheduler_authorize_stdin
        ;;
    *) printf 'Unknown sched-ext command\n' >&2; false ;;
esac
