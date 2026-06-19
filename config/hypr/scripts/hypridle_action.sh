#!/usr/bin/env bash
# ~/.config/hypr/scripts/hypridle_action.sh
# Hard guard for every Hypridle timeout action.

set -euo pipefail

CONF="${XDG_CONFIG_HOME:-$HOME/.config}"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}"

INHIBITOR_SH="${INHIBITOR_SH:-${CONF}/waybar/scripts/idle_inhibitor_global.sh}"
SCRIPTS_DIR="${CONF}/hypr/scripts"
LOG_FILE="${HYPRIDLE_ACTION_LOG:-${CACHE}/hypridle/actions.log}"

mkdir -p "$(dirname "$LOG_FILE")"

log() {
    printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$LOG_FILE" 2>/dev/null || true
}

action="${1:-}"
shift || true

case "$action" in
    prepare-sleep)
        "$INHIBITOR_SH" off >/dev/null 2>&1 || true
        log "sleep transition: inhibitor reset before sleep"
        exec loginctl lock-session
        ;;

    resume-sleep)
        "$INHIBITOR_SH" off >/dev/null 2>&1 || true
        log "sleep transition: inhibitor reset after sleep"
        exec hyprctl dispatch 'hl.dsp.dpms({ action = "enable" })'
        ;;
esac

if [[ -x "$INHIBITOR_SH" ]] && "$INHIBITOR_SH" is-active >/dev/null 2>&1; then
    log "blocked timeout action: ${action:-missing}"
    exit 0
fi

log "allowed timeout action: ${action:-missing}"

case "$action" in
    waybar-hide)
        exec "${SCRIPTS_DIR}/waybar_toggle_idle.sh"
        ;;

    dim)
        exec "${SCRIPTS_DIR}/dim_display.sh"
        ;;

    lock)
        exec loginctl lock-session
        ;;

    dpms-off)
        exec hyprctl dispatch 'hl.dsp.dpms({ action = "disable" })'
        ;;

    suspend)
        systemctl suspend || exec loginctl suspend
        ;;

    test-touch)
        marker="${1:-}"
        [[ -n "$marker" ]] || {
            printf '%s\n' 'test-touch requires a marker path' >&2
            exit 2
        }
        printf 'fired\n' >"$marker"
        ;;

    *)
        printf 'Unknown Hypridle action: %s\n' "${action:-missing}" >&2
        exit 2
        ;;
esac
