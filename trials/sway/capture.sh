#!/usr/bin/env bash
# Screen capture within an active Sway session; clipboard only.
set -euo pipefail
[[ "${XDG_CURRENT_DESKTOP:-}" == sway && -n "${WAYLAND_DISPLAY:-}" ]] || {
    printf 'Sway session required\n' >&2; exit 1;
}
for pkg in grim wl-copy; do command -v "$pkg" >/dev/null 2>&1 || {
    printf 'Required utility missing: %s\n' "$pkg" >&2; exit 127;
}; done
case "${1:-}" in
    output)
        [[ $# -eq 1 ]] || exit 2
        grim - | wl-copy --type image/png ;;
    area)
        [[ $# -eq 1 ]] || exit 2
        command -v slurp >/dev/null 2>&1 || exit 127
        selection="$(slurp)" || exit 1
        [[ -n "$selection" ]] || exit 1
        grim -g "$selection" - | wl-copy --type image/png ;;
    *) printf 'usage: capture.sh output|area\n' >&2; exit 2 ;;
esac
