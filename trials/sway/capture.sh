#!/usr/bin/env bash
# Sway screenshots: grim/slurp -> clipboard + Satty annotation editor.
# A capture lock protects selection/capture, not the editor's lifetime.
set -euo pipefail
[[ "${XDG_CURRENT_DESKTOP:-}" == sway && -n "${SWAYSOCK:-}" && -n "${WAYLAND_DISPLAY:-}" ]] || {
    printf 'Capture requires active Sway session\n' >&2; exit 1;
}
[[ $# == 1 ]] || { printf 'Usage: capture.sh area|window|display|output\n' >&2; exit 2; }
mode="$1"
case "$mode" in area|window|display|output) ;; *) printf 'Invalid capture mode\n' >&2; exit 2 ;; esac
for tool in grim slurp wl-copy satty flock mktemp; do
    command -v "$tool" >/dev/null 2>&1 || {
        printf 'Missing capture dependency: %s\n' "$tool" >&2; exit 127;
    }
done
if [[ "$mode" == window ]]; then
    for tool in swaymsg jq; do
        command -v "$tool" >/dev/null 2>&1 || exit 127
    done
fi
runtime="${XDG_RUNTIME_DIR:-}"
[[ -d "$runtime" && ! -L "$runtime" ]] || {
    printf 'Safe XDG_RUNTIME_DIR required\n' >&2; exit 1;
}
lock_dir="$runtime/awtarchy-locks"
mkdir -p -m 0700 -- "$lock_dir"
[[ -d "$lock_dir" && ! -L "$lock_dir" ]] || exit 1

# Open the lock in a child subshell so the Satty editor never owns its fd.
(
    flock -n 9 || {
        if command -v notify-send >/dev/null 2>&1; then
            notify-send 'Screenshot' 'Capture already in progress.' || true
        fi
        return 0
    }
    case "$mode" in
        area) geometry="$(slurp -b '#ffffff20' -c '#00000040')" || return 1 ;;
        display|output) geometry="$(slurp -o -r -c '#00000000')" || return 1 ;;
        window)
            rectangles="$(swaymsg -r -t get_tree | jq -r '
                .. | objects
                | select(.type? == "con" and (.visible? == true))
                | select((.app_id? // "") != "" or .window? != null)
                | select((.rect.width? // 0) > 1 and (.rect.height? // 0) > 1)
                | "\(.rect.x),\(.rect.y) \(.rect.width)x\(.rect.height) \((.name // "Window") | gsub("[\r\n]"; " "))"
            ')" || return 1
            [[ -n "$rectangles" ]] || {
                printf 'No visible windows to capture\n' >&2; return 1;
            }
            geometry="$(printf '%s\n' "$rectangles" | slurp -r -f '%x,%y %wx%h' -b '#ffffff20' -c '#00000040')" || return 1 ;;
    esac
    [[ -n "$geometry" ]] || return 1
    image="$(mktemp "$runtime/awtarchy-satty-XXXXXX.png")"
    # Keep image path in a separate restricted file so the parent can read it;
    # avoid a subshell variable that disappears when the capture finishes.
    path_file="$(mktemp "$runtime/awtarchy-satty-path-XXXXXX")"
    trap 'rm -f -- "${path_file:-}" "${image:-}"' RETURN
    grim -g "$geometry" "$image" || return 1
    wl-copy --type image/png < "$image" || return 1
    printf '%s\n' "$image" > "$path_file"
    # Parent receives this path via stdout once clipboard copy succeeds.
    printf '%s\n' "$image"
    trap - RETURN
    rm -f -- "$path_file"
) 9>"$lock_dir/sway-screenshot.lock" > "$runtime/awtarchy-satty-last-path-$$"
rc=$?
if (( rc != 0 )); then
    rm -f -- "$runtime/awtarchy-satty-last-path-$$"
    exit "$rc"
fi
image="$(<"$runtime/awtarchy-satty-last-path-$$")"
rm -f -- "$runtime/awtarchy-satty-last-path-$$"
[[ -f "$image" && ! -L "$image" ]] || exit 1
trap 'rm -f -- "$image"' EXIT
out_dir="$HOME/Pictures/Screenshots"
mkdir -p -- "$out_dir"
satty --filename "$image" \
    --output-filename "$out_dir/$(date +%m%d%Y-%I%p-%S).png" \
    --default-hide-toolbars
