#!/usr/bin/env bash
# Toggle the active Umbriel compositor animation switch. No persistent edits.
set -euo pipefail
[[ "${XDG_CURRENT_DESKTOP,,}" == umbriel && -n "${WAYLAND_DISPLAY:-}" ]] || {
    printf 'Umbriel graphical session required\n' >&2
    false
}
command -v umbriel >/dev/null 2>&1 || {
    printf 'Missing umbriel\n' >&2
    false
}
[[ $# -eq 0 ]] || { printf 'Usage: animations.sh\n' >&2; false; }
current="$(umbriel config get animation.enabled)" || false
case "$current" in
    true) target=false; label=OFF ;;
    false) target=true; label=ON ;;
    *) printf 'Invalid compositor animation state: %s\n' "$current" >&2; false ;;
esac
umbriel config set animation.enabled "$target" || false
[[ "$(umbriel config get animation.enabled)" == "$target" ]] || {
    printf 'Umbriel did not confirm animation change\n' >&2
    false
}
command -v notify-send >/dev/null 2>&1 &&
    notify-send -a Umbriel -t 1200 "Animations: $label" || true
