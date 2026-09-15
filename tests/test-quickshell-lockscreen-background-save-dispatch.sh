#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STATE="${ROOT}/config/hypr/scripts/quickshell_application_state.sh"
EDITOR_SAVE="${ROOT}/config/hypr/scripts/quickshell_lockscreen_editor_save.sh"
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

# Exercise the exact editor-save wrapper with the current extension fields.  A
# successful save has a machine-readable success response so QML can distinguish
# an atomic committed save from a helper that died after partial processing.
mkdir -p "$TMP/config/hypr/scripts"
cp -- "$STATE" "$TMP/config/hypr/scripts/quickshell_application_state.sh"
cp -- "$EDITOR_SAVE" "$TMP/config/hypr/scripts/quickshell_lockscreen_editor_save.sh"
printf 'image\n' >"$TMP/custom.png"

editor_layout='{"logo":{"x":0.5,"y":0.34,"scale":1,"stretch_x":1,"stretch_y":1,"opacity":100,"rotation":12,"color":"auto"},"time":{"x":0.5,"y":0.51,"scale":1,"stretch_x":1,"stretch_y":1,"opacity":100,"rotation":0,"color":"auto"},"date":{"x":0.5,"y":0.555,"scale":1,"stretch_x":1,"stretch_y":1,"opacity":100,"rotation":0,"color":"auto"},"username":{"x":0.5,"y":0.595,"scale":1,"stretch_x":1,"stretch_y":1,"opacity":100,"rotation":0,"color":"auto"},"weather":{"x":0.5,"y":0.635,"scale":1,"stretch_x":1,"stretch_y":1,"opacity":100,"rotation":0,"color":"auto"},"password":{"x":0.5,"y":0.7,"scale":1,"stretch_x":1,"stretch_y":1,"opacity":100,"rotation":0,"color":"auto"}}'
custom_images="$(jq -cn --arg path "$TMP/custom.png" '[{id:"image-regression",path:$path,x:0.5,y:0.5,scale:1,stretch_x:1,stretch_y:1,opacity:63,rotation:17,spawn_animation:"pixel-warp",spawn_timing:"after-logo",visible:true}]')"
visualizer='{"enabled":false,"x":0.5,"y":0.8,"scale":1,"stretch_x":1,"stretch_y":1,"opacity":100,"rotation":9,"color":"auto","bands":16,"gap":4,"height":100,"sensitivity":180,"shape":"straight","bend":45,"performance":"balanced"}'
timezone_clocks='[{"id":"timezone-regression","timezone":"UTC","format":"24h","show_label":false,"x":0.5,"y":0.6,"scale":1,"stretch_x":1,"stretch_y":1,"opacity":80,"rotation":5,"color":"auto","visible":true}]'
custom_texts='[{"id":"text-regression","text":"Saved text","variants":[],"randomize":false,"alignment":"center","x":0.5,"y":0.55,"scale":1,"stretch_x":1,"stretch_y":1,"opacity":75,"rotation":-5,"color":"auto","visible":true}]'

editor_output="$(
    XDG_CONFIG_HOME="$TMP/config" XDG_CACHE_HOME="$TMP/cache" HOME="$TMP/home" HYPR_QUICKSHELL_SCRIPT=/bin/false \
        bash "$TMP/config/hypr/scripts/quickshell_lockscreen_editor_save.sh" \
        "$editor_layout" "$visibility" black '#000000' '' cover 0.5 0.5 none 0 10 auto \
        "$custom_images" "$visualizer" 90 pixel 1800 90 pixelated split squares '•' 24h \
        "$timezone_clocks" "$custom_texts"
)" || fail 'current editor-save wrapper rejected a valid full presentation'

jq -e '.ok == true' <<<"$editor_output" >/dev/null 2>&1 \
    || fail 'editor-save wrapper did not return an explicit JSON success response'
jq -e '
    .lockscreen_layout.logo.rotation == 12
    and .lockscreen_custom_images[0].opacity == 63
    and .lockscreen_custom_images[0].spawn_timing == "after-logo"
    and .lockscreen_visualizer.rotation == 9
    and .lockscreen_timezone_clocks[0].show_label == false
    and .lockscreen_custom_texts[0].text == "Saved text"
' "$TMP/cache/awtarchy/quickshell-state.json" >/dev/null \
    || fail 'editor-save wrapper did not atomically persist current extension fields'

# Upgraded installations may carry the legacy-inconsistent combination
# lockscreen_background="wallpaper" with no wallpaper path. Saving any editor
# change must repair that stale optional resource state instead of bricking Save.
editor_output="$(
    XDG_CONFIG_HOME="$TMP/config" XDG_CACHE_HOME="$TMP/cache" HOME="$TMP/home" HYPR_QUICKSHELL_SCRIPT=/bin/false \
        bash "$TMP/config/hypr/scripts/quickshell_lockscreen_editor_save.sh" \
        "$editor_layout" "$visibility" wallpaper '#000000' '' cover 0.5 0.5 none 0 10 auto \
        "$custom_images" "$visualizer" 90 pixel 1800 90 pixelated split squares '•' 24h \
        "$timezone_clocks" "$custom_texts"
)" || fail 'stale wallpaper-without-path state still bricks editor Save'

jq -e '.ok == true' <<<"$editor_output" >/dev/null 2>&1 \
    || fail 'repaired stale wallpaper state did not return explicit JSON success'
jq -e '
    .lockscreen_background == "black"
    and .lockscreen_wallpaper_path == ""
' "$TMP/cache/awtarchy/quickshell-state.json" >/dev/null \
    || fail 'stale wallpaper state was not repaired to a safe savable background'

# Optional custom-image files can disappear between releases or user sessions.
# A stale file reference must be removed rather than making every future Save fail.
rm -f -- "$TMP/custom.png"
editor_output="$(
    XDG_CONFIG_HOME="$TMP/config" XDG_CACHE_HOME="$TMP/cache" HOME="$TMP/home" HYPR_QUICKSHELL_SCRIPT=/bin/false \
        bash "$TMP/config/hypr/scripts/quickshell_lockscreen_editor_save.sh" \
        "$editor_layout" "$visibility" black '#000000' '' cover 0.5 0.5 none 0 10 auto \
        "$custom_images" "$visualizer" 90 pixel 1800 90 pixelated split squares '•' 24h \
        "$timezone_clocks" "$custom_texts"
)" || fail 'stale custom-image file still bricks editor Save'

jq -e '.ok == true' <<<"$editor_output" >/dev/null 2>&1 \
    || fail 'repaired stale custom-image state did not return explicit JSON success'
jq -e '.lockscreen_custom_images == []' "$TMP/cache/awtarchy/quickshell-state.json" >/dev/null \
    || fail 'stale custom-image reference was not removed during Save'

printf '%s\n' 'PASS: lockscreen background composition save dispatch'
