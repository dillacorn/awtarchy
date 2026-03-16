#!/usr/bin/env bash
set -euo pipefail

# ~/.config/hypr/scripts/waybar_ready_sound.sh
#
# Purpose:
#   Wait for Waybar, optionally wait through a separate usb_refresh_fixer.sh run,
#   then wait for audio to settle and play a sound once.
#
# Design:
#   - Does NOT call usb_refresh_fixer.sh itself.
#   - If usb_refresh_fixer.sh is not used, this still works normally.
#   - If usb_refresh_fixer.sh is used at boot, this waits for its activity lock.
#
# Tunables:
#   WAIT_WAYBAR_SECS          total wait for Waybar visibility
#   WAYBAR_POLL_SECS          Waybar polling interval
#   REFRESH_DETECT_WINDOW_SECS how long to watch for optional usb refresh startup
#   WAIT_AUDIO_SECS           total wait for audio/default-sink readiness
#   AUDIO_POLL_SECS           audio polling interval
#   QUIET_POLLS               refresh lock must be absent this many polls in a row
#   STABLE_POLLS              default sink must stay stable this many polls in a row
#   SOUND_FILE                file to play
#   USB_REFRESH_LOCK_FILE     override lock path if needed

WAIT_WAYBAR_SECS="${WAIT_WAYBAR_SECS:-30}"
WAYBAR_POLL_SECS="${WAYBAR_POLL_SECS:-0.05}"

REFRESH_DETECT_WINDOW_SECS="${REFRESH_DETECT_WINDOW_SECS:-8}"
WAIT_AUDIO_SECS="${WAIT_AUDIO_SECS:-60}"
AUDIO_POLL_SECS="${AUDIO_POLL_SECS:-0.20}"
QUIET_POLLS="${QUIET_POLLS:-8}"
STABLE_POLLS="${STABLE_POLLS:-8}"

SOUND_FILE="${SOUND_FILE:-$HOME/.config/hypr/sounds/awtarchy-login.mp3}"
USB_REFRESH_LOCK_FILE="${USB_REFRESH_LOCK_FILE:-/tmp/usb_refresh_fixer.$(id -un).active}"
SCRIPT_LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/waybar_ready_sound.lock"

have() { command -v "$1" >/dev/null 2>&1; }
is_waybar_up() { pgrep -x waybar >/dev/null 2>&1; }

is_waybar_visible() {
    is_waybar_up || return 1
    have hyprctl || return 0

    if have jq; then
        hyprctl layers -j 2>/dev/null \
            | jq -e '.. | objects | (.namespace? // empty) | select(type=="string") | select(test("^waybar"; "i"))' \
            >/dev/null 2>&1
        return $?
    fi

    hyprctl layers 2>/dev/null | grep -Eqi 'namespace: *waybar|waybar'
}

wait_for_waybar_visible() {
    local end
    end=$(( $(date +%s) + WAIT_WAYBAR_SECS ))

    while (( $(date +%s) < end )); do
        if is_waybar_visible; then
            return 0
        fi
        sleep "$WAYBAR_POLL_SECS"
    done

    return 1
}

default_sink_name() {
    have wpctl || return 1

    wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk -F'"' '
        /node\.name =/        { print $2; found=1; exit }
        /node\.nick =/        { if (nick == "") nick=$2 }
        /node\.description =/ { if (desc == "") desc=$2 }
        END {
            if (!found) {
                if (nick != "") print nick
                else if (desc != "") print desc
            }
        }
    '
}

default_sink_desc() {
    have wpctl || return 1

    wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk -F'"' '
        /node\.description =/ { print $2; found=1; exit }
        /node\.nick =/        { if (!found) print $2; found=1; exit }
    '
}

default_sink_is_real() {
    local sink
    sink="$(default_sink_name || true)"
    [[ -n "$sink" ]] || return 1
    [[ "$sink" != "auto_null" ]] || return 1
    return 0
}

refresh_lock_active() {
    local pid
    [[ -r "$USB_REFRESH_LOCK_FILE" ]] || return 1
    pid="$(tr -dc '0-9' < "$USB_REFRESH_LOCK_FILE" 2>/dev/null || true)"
    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    [[ -d "/proc/$pid" ]]
}

wait_for_optional_refresh_cycle() {
    local detect_end settle_end quiet=0
    REFRESH_WAS_SEEN=0

    detect_end=$(( $(date +%s) + REFRESH_DETECT_WINDOW_SECS ))
    while (( $(date +%s) < detect_end )); do
        if refresh_lock_active; then
            REFRESH_WAS_SEEN=1
            break
        fi
        sleep "$AUDIO_POLL_SECS"
    done

    if (( REFRESH_WAS_SEEN == 0 )); then
        return 0
    fi

    settle_end=$(( $(date +%s) + WAIT_AUDIO_SECS ))
    while (( $(date +%s) < settle_end )); do
        if refresh_lock_active; then
            quiet=0
        else
            ((quiet++))
            if (( quiet >= QUIET_POLLS )); then
                return 0
            fi
        fi
        sleep "$AUDIO_POLL_SECS"
    done

    return 1
}

find_sink_id_by_name() {
    local want="$1"
    [[ -n "$want" ]] || return 1
    have jq || return 1
    have pw-dump || return 1

    pw-dump 2>/dev/null | jq -r --arg want "$want" '
        .[]
        | select(.type == "PipeWire:Interface:Node")
        | select(.info.props["media.class"] == "Audio/Sink")
        | select(.info.props["node.name"] == $want)
        | .id
    ' | head -n1
}

find_sink_id_by_desc() {
    local want="$1"
    [[ -n "$want" ]] || return 1
    have jq || return 1
    have pw-dump || return 1

    pw-dump 2>/dev/null | jq -r --arg want "$want" '
        .[]
        | select(.type == "PipeWire:Interface:Node")
        | select(.info.props["media.class"] == "Audio/Sink")
        | select(
            .info.props["node.description"] == $want
            or .info.props["node.nick"] == $want
        )
        | .id
    ' | head -n1
}

wait_for_saved_sink_back_and_restore() {
    local saved_name="$1"
    local saved_desc="$2"
    local end id="" cur="" last="" count=0

    have wpctl || return 1
    end=$(( $(date +%s) + WAIT_AUDIO_SECS ))

    while (( $(date +%s) < end )); do
        id=""

        if [[ -n "$saved_name" ]]; then
            id="$(find_sink_id_by_name "$saved_name" || true)"
        fi

        if [[ -z "$id" && -n "$saved_desc" ]]; then
            id="$(find_sink_id_by_desc "$saved_desc" || true)"
        fi

        if [[ -n "$id" ]]; then
            wpctl set-default "$id" >/dev/null 2>&1 || true

            if [[ -n "$saved_name" ]]; then
                cur="$(default_sink_name || true)"
            else
                cur="$(default_sink_desc || true)"
            fi

            if [[ -n "$cur" && "$cur" == "${saved_name:-$saved_desc}" ]]; then
                if [[ "$cur" == "$last" ]]; then
                    ((count++))
                else
                    last="$cur"
                    count=1
                fi

                if (( count >= STABLE_POLLS )); then
                    return 0
                fi
            else
                last=""
                count=0
            fi
        fi

        sleep "$AUDIO_POLL_SECS"
    done

    return 1
}

wait_for_stable_real_default_sink() {
    local end last="" cur="" count=0
    end=$(( $(date +%s) + WAIT_AUDIO_SECS ))

    while (( $(date +%s) < end )); do
        cur="$(default_sink_name || true)"

        if [[ -n "$cur" && "$cur" != "auto_null" ]]; then
            if [[ "$cur" == "$last" ]]; then
                ((count++))
            else
                last="$cur"
                count=1
            fi

            if (( count >= STABLE_POLLS )); then
                return 0
            fi
        else
            last=""
            count=0
        fi

        sleep "$AUDIO_POLL_SECS"
    done

    return 1
}

try_play() {
    [[ -f "$SOUND_FILE" ]] || return 1
    have pw-play || return 1
    pw-play "$SOUND_FILE" >/dev/null 2>&1
}

play_with_retry() {
    local end
    end=$(( $(date +%s) + WAIT_AUDIO_SECS ))

    while (( $(date +%s) < end )); do
        if default_sink_is_real && try_play; then
            return 0
        fi
        sleep "$AUDIO_POLL_SECS"
    done

    return 1
}

main() {
    local saved_name="" saved_desc=""

    if have flock; then
        exec 9>"$SCRIPT_LOCK_FILE"
        flock -n 9 || exit 0
    fi

    wait_for_waybar_visible || exit 0

    if default_sink_is_real; then
        saved_name="$(default_sink_name || true)"
        saved_desc="$(default_sink_desc || true)"
    fi

    wait_for_optional_refresh_cycle || exit 0

    if (( REFRESH_WAS_SEEN == 1 )) && [[ -n "$saved_name$saved_desc" ]]; then
        wait_for_saved_sink_back_and_restore "$saved_name" "$saved_desc" || true
    fi

    wait_for_stable_real_default_sink || exit 0
    play_with_retry || exit 0
}

main "$@"
