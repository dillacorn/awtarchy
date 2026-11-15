#!/usr/bin/env bash
# Mirror Sway's native input-mode label for the shared Quickshell bar.
# Input mode switching is owned by Sway; this file never dispatches keys.
set -euo pipefail
[[ "${XDG_CURRENT_DESKTOP:-}" == sway && -n "${WAYLAND_DISPLAY:-}" ]] || {
    printf 'Sway mode-state requires Sway Wayland session\n' >&2
    exit 1
}
[[ $# -eq 1 ]] || { printf 'usage: mode-state.sh sync|default|noalt|mouse|vm\n' >&2; exit 2; }
mode="$1"
if [[ "$mode" == sync ]]; then
    [[ -n "${SWAYSOCK:-}" ]] || { printf 'Missing Sway socket\n' >&2; exit 1; }
    mode="$(swaymsg -r -t get_binding_state | jq -er '.name | select(type == "string")')"
fi
case "$mode" in default|noalt|mouse|vm) ;; *) printf 'Invalid Sway mode\n' >&2; exit 2 ;; esac
root="${XDG_RUNTIME_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}}"
[[ -d "$root" && ! -L "$root" ]] || { printf 'Invalid runtime directory\n' >&2; exit 1; }
state="$root/awtarchy-sway-submap"
[[ ! -L "$state" ]] || { printf 'Refusing linked Sway mode state\n' >&2; exit 1; }
temp="$(mktemp "$root/.awtarchy-sway-submap.XXXXXXXX")"
trap 'rm -f -- "$temp"' EXIT
if [[ "$mode" == default ]]; then
    printf '' >"$temp"
else
    printf '%s\n' "$mode" >"$temp"
fi
chmod 0600 -- "$temp"
mv -f -- "$temp" "$state"
