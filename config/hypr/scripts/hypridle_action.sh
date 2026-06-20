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

OBS_LOG_FILE_OVERRIDE="${OBS_LOG_FILE_OVERRIDE:-}"
OBS_PROCESS_REQUIRED="${OBS_PROCESS_REQUIRED:-1}"

# Keep synchronized with the game classes in hyprland.lua.
GAME_CLASS_REGEX='^(steam_app_.*|lutris_game_class|minigalaxy|playnite_game_class|gamescope|chiaki|moonlight|com\.moonlight_stream\.Moonlight|.*\.exe)$'

BROWSER_CLASS_REGEX='^(firefox|org\.mozilla\.firefox|firefoxdeveloperedition|librewolf|floorp|zen|zen-browser|chromium|chromium-browser|org\.chromium\.Chromium|google-chrome.*|brave-browser.*|com\.brave\.Browser|vivaldi.*|microsoft-edge.*)$'
BROWSER_MPRIS_REGEX='^(firefox|librewolf|floorp|zen|chromium|google-chrome|chrome|brave|vivaldi|microsoft-edge|edge)([._-]|$)'

VIDEO_PLAYER_CLASS_REGEX='^(mpv|vlc|org\.videolan\.VLC|celluloid|io\.github\.celluloid_player\.Celluloid|haruna|org\.kde\.haruna|smplayer|totem|org\.gnome\.Totem|clapper|com\.github\.rafostar\.Clapper|stremio|com\.stremio\.Stremio|jellyfin-media-player|com\.github\.iwalton3\.jellyfin-media-player|freetube|io\.freetubeapp\.FreeTube)$'
VIDEO_PLAYER_MPRIS_REGEX='(mpv|vlc|celluloid|haruna|smplayer|totem|clapper|stremio|jellyfin|freetube)'

# Music and audio-only playback must not block normal idling.
AUDIO_PLAYER_MPRIS_REGEX='^(spotify|ncspot|cider|amberol|rhythmbox|lollypop|audacious|strawberry|elisa|tauon|deadbeef|cmus|musikcube)([._-]|$)'
AUDIO_URL_REGEX='(music\.youtube\.com|open\.spotify\.com|soundcloud\.com|music\.apple\.com|tidal\.com|bandcamp\.com|deezer\.com|pandora\.com|music\.amazon\.)|\.(mp3|flac|ogg|oga|opus|m4a|aac|wav|wma)([?#]|$)'
AUDIO_TITLE_REGEX='(spotify|soundcloud|youtube music|apple music|bandcamp|tidal|deezer|pandora|amazon music)'

mkdir -p "$(dirname "$LOG_FILE")"

log() {
    printf '%s %s\n' \
        "$(date '+%F %T')" \
        "$*" \
        >>"$LOG_FILE" 2>/dev/null || true
}

playerctl_available() {
    if [[ "$PLAYERCTL_BIN" == */* ]]; then
        [[ -x "$PLAYERCTL_BIN" ]]
    else
        command -v "$PLAYERCTL_BIN" >/dev/null 2>&1
    fi
}

get_clients() {
    timeout 2 "$HYPRCTL_BIN" clients -j 2>/dev/null || true
}


focused_workspace_id() {
    timeout 2 "$HYPRCTL_BIN" activeworkspace -j 2>/dev/null |
        jq -r '.id // empty' 2>/dev/null ||
        true
}

visible_workspaces_json() {
    local monitors

    monitors="$(
        timeout 2 "$HYPRCTL_BIN" monitors -j 2>/dev/null ||
            true
    )"

    if [[ -z "$monitors" ]]; then
        printf '%s\n' '[]'
        return 1
    fi

    jq -c '
        [
            .[]
            |
            (.activeWorkspace.id // empty),
            (
                .specialWorkspace.id
                // .activeSpecialWorkspace.id
                // empty
            )
        ]
        | map(
            select(
                type == "number"
                and . != 0
            )
        )
        | unique
    ' <<<"$monitors" 2>/dev/null || {
        printf '%s\n' '[]'
        return 1
    }
}

visible_workspace_ids() {
    visible_workspaces_json |
        jq -r '.[]' 2>/dev/null ||
        true
}

player_status() {
    local player="$1"

    timeout 1 "$PLAYERCTL_BIN" \
        --player="$player" \
        status \
        2>/dev/null ||
        true
}

player_metadata() {
    local player="$1"
    local separator=$'\x1f'
    local format

    format="{{xesam:title}}${separator}{{xesam:url}}${separator}{{xesam:album}}${separator}{{xesam:artist}}"

    timeout 1 "$PLAYERCTL_BIN" \
        --player="$player" \
        metadata \
        --format "$format" \
        2>/dev/null ||
        true
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


obs_pids() {
    {
        pgrep -u "$(id -u)" -x obs 2>/dev/null || true
        pgrep -u "$(id -u)" -x obs-studio 2>/dev/null || true
    } |
        awk '/^[0-9]+$/ && !seen[$0]++'
}

obs_process_is_running() {
    obs_pids | grep -qE '^[0-9]+$'
}

obs_current_log() {
    local pid fd target
    local directory file modified
    local newest=""
    local newest_modified=-1

    if [[ -n "$OBS_LOG_FILE_OVERRIDE" ]]; then
        [[ -r "$OBS_LOG_FILE_OVERRIDE" ]] || return 1
        printf '%s\n' "$OBS_LOG_FILE_OVERRIDE"
        return 0
    fi

    while IFS= read -r pid; do
        [[ "$pid" =~ ^[0-9]+$ ]] || continue

        for fd in "/proc/${pid}/fd/"*; do
            target="$(
                readlink -f -- "$fd" 2>/dev/null ||
                    true
            )"

            case "$target" in
                */obs-studio/logs/*.txt)
                    if [[ -r "$target" ]]; then
                        printf '%s\n' "$target"
                        return 0
                    fi
                    ;;
            esac
        done
    done < <(obs_pids)

    for directory in \
        "$HOME/.config/obs-studio/logs" \
        "$HOME/.var/app/com.obsproject.Studio/config/obs-studio/logs"
    do
        [[ -d "$directory" ]] || continue

        shopt -s nullglob

        for file in "$directory"/*.txt; do
            modified="$(
                stat -c '%Y' -- "$file" 2>/dev/null ||
                    printf '%s' -1
            )"

            [[ "$modified" =~ ^[0-9]+$ ]] || continue

            if (( modified > newest_modified )); then
                newest="$file"
                newest_modified="$modified"
            fi
        done
    done

    [[ -n "$newest" && -r "$newest" ]] || return 1
    printf '%s\n' "$newest"
}

obs_output_states() {
    local log_file

    if [[ "$OBS_PROCESS_REQUIRED" != "0" ]] &&
       ! obs_process_is_running
    then
        return 1
    fi

    log_file="$(obs_current_log)" || return 1

    awk '
        /==== Recording Start/ {
            recording = 1
        }

        /==== Recording Stop/ {
            recording = 0
        }

        /==== Streaming Start/ {
            streaming = 1
        }

        /==== Streaming Stop/ {
            streaming = 0
        }

        /User stopped the stream/ {
            streaming = 0
        }

        /streaming stop requested/ {
            streaming = 0
        }

        /Output '\''[^'\'']*stream[^'\'']*'\'': stopping/ {
            streaming = 0
        }

        /==== Replay Buffer Start/ {
            replay = 1
        }

        /==== Replay Buffer Stop/ {
            replay = 0
        }

        /Starting Virtual Camera output/ {
            virtual_camera = 1
        }

        /starting virtual-output/ {
            virtual_camera = 1
        }

        /Failed to start virtual camera/ {
            virtual_camera = 0
        }

        /Output '\''virtualcam_output'\'': stopping/ {
            virtual_camera = 0
        }

        /virtual-output stop/ {
            virtual_camera = 0
        }

        END {
            separator = ""

            if (recording) {
                printf "%srecording", separator
                separator = ","
            }

            if (streaming) {
                printf "%sstreaming", separator
                separator = ","
            }

            if (replay) {
                printf "%sreplay-buffer", separator
                separator = ","
            }

            if (virtual_camera) {
                printf "%svirtual-camera", separator
                separator = ","
            }

            if (separator != "") {
                printf "\n"
            }
        }
    ' "$log_file"
}

obs_output_is_active() {
    local states

    states="$(
        obs_output_states 2>/dev/null ||
            true
    )"

    [[ -n "$states" ]]
}

obs_diagnose() {
    local log_file states

    printf '%s\n' 'obs_processes:'

    if ! obs_pids |
        while IFS= read -r pid; do
            ps -o pid=,comm=,args= -p "$pid"
        done
    then
        true
    fi

    if ! obs_process_is_running; then
        printf '%s\n' '  none'
    fi

    log_file="$(
        obs_current_log 2>/dev/null ||
            true
    )"

    printf 'current_log=%s\n' "${log_file:-none}"

    states="$(
        obs_output_states 2>/dev/null ||
            true
    )"

    printf 'active_outputs=%s\n' "${states:-none}"

    if [[ -n "$states" ]]; then
        printf '%s\n' 'obs_output_active=yes'
    else
        printf '%s\n' 'obs_output_active=no'
    fi

    if [[ -n "$log_file" && -r "$log_file" ]]; then
        printf '\n%s\n' 'recent_output_events:'

        grep -E \
            '==== (Recording|Streaming|Replay Buffer) (Start|Stop)|User stopped the stream|streaming stop requested|Starting Virtual Camera output|starting virtual-output|Failed to start virtual camera|virtualcam_output.*stopping|virtual-output stop' \
            "$log_file" |
            tail -n 20 ||
            true
    fi
}

media_is_audio_only() {
    local player="${1,,}"
    local title="${2,,}"
    local url="${3,,}"
    local album="$4"

    [[ "$player" =~ $AUDIO_PLAYER_MPRIS_REGEX ]] &&
        return 0

    [[ "$url" =~ $AUDIO_URL_REGEX ]] &&
        return 0

    [[ "$title" =~ $AUDIO_TITLE_REGEX ]] &&
        return 0

    # Album metadata is treated as a strong music signal.
    [[ -n "${album//[[:space:]]/}" ]] &&
        return 0

    return 1
}


browser_video_on_visible_workspace() {
    local media_title="$1"
    local visible clients

    [[ ${#media_title} -ge 4 ]] || return 1

    visible="$(visible_workspaces_json)"
    clients="$(get_clients)"

    [[ "$visible" != "[]" ]] || return 1
    [[ -n "$clients" ]] || return 1

    jq -e \
        --argjson visible "$visible" \
        --arg regex "$BROWSER_CLASS_REGEX" \
        --arg media_title "$media_title" \
        '
        ($media_title | ascii_downcase) as $needle
        |
        any(
            .[];
            (.mapped == true)
            and
            (
                (.workspace.id // -999999) as $workspace_id
                |
                ($visible | index($workspace_id)) != null
            )
            and
            (
                ((.class // "") | test($regex; "i"))
                or
                ((.initialClass // "") | test($regex; "i"))
            )
            and
            (
                (.title // "")
                | ascii_downcase
                | contains($needle)
            )
        )
        ' \
        <<<"$clients" \
        >/dev/null 2>&1
}


dedicated_video_on_visible_workspace() {
    local visible clients

    visible="$(visible_workspaces_json)"
    clients="$(get_clients)"

    [[ "$visible" != "[]" ]] || return 1
    [[ -n "$clients" ]] || return 1

    jq -e \
        --argjson visible "$visible" \
        --arg regex "$VIDEO_PLAYER_CLASS_REGEX" \
        '
        any(
            .[];
            (.mapped == true)
            and
            (
                (.workspace.id // -999999) as $workspace_id
                |
                ($visible | index($workspace_id)) != null
            )
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
    local player status metadata
    local title url album artist
    local separator=$'\x1f'
    local player_lower

    playerctl_available || return 1

    while IFS= read -r player; do
        [[ -n "$player" ]] || continue

        status="$(player_status "$player")"
        [[ "$status" == "Playing" ]] || continue

        metadata="$(player_metadata "$player")"

        title=""
        url=""
        album=""
        artist=""

        IFS="$separator" read -r title url album artist <<<"$metadata"

        if media_is_audio_only \
            "$player" \
            "$title" \
            "$url" \
            "$album"
        then
            continue
        fi

        player_lower="${player,,}"

        if [[ "$player_lower" =~ $VIDEO_PLAYER_MPRIS_REGEX ]] &&
           dedicated_video_on_visible_workspace
        then
            return 0
        fi

        if [[ "$player_lower" =~ $BROWSER_MPRIS_REGEX ]] &&
           browser_video_on_visible_workspace "$title"
        then
            return 0
        fi
    done < <(
        timeout 2 "$PLAYERCTL_BIN" --list-all 2>/dev/null ||
            true
    )

    return 1
}

video_diagnose() {
    local player status metadata
    local title url album artist
    local separator=$'\x1f'
    local classification

    printf 'focused_workspace=%s\n' \
        "$(focused_workspace_id || printf unknown)"

    printf 'visible_workspaces=%s\n' \
        "$(visible_workspaces_json |
            jq -r '
                if length == 0 then
                    "none"
                else
                    map(tostring) | join(",")
                end
            ' 2>/dev/null || printf unknown)"

    printf '\n%s\n' 'relevant_windows:'

    get_clients |
        jq -r \
            --arg browser "$BROWSER_CLASS_REGEX" \
            --arg video "$VIDEO_PLAYER_CLASS_REGEX" \
            '
            .[]
            | select(
                ((.class // "") | test($browser; "i"))
                or
                ((.initialClass // "") | test($browser; "i"))
                or
                ((.class // "") | test($video; "i"))
                or
                ((.initialClass // "") | test($video; "i"))
            )
            |
            "class=\(.class) workspace=\(.workspace.id) mapped=\(.mapped) fullscreen=\(.fullscreen // "missing") title=\(.title)"
            ' \
            2>/dev/null ||
        true

    printf '\n%s\n' 'mpris_players:'

    while IFS= read -r player; do
        [[ -n "$player" ]] || continue

        status="$(player_status "$player")"
        metadata="$(player_metadata "$player")"

        title=""
        url=""
        album=""
        artist=""

        IFS="$separator" read -r title url album artist <<<"$metadata"

        if media_is_audio_only \
            "$player" \
            "$title" \
            "$url" \
            "$album"
        then
            classification="audio-only"
        else
            classification="possible-video"
        fi

        printf 'player=%s\n' "$player"
        printf '  status=%s\n' "${status:-unknown}"
        printf '  classification=%s\n' "$classification"
        printf '  title=%s\n' "${title:-none}"
        printf '  url=%s\n' "${url:-none}"
        printf '  album=%s\n' "${album:-none}"
        printf '  artist=%s\n' "${artist:-none}"
    done < <(
        timeout 2 "$PLAYERCTL_BIN" --list-all 2>/dev/null ||
            true
    )

    printf '\nvideo_active=%s\n' \
        "$(video_is_playing && printf yes || printf no)"
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

    video-diagnose)
        video_diagnose
        exit
        ;;

    obs-active)
        obs_output_is_active
        exit
        ;;

    obs-diagnose)
        obs_diagnose
        exit
        ;;
esac

if [[ -x "$INHIBITOR_SH" ]] &&
   "$INHIBITOR_SH" is-active >/dev/null 2>&1; then
    log "blocked timeout action: ${action:-missing}; Waybar inhibitor active"
    exit 0
fi

if obs_output_is_active; then
    log "blocked timeout action: ${action:-missing}; OBS output active: $(obs_output_states || printf unknown)"
    exit 0
fi

if game_is_running; then
    log "blocked timeout action: ${action:-missing}; game active"
    exit 0
fi

if video_is_playing; then
    log "blocked timeout action: ${action:-missing}; visible video playback active"
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
