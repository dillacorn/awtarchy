#!/usr/bin/env bash
# Sway: capture the focused display to a PNG and clipboard, or annotate selected captures.
set -euo pipefail
[[ "${XDG_CURRENT_DESKTOP:-}" == sway && -n "${SWAYSOCK:-}" &&
   -n "${WAYLAND_DISPLAY:-}" ]] || {
    printf 'Capture requires an active Sway session\n' >&2; exit 1;
}
[[ $# -eq 1 ]] || { printf 'Usage: capture.sh area|window|display|display-copy|output\n' >&2; exit 2; }
mode="$1"
case "$mode" in area|window|display|display-copy|output) ;; *) printf 'Invalid capture mode\n' >&2; exit 2 ;; esac
# The focused-display shortcut must work without slurp or Satty.
tools=(grim wl-copy flock mktemp)
if [[ "$mode" != display-copy ]]; then
    tools+=(slurp satty)
fi
if [[ "$mode" == display-copy || "$mode" == window ]]; then
    tools+=(swaymsg jq)
fi
if [[ "$mode" == display-copy ]]; then
    tools+=(cp date)
fi
for tool in "${tools[@]}"; do
    command -v "$tool" >/dev/null 2>&1 || {
        printf 'Missing capture dependency: %s\n' "$tool" >&2; exit 127;
    }
done
runtime="${XDG_RUNTIME_DIR:-}"
[[ -n "$runtime" && -d "$runtime" && ! -L "$runtime" ]] || {
    printf 'Safe XDG_RUNTIME_DIR is required\n' >&2; exit 1;
}
lock_dir="$runtime/awtarchy-locks"
mkdir -p -m 0700 -- "$lock_dir"
[[ -d "$lock_dir" && ! -L "$lock_dir" ]] || exit 1

capture() {
    local geometry="" rectangles="" focused_output="" image="" ok=0
    flock -n 9 || {
        command -v notify-send >/dev/null 2>&1 &&
            notify-send 'Screenshot' 'Capture already running.' 9>&- || true
        return 0
    }
    case "$mode" in
        area) geometry="$(slurp -b '#ffffff20' -c '#00000040' 9>&-)" || return 1 ;;
        display|output) geometry="$(slurp -o -r -c '#00000000' 9>&-)" || return 1 ;;
        display-copy)
            # The focused Sway output is authoritative, not the pointer
            # position. Missing or ambiguous focus must fail closed.
            focused_output="$(swaymsg -r -t get_outputs 9>&- | jq -er '
                if type != "array" then error("invalid outputs") else
                    [.[] | select(type == "object" and .focused == true
                                   and .active == true)
                         | .name | select(type == "string" and length > 0)] |
                    if length == 1 then .[0]
                    else error("expected exactly one focused active output") end
                end
            ')" || {
                printf 'Cannot determine the focused active Sway display\n' >&2
                return 1
            }
            ;;
        window)
            rectangles="$(swaymsg -r -t get_tree 9>&- | jq -r '
                .. | objects
                | select(.type? == "con" and (.visible? == true))
                | select((.app_id? // "") != "" or .window? != null)
                | select((.rect.width? // 0) > 1 and (.rect.height? // 0) > 1)
                | "\(.rect.x),\(.rect.y) \(.rect.width)x\(.rect.height) \((.name // "Window") | gsub("[\r\n]"; " "))"
            ')" || return 1
            [[ -n "$rectangles" ]] || {
                printf 'No visible application windows to capture\n' >&2
                return 1
            }
            geometry="$(printf '%s\n' "$rectangles" |
                slurp -r -f '%x,%y %wx%h' -b '#ffffff20' -c '#00000040' 9>&-)" || return 1 ;;
    esac
    [[ -n "$geometry" || -n "$focused_output" ]] || return 1
    image="$(mktemp "$runtime/awtarchy-satty-XXXXXX.png")" || return 1
    trap 'if [[ "${ok:-0}" != 1 ]]; then rm -f -- "${image:-}"; fi' EXIT
    if [[ -n "$focused_output" ]]; then
        grim -o "$focused_output" "$image" 9>&- || return 1
    else
        grim -g "$geometry" "$image" 9>&- || return 1
    fi
    # wl-copy forks a long-lived clipboard provider. Never let it inherit
    # the capture flock descriptor, or later screenshots report lock-busy.
    wl-copy --type image/png < "$image" 9>&- || return 1
    ok=1
    printf '%s\n' "$image"
}

# Only the child capture command owns descriptor 9. Satty does not inherit it.
if ! image="$(capture 9>"$lock_dir/sway-screenshot.lock")"; then
    printf 'Sway screenshot capture failed or was canceled\n' >&2
    exit 1
fi
[[ -n "$image" ]] || exit 0
[[ -f "$image" && ! -L "$image" ]] || exit 1
trap 'rm -f -- "$image"' EXIT
# Super+Shift+D captures the focused output, copies it to the clipboard
# (above) AND saves a unique PNG without asking for a display or Satty.
directory="$HOME/Pictures/Screenshots"
if [[ "$mode" == display-copy ]]; then
    mkdir -p -- "$directory"
    [[ -d "$directory" && ! -L "$directory" ]] || {
        printf 'Unsafe screenshots directory: %s\n' "$directory" >&2
        exit 1
    }
    saved="$(mktemp "$directory/Screenshot-$(date +%Y-%m-%d_%H-%M-%S)-XXXXXXXX.png")" || exit 1
    if ! cp -- "$image" "$saved"; then
        rm -f -- "$saved"
        printf 'Failed to save screenshot: %s\n' "$saved" >&2
        exit 1
    fi
    printf 'Saved screenshot and copied to clipboard: %s\n' "$saved"
    exit 0
fi
mkdir -p -- "$directory"
satty --filename "$image" \
    --output-filename "$directory/$(date +%m%d%Y-%I%p-%S).png" \
    --default-hide-toolbars
