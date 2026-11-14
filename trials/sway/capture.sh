#!/usr/bin/env bash
# Sway: grim/slurp capture -> clipboard + Satty. Editing is never lock-held.
set -euo pipefail
[[ "${XDG_CURRENT_DESKTOP:-}" == sway && -n "${SWAYSOCK:-}" &&
   -n "${WAYLAND_DISPLAY:-}" ]] || {
    printf 'Capture requires an active Sway session\n' >&2; exit 1;
}
[[ $# -eq 1 ]] || { printf 'Usage: capture.sh area|window|display|output\n' >&2; exit 2; }
mode="$1"
case "$mode" in area|window|display|output) ;; *) printf 'Invalid capture mode\n' >&2; exit 2 ;; esac
for tool in grim slurp wl-copy satty flock mktemp; do
    command -v "$tool" >/dev/null 2>&1 || {
        printf 'Missing capture dependency: %s\n' "$tool" >&2; exit 127;
    }
done
if [[ "$mode" == window ]]; then
    command -v swaymsg >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 || exit 127
fi
runtime="${XDG_RUNTIME_DIR:-}"
[[ -n "$runtime" && -d "$runtime" && ! -L "$runtime" ]] || {
    printf 'Safe XDG_RUNTIME_DIR is required\n' >&2; exit 1;
}
lock_dir="$runtime/awtarchy-locks"
mkdir -p -m 0700 -- "$lock_dir"
[[ -d "$lock_dir" && ! -L "$lock_dir" ]] || exit 1

capture() {
    local geometry="" rectangles="" image="" ok=0
    flock -n 9 || {
        command -v notify-send >/dev/null 2>&1 &&
            notify-send 'Screenshot' 'Capture already running.' 9>&- || true
        return 0
    }
    case "$mode" in
        area) geometry="$(slurp -b '#ffffff20' -c '#00000040' 9>&-)" || return 1 ;;
        display|output) geometry="$(slurp -o -r -c '#00000000' 9>&-)" || return 1 ;;
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
    [[ -n "$geometry" ]] || return 1
    image="$(mktemp "$runtime/awtarchy-satty-XXXXXX.png")" || return 1
    trap 'if [[ "${ok:-0}" != 1 ]]; then rm -f -- "${image:-}"; fi' EXIT
    grim -g "$geometry" "$image" 9>&- || return 1
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
directory="$HOME/Pictures/Screenshots"
mkdir -p -- "$directory"
satty --filename "$image" \
    --output-filename "$directory/$(date +%m%d%Y-%I%p-%S).png" \
    --default-hide-toolbars
