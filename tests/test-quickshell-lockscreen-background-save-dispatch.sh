#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STATE="${ROOT}/config/hypr/scripts/quickshell_application_state.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

layout='{"logo":{"x":0.5,"y":0.34,"scale":1,"color":"auto"},"time":{"x":0.5,"y":0.51,"scale":1,"color":"auto"},"date":{"x":0.5,"y":0.555,"scale":1,"color":"auto"},"username":{"x":0.5,"y":0.595,"scale":1,"color":"auto"},"weather":{"x":0.5,"y":0.635,"scale":1,"color":"auto"},"password":{"x":0.5,"y":0.7,"scale":1,"color":"auto"}}'
visibility='{"logo":true,"time":false,"date":false,"username":false,"weather":false,"password":true}'

mkdir -p "$TMP/cache/awtarchy" "$TMP/home"
printf '%s\n' '{"enabled":true,"monitors":{},"launcher_sizes":{},"update_notifications_enabled":true}' \
    >"$TMP/cache/awtarchy/quickshell-state.json"

XDG_CACHE_HOME="$TMP/cache" HOME="$TMP/home" HYPR_QUICKSHELL_SCRIPT=/bin/false \
    bash "$STATE" save-lockscreen-editor \
    "$layout" "$visibility" black '#000000' '' \
    contain 0.25 0.75 dark 40 20 \
    || fail 'expanded lockscreen editor save was rejected by command dispatch'

jq -e '
    .lockscreen_wallpaper_fit == "contain"
    and .lockscreen_wallpaper_focal_x == 0.25
    and .lockscreen_wallpaper_focal_y == 0.75
    and .lockscreen_overlay_mode == "dark"
    and .lockscreen_overlay_strength == 40
    and .lockscreen_wallpaper_blur == 20
' "$TMP/cache/awtarchy/quickshell-state.json" >/dev/null \
    || fail 'expanded lockscreen editor save did not persist composition fields'

printf '%s\n' 'PASS: lockscreen background composition save dispatch'
