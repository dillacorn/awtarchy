#!/usr/bin/env bash
# Umbriel capture parity: region/window/output with Satty, or focused-output copy.
# Never call Hyprland-only hyprpicker or Sway IPC.
set -euo pipefail

[[ "${XDG_CURRENT_DESKTOP,,}" == umbriel && -n "${WAYLAND_DISPLAY:-}" ]] || {
    printf 'Capture requires an active Umbriel session\n' >&2
    exit 1
}
[[ $# -eq 1 ]] || { printf 'Usage: capture.sh area|window|display|display-copy\n' >&2; exit 2; }
mode="$1"
case "$mode" in
    area|window|display|display-copy) ;;
    *) printf 'Unknown capture mode\n' >&2; exit 2 ;;
esac

tools=(grim wl-copy flock mktemp)
if [[ "$mode" != display-copy ]]; then
    tools+=(slurp satty)
fi
if [[ "$mode" == display-copy || "$mode" == window ]]; then
    tools+=(umbriel jq)
fi
for tool in "${tools[@]}"; do
    command -v "$tool" >/dev/null 2>&1 || {
        printf 'Missing capture dependency: %s\n' "$tool" >&2
        exit 127
    }
done

runtime="${XDG_RUNTIME_DIR:-}"
[[ -n "$runtime" && -d "$runtime" && ! -L "$runtime" && -O "$runtime" ]] || {
    printf 'A private XDG_RUNTIME_DIR is required\n' >&2
    exit 1
}
lock_dir="$runtime/awtarchy-locks"
mkdir -p -m 0700 -- "$lock_dir"
[[ -d "$lock_dir" && ! -L "$lock_dir" && -O "$lock_dir" ]] || exit 1
[[ ! -L "$lock_dir/umbriel-screenshot.lock" ]] || exit 1

capture() {
    local geometry="" rectangles="" focused_output="" image="" ok=0
    trap 'if [[ "${ok:-0}" != 1 && -n "${image:-}" ]]; then rm -f -- "$image"; fi' EXIT

    if [[ "$mode" == display-copy ]]; then
        flock -w 5 9 || {
            printf 'Screenshot queue timed out\n' >&2
            return 1
        }
    else
        flock -n 9 || {
            command -v notify-send >/dev/null 2>&1 &&
                notify-send 'Screenshot' 'Capture already running.' 9>&- || true
            return 0
        }
    fi

    case "$mode" in
        area)
            geometry="$(slurp -b '#ffffff20' -c '#00000040' 9>&-)" || return 1
            ;;
        display)
            geometry="$(slurp -o -r -c '#00000000' 9>&-)" || return 1
            ;;
        display-copy)
            focused_output="$(umbriel outputs --json 9>&- | jq -er '
                (if type == "array" then . else .ok end) as $outputs
                | if ($outputs | type) != "array" then
                    error("invalid Umbriel output response")
                  else
                    [$outputs[] | select(.focused == true and .enabled == true)
                     | .name | select(type == "string" and length > 0)]
                    | if length == 1 then .[0]
                      else error("expected exactly one focused output") end
                  end
            ')" || {
                printf 'Cannot identify the focused Umbriel output\n' >&2
                return 1
            }
            ;;
        window)
            rectangles="$(umbriel windows --json 9>&- | jq -r '
                (if type == "array" then . else .ok end) as $windows
                | if ($windows | type) != "array" then
                    error("invalid Umbriel window response")
                  else
                    $windows[]
                    | select(.visible == true and .tab_hidden != true and .minimized != true)
                    | select((.app_id // "") != "")
                    | (.width // .w // 0) as $width
                    | (.height // .h // 0) as $height
                    | select((.x | type) == "number" and (.y | type) == "number"
                             and ($width | type) == "number"
                             and ($height | type) == "number"
                             and $width > 1 and $height > 1)
                    | "\\(.x | floor),\\(.y | floor) \\($width | floor)x\\($height | floor) \\((.title // .app_id) | gsub("[\\r\\n]"; " "))"
                  end
            ')" || return 1
            [[ -n "$rectangles" ]] || {
                printf 'No visible Umbriel application windows\n' >&2
                return 1
            }
            geometry="$(printf '%s\n' "$rectangles" |
                slurp -r -f '%x,%y %wx%h' -b '#ffffff20' -c '#00000040' 9>&-)" || return 1
            ;;
    esac
    [[ -n "$geometry" || -n "$focused_output" ]] || return 1
    image="$(mktemp "$runtime/awtarchy-umbriel-shot-XXXXXXXX.png")" || return 1
    if [[ -n "$focused_output" ]]; then
        grim -o "$focused_output" "$image" 9>&- || return 1
    else
        grim -g "$geometry" "$image" 9>&- || return 1
    fi
    sound="$HOME/.config/hypr/scripts/screenshot_sound.sh"
    if [[ -f "$sound" && ! -L "$sound" ]]; then
        style=satty
        [[ "$mode" == display-copy ]] && style=direct
        bash "$sound" play "$style" 9>&- >/dev/null 2>&1 || true
    fi
    wl-copy --type image/png < "$image" 9>&- || return 1
    ok=1
    printf '%s\n' "$image"
}
if ! image="$(capture 9>"$lock_dir/umbriel-screenshot.lock")"; then
    printf 'Umbriel screenshot capture failed or was canceled\n' >&2
    exit 1
fi
[[ -n "$image" ]] || exit 0
[[ -f "$image" && ! -L "$image" ]] || exit 1
trap 'rm -f -- "$image"' EXIT
directory="$HOME/Pictures/Screenshots"
mkdir -p -- "$directory"
[[ -d "$directory" && ! -L "$directory" && -O "$directory" ]] || {
    printf 'Unsafe screenshot directory\n' >&2
    exit 1
}

if [[ "$mode" == display-copy ]]; then
    saved="$(mktemp "$directory/Screenshot-$(date +%Y-%m-%d_%H-%M-%S)-XXXXXXXX.png")" || exit 1
    if ! cp -- "$image" "$saved"; then
        rm -f -- "$saved"
        exit 1
    fi
    printf 'Saved and copied: %s\n' "$saved"
else
    if [[ "$mode" == display ]]; then
        satty --filename "$image" --fullscreen \
            --output-filename "$directory/$(date +%m%d%Y-%I%p-%S).png"
    else
        satty --filename "$image" --default-hide-toolbars \
            --output-filename "$directory/$(date +%m%d%Y-%I%p-%S).png"
    fi
fi
