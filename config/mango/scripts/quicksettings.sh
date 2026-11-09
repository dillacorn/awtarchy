#!/usr/bin/env bash
# Mango-facing backend for Awtarchy's Quickshell Quick Settings.
# Retain the existing brightness, scheduler and bar settings implementation;
# fail closed for actions with no correct Mango equivalent.
set -euo pipefail

config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
original="$config_home/hypr/scripts/hypr_quicksettings.sh"
manager="$config_home/mango/scripts/quickshell.sh"

[[ -f "$original" && ! -L "$original" && -f "$manager" && ! -L "$manager" ]] || {
    printf 'Mango Quick Settings: required Awtarchy backend is missing or linked.\n' >&2
    false
}
command -v mmsg >/dev/null 2>&1 || {
    printf 'Mango Quick Settings: mmsg is required.\n' >&2
    false
}
command -v jq >/dev/null 2>&1 || {
    printf 'Mango Quick Settings: jq is required.\n' >&2
    false
}

status() {
    local monitor="${1:-}" brightness="${2:-}"
    local base monitors keymode barposition barenabled autohide

    # This backend already owns scheduler state and DDC brightness. Do not
    # create a second scheduler or brightness preference store.
    base="$(bash "$original" --status-json "$monitor" "$brightness")" || return 1
    jq -e 'type == "object" and (.sched_ext | type == "object")' <<<"$base" >/dev/null || return 1

    monitors="$(mmsg get all-monitors | jq -ec '
        [.monitors[]
          | {
              name: (.name // ""),
              description: "",
              focused: (.active == true),
              width: (.width // 0),
              height: (.height // 0),
              refresh_rate: 0
            }
        ]')" || return 1
    keymode="$(mmsg get keymode | jq -er '.keymode // "default"')" || return 1

    # The Mango shell manager shares the original persisted bar state.
    barposition="$(bash "$manager" getpos "$monitor")" || return 1
    barenabled="$(bash "$manager" getenabled "$monitor")" || return 1
    autohide="$(bash "$manager" getautohide "$monitor")" || return 1
    [[ "$barposition" =~ ^(top|bottom|left|right)$ ]] || return 1
    [[ "$barenabled" =~ ^(true|false)$ && "$autohide" =~ ^(true|false)$ ]] || return 1

    jq -cn --argjson original "$base" --argjson monitors "$monitors" \
        --arg monitor "$monitor" --arg position "$barposition" \
        --arg enabled "$barenabled" --arg autohide "$autohide" \
        --arg keymode "$keymode" '
        $original
        | .monitors = $monitors
        | .bar = {
            monitor: $monitor, position: $position,
            enabled: ($enabled == "true"), auto_hide: ($autohide == "true")
          }
        | .submap = (if $keymode == "default" then "reset" else $keymode end)
        | .night_light.enabled = false
        | .night_light.identity = "unavailable"
        | .night_light.schedule_enabled = false
        | .vibrance.enabled = false
        | .vibrance.value = null
    '
}

action() {
    local name="${1:-}" monitor="${2:-}" value="${3:-}"
    shift || true
    case "$name" in
        brightness-adjust|brightness-percent|scheduler-start|scheduler-stop|scheduler-profile|scheduler-args|scheduler-autopower|scheduler-reset|wallpaper)
            # These operations do not require Hyprland IPC.
            bash "$original" --action "$name" "$@"
            ;;
        bar-enabled|bar-auto-hide)
            [[ $# == 2 && -n "$monitor" && "$value" =~ ^(true|false)$ ]] || return 2
            if [[ "$name" == bar-enabled ]]; then
                bash "$manager" setenabled "$monitor" "$value"
            else
                bash "$manager" setautohide "$monitor" "$value"
            fi
            ;;
        bar-position)
            [[ $# == 2 && -n "$monitor" && "$value" =~ ^(top|bottom|left|right)$ ]] || return 2
            bash "$manager" setpos "$monitor" "$value"
            ;;
        submap)
            [[ $# == 1 && "$monitor" =~ ^(reset|noalt|mouse|vm)$ ]] || return 2
            local helper="$config_home/mango/scripts/keymode.sh"
            [[ -f "$helper" && ! -L "$helper" ]] || {
                printf 'Mango key mode helper is unavailable.\n' >&2
                return 1
            }
            if [[ "$monitor" == reset ]]; then
                bash "$helper" set default
            else
                bash "$helper" set "$monitor"
            fi
            ;;
        night-light|night-light-schedule|vibrance)
            printf 'Mango Quick Settings: %s has no equivalent backend yet.\n' "$name" >&2
            return 2
            ;;
        *)
            printf 'Mango Quick Settings: unsupported action %s\n' "$name" >&2
            return 2
            ;;
    esac
}

case "${1:-}" in
    --status-json)
        shift
        status "$@"
        ;;
    --action)
        shift
        action "$@"
        ;;
    --authorize-scheduler-stdin|--restore-scheduler)
        # Preserve the restricted and already-tested scxctl authorization
        # path verbatim. Never read or log stdin in this wrapper.
        bash "$original" "$@"
        ;;
    *)
        printf 'usage: quicksettings.sh --status-json [monitor [brightness]] | --action ...\n' >&2
        false
        ;;
esac
