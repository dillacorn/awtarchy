#!/usr/bin/env bash
# Control native Sway modes; update the UI only after IPC confirms the mode.
set -euo pipefail
[[ "${XDG_CURRENT_DESKTOP:-}" == sway && -n "${SWAYSOCK:-}" &&
   -n "${WAYLAND_DISPLAY:-}" ]] || {
    printf 'Active Sway session required\n' >&2
    exit 1
}
case "$*" in
    "toggle noalt"|"toggle mouse"|"toggle vm"|"reset") ;;
    *) printf 'Usage: mode-control.sh toggle noalt|mouse|vm OR reset\n' >&2; exit 2 ;;
esac
mode_now() {
    swaymsg -r -t get_binding_state | jq -er '.name | select(type == "string")'
}
current="$(mode_now)"
case "$current" in default|noalt|mouse|vm) ;; *)
    printf 'Unrecognized Sway mode: %s\n' "$current" >&2; exit 1 ;;
esac
target=default
if [[ "$1" == toggle && "$current" != "$2" ]]; then target="$2"; fi
if [[ "$target" != "$current" ]]; then
    response="$(swaymsg -r -t command "mode \"$target\"")" || {
        printf 'Sway mode command failed\n' >&2; exit 1;
    }
    jq -e 'type == "array" and length > 0 and all(.[]; .success == true)' \
        >/dev/null <<< "$response" || {
        printf 'Sway refused mode change\n' >&2; exit 1;
    }
fi
[[ "$(mode_now)" == "$target" ]] || {
    printf 'Sway did not confirm the requested mode\n' >&2; exit 1;
}
bash "${XDG_CONFIG_HOME:-$HOME/.config}/sway/awtarchy-trial/mode-state.sh" sync
if [[ "$current" != "$target" ]] && command -v notify-send >/dev/null 2>&1; then
    if [[ "$target" == default ]]; then
        label="$current submap: OFF"
    else
        label="$target submap: ON"
    fi
    notify-send -a Awtarchy -h boolean:transient:true -t 1000 "$label" >/dev/null 2>&1 || true
fi
