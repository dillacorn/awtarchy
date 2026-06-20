#!/usr/bin/env bash
# ~/.config/hypr/scripts/hypridle_action.sh
# Authoritative guard for every Hypridle timeout action.

set -euo pipefail

CONF="${XDG_CONFIG_HOME:-$HOME/.config}"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}"

INHIBITOR_SH="${INHIBITOR_SH:-${CONF}/waybar/scripts/idle_inhibitor_global.sh}"
SCRIPTS_DIR="${CONF}/hypr/scripts"
LOG_FILE="${HYPRIDLE_ACTION_LOG:-${CACHE}/hypridle/actions.log}"

HYPRCTL_BIN="${HYPRCTL_BIN:-hyprctl}"
PLAYERCTL_BIN="${PLAYERCTL_BIN:-playerctl}"

# Keep synchronized with the game classes in hyprland.lua.
GAME_CLASS_REGEX='^(steam_app_.*|lutris_game_class|minigalaxy|playnite_game_class|gamescope|chiaki|moonlight|com\.moonlight_stream\.Moonlight|.*\.exe)$'

# Browser playback only blocks idle while a browser window is fullscreen.
BROWSER_CLASS_REGEX='^(firefox|org\.mozilla\.firefox|firefoxdeveloperedition|librewolf|floorp|zen|zen-browser|chromium|chromium-browser|org\.chromium\.Chromium|google-chrome.*|brave-browser.*|com\.brave\.Browser|vivaldi.*|microsoft-edge.*)$'
BROWSER_MPRIS_REGEX='^(firefox|librewolf|floorp|zen|chromium|google-chrome|chrome|brave|vivaldi|microsoft-edge|edge)([._-]|$)'

# Dedicated video players block idle whenever they are actively playing.
VIDEO_PLAYER_CLASS_REGEX='^(mpv|vlc|org\.videolan\.VLC|celluloid|io\.github\.celluloid_player\.Celluloid|haruna|org\.kde\.haruna|smplayer|totem|org\.gnome\.Totem|clapper|com\.github\.rafostar\.Clapper|stremio|com\.stremio\.Stremio|jellyfin-media-player|com\.github\.iwalton3\.jellyfin-media-player|freetube|io\.freetubeapp\.FreeTube)$'
VIDEO_PLAYER_MPRIS_REGEX='(mpv|vlc|celluloid|haruna|smplayer|totem|clapper|stremio|jellyfin|freetube)'

mkdir -p "$(dirname "$LOG_FILE")"

log() {
    printf '%s %s\n' \
        "$(date '+%F %T')" \
        "$*" \
        >>"$LOG_FILE" 2>/dev/null || true
}

get_clients() {
    timeout 2 "$HYPRCTL_BIN" clients -j 2>/dev/null || true
}

game_is_running() {
    local clients

    clients="$(get_clients)"
    [[ -n "$clients" ]] || return 1

    jq -e \
        --arg regex "$GAME_CLASS_REGEX" \
        '
        any(
            .[];
            (.mapped == true)
            and
            (
                ((.contentType // "") == "game")
                or
                ((.class // "") | test($regex; "i"))
                or
                ((.initialClass // "") | test($regex; "i"))
            )
        )
        ' \
        <<<"$clients" \
        >/dev/null 2>&1
}

playerctl_available() {
    if [[ "$PLAYERCTL_BIN" == */* ]]; then
        [[ -x "$PLAYERCTL_BIN" ]]
    else
        command -v "$PLAYERCTL_BIN" >/dev/null 2>&1
    fi
}

playing_players() {
    local player status

    playerctl_available || return 1

    while IFS= read -r player; do
        [[ -n "$player" ]] || continue

        status="$(
            timeout 1 "$PLAYERCTL_BIN" \
                --player="$player" \
                status \
                2>/dev/null ||
                true
        )"

        if [[ "$status" == "Playing" ]]; then
            printf '%s\n' "${player,,}"
        fi
    done < <(
        timeout 2 "$PLAYERCTL_BIN" --list-all 2>/dev/null || true
    )
}

fullscreen_browser_is_open() {
    local clients

    clients="$(get_clients)"
    [[ -n "$clients" ]] || return 1

    jq -e \
        --arg regex "$BROWSER_CLASS_REGEX" \
        '
        def active_fullscreen:
            (.fullscreen == true)
            or
            (
                ((.fullscreen // 0) | type) == "number"
                and
                ((.fullscreen // 0) > 0)
            )
            or
            (.fullscreenClient == true)
            or
            (
                ((.fullscreenClient // 0) | type) == "number"
                and
                ((.fullscreenClient // 0) > 0)
            );

        any(
            .[];
            (.mapped == true)
            and active_fullscreen
            and
            (
                ((.class // "") | test($regex; "i"))
                or
                ((.initialClass // "") | test($regex; "i"))
            )
        )
        ' \
        <<<"$clients" \
        >/dev/null 2>&1
}

dedicated_video_player_is_open() {
    local clients

    clients="$(get_clients)"
    [[ -n "$clients" ]] || return 1

    jq -e \
        --arg regex "$VIDEO_PLAYER_CLASS_REGEX" \
        '
        any(
            .[];
            (.mapped == true)
            and
            (
                ((.class // "") | test($regex; "i"))
                or
                ((.initialClass // "") | test($regex; "i"))
            )
        )
        ' \
        <<<"$clients" \
        >/dev/null 2>&1
}

video_is_playing() {
    local players

    players="$(playing_players || true)"
    [[ -n "$players" ]] || return 1

    if grep -Eiq "$VIDEO_PLAYER_MPRIS_REGEX" <<<"$players" &&
       dedicated_video_player_is_open; then
        return 0
    fi

    if grep -Eiq "$BROWSER_MPRIS_REGEX" <<<"$players" &&
       fullscreen_browser_is_open; then
        return 0
    fi

    return 1
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
        exec "$HYPRCTL_BIN" dispatch 'hl.dsp.dpms({ action = "enable" })'
        ;;

    game-active)
        game_is_running
        exit
        ;;

    video-active)
        video_is_playing
        exit
        ;;
esac

if [[ -x "$INHIBITOR_SH" ]] &&
   "$INHIBITOR_SH" is-active >/dev/null 2>&1; then
    log "blocked timeout action: ${action:-missing}; Waybar inhibitor active"
    exit 0
fi

if game_is_running; then
    log "blocked timeout action: ${action:-missing}; game active"
    exit 0
fi

if video_is_playing; then
    log "blocked timeout action: ${action:-missing}; video playback active"
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
        exec "$HYPRCTL_BIN" dispatch 'hl.dsp.dpms({ action = "disable" })'
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
        printf 'Unknown Hypridle action: %s\n' \
            "${action:-missing}" >&2
        exit 2
        ;;
esac
