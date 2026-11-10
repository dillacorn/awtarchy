#!/usr/bin/env bash
# Mirror Jay's native input-mode label for the shared Quickshell bar.
# Input mode switching is owned by Jay; this file never dispatches keys.
set -euo pipefail
[[ "${XDG_CURRENT_DESKTOP:-}" == jay && -n "${WAYLAND_DISPLAY:-}" ]] || {
    printf 'Jay mode-state requires Jay Wayland session\n' >&2
    exit 1
}
[[ $# -eq 1 ]] || { printf 'usage: mode-state.sh default|noalt|mouse|vm\n' >&2; exit 2; }
case "$1" in default|noalt|mouse|vm) ;; *) printf 'Invalid Jay mode\n' >&2; exit 2 ;; esac
root="${XDG_RUNTIME_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}}"
[[ -d "$root" && ! -L "$root" ]] || { printf 'Invalid runtime directory\n' >&2; exit 1; }
state="$root/awtarchy-jay-submap"
[[ ! -L "$state" ]] || { printf 'Refusing linked Jay mode state\n' >&2; exit 1; }
temp="$(mktemp "$root/.awtarchy-jay-submap.XXXXXXXX")"
trap 'rm -f -- "$temp"' EXIT
if [[ "$1" == default ]]; then
    printf '' >"$temp"
else
    printf '%s\n' "$1" >"$temp"
fi
chmod 0600 -- "$temp"
mv -f -- "$temp" "$state"
