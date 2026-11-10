#!/usr/bin/env bash
# Spawned by a Jay privileged shortcut (Wayland screencopy privilege).
set -euo pipefail
[[ "${XDG_CURRENT_DESKTOP:-}" == jay && -n "${WAYLAND_DISPLAY:-}" ]] || {
    printf 'Jay session required\n' >&2
    exit 1
}
command -v grim >/dev/null && command -v wl-copy >/dev/null || {
    printf 'grim and wl-copy are required\n' >&2
    exit 1
}
case "${1:-}" in
    output) [[ $# -eq 1 ]] || exit 2; grim - | wl-copy --type image/png ;;
    area)
        [[ $# -eq 1 ]] || exit 2
        command -v slurp >/dev/null || exit 127
        geometry="$(slurp)" || exit 1
        [[ -n "$geometry" ]] || exit 1
        grim -g "$geometry" - | wl-copy --type image/png
        ;;
    *) printf 'usage: capture.sh area|output\n' >&2; exit 2 ;;
esac
