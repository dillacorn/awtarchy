#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STATE="${ROOT}/config/hypr/scripts/quickshell_application_state.sh"
EDITOR_SAVE="${ROOT}/config/hypr/scripts/quickshell_lockscreen_editor_save.sh"
BAR="${ROOT}/config/quickshell/awtarchy/BarState.qml"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

layout='{"logo":{"x":0.5,"y":0.34,"scale":1,"stretch_x":1,"stretch_y":1,"opacity":100,"rotation":0,"color":"auto"},"time":{"x":0.5,"y":0.51,"scale":1,"stretch_x":1,"stretch_y":1,"opacity":100,"rotation":0,"color":"auto"},"date":{"x":0.5,"y":0.555,"scale":1,"stretch_x":1,"stretch_y":1,"opacity":100,"rotation":0,"color":"auto"},"username":{"x":0.5,"y":0.595,"scale":1,"stretch_x":1,"stretch_y":1,"opacity":100,"rotation":0,"color":"auto"},"weather":{"x":0.5,"y":0.635,"scale":1,"stretch_x":1,"stretch_y":1,"opacity":100,"rotation":0,"color":"auto"},"password":{"x":0.5,"y":0.7,"scale":1,"stretch_x":1,"stretch_y":1,"opacity":100,"rotation":0,"color":"auto"}}'
visualizer='{"enabled":false,"x":0.5,"y":0.8,"scale":1,"stretch_x":1,"stretch_y":1,"opacity":100,"rotation":0,"color":"auto","bands":16,"gap":4,"height":100,"sensitivity":180,"shape":"straight","bend":45,"performance":"balanced"}'

shared="$(jq -cn --argjson layout "$layout" --argjson visualizer "$visualizer" '{
  lockscreen_layout:$layout,
  lockscreen_show_logo:true,
  lockscreen_show_time:false,
  lockscreen_show_date:false,
  lockscreen_show_username:false,
  lockscreen_show_weather:false,
  lockscreen_custom_images:[],
  lockscreen_timezone_clocks:[],
  lockscreen_custom_texts:[],
  lockscreen_visualizer:$visualizer,
  lockscreen_background:"color",
  lockscreen_background_color:"#112233",
  lockscreen_wallpaper_path:"",
  lockscreen_wallpaper_fit:"cover",
  lockscreen_wallpaper_focal_x:0.5,
  lockscreen_wallpaper_focal_y:0.5,
  lockscreen_background_opacity:90,
  lockscreen_background_opacity_previous:90,
  lockscreen_overlay_mode:"none",
  lockscreen_overlay_strength:0,
  lockscreen_wallpaper_blur:10,
  lockscreen_blur_style:"pixelated",
  lockscreen_weather_units:"auto",
  lockscreen_animation:"split",
  lockscreen_entry_transition:"pixel",
  lockscreen_entry_transition_duration:1800,
  lockscreen_password_mask_mode:"squares",
  lockscreen_password_mask_character:"•",
  lockscreen_clock_format:"24h"
}')"

dp1="$(jq -c '.lockscreen_background="black" | .lockscreen_background_color="#000000"' <<<"$shared")"
hdmi="$(jq -c '.lockscreen_clock_format="12h" | .lockscreen_show_time=true' <<<"$shared")"
disconnected="$(jq -c '.lockscreen_entry_transition="wipe"' <<<"$shared")"
overrides="$(jq -cn --argjson dp1 "$dp1" --argjson hdmi "$hdmi" --argjson disconnected "$disconnected" '{"DP-1":$dp1,"HDMI-A-1":$hdmi,"DP-DISCONNECTED":$disconnected}')"

mkdir -p "$TMP/config/hypr/scripts" "$TMP/cache/awtarchy" "$TMP/home"
cp -- "$STATE" "$TMP/config/hypr/scripts/quickshell_application_state.sh"
cp -- "$EDITOR_SAVE" "$TMP/config/hypr/scripts/quickshell_lockscreen_editor_save.sh"
printf '%s\n' '{"enabled":true,"monitors":{},"launcher_sizes":{},"update_notifications_enabled":true,"unrelated_marker":"keep-me"}' >"$TMP/cache/awtarchy/quickshell-state.json"

output="$(
  XDG_CONFIG_HOME="$TMP/config" XDG_CACHE_HOME="$TMP/cache" HOME="$TMP/home" HYPR_QUICKSHELL_SCRIPT=/bin/false \
    bash "$TMP/config/hypr/scripts/quickshell_lockscreen_editor_save.sh" --profiles "$shared" "$overrides"
)" || fail 'profile save mode rejected valid Shared/override state'

jq -e '.ok == true' <<<"$output" >/dev/null || fail 'profile save mode did not return JSON success'
jq -e '
  .unrelated_marker == "keep-me"
  and .lockscreen_background == "color"
  and .lockscreen_background_color == "#112233"
  and .lockscreen_entry_transition == "pixel"
  and .lockscreen_monitor_overrides["DP-1"].lockscreen_background == "black"
  and .lockscreen_monitor_overrides["HDMI-A-1"].lockscreen_clock_format == "12h"
  and .lockscreen_monitor_overrides["DP-DISCONNECTED"].lockscreen_entry_transition == "wipe"
' "$TMP/cache/awtarchy/quickshell-state.json" >/dev/null \
  || fail 'Shared and monitor profiles were not persisted together'

before_hash="$(sha256sum "$TMP/cache/awtarchy/quickshell-state.json" | awk '{print $1}')"
invalid_overrides="$(jq -c '.["DP-1"].lockscreen_background="invalid"' <<<"$overrides")"
if XDG_CONFIG_HOME="$TMP/config" XDG_CACHE_HOME="$TMP/cache" HOME="$TMP/home" HYPR_QUICKSHELL_SCRIPT=/bin/false \
    bash "$TMP/config/hypr/scripts/quickshell_lockscreen_editor_save.sh" --profiles "$shared" "$invalid_overrides" >/dev/null 2>&1; then
  fail 'invalid monitor override was accepted'
fi
after_hash="$(sha256sum "$TMP/cache/awtarchy/quickshell-state.json" | awk '{print $1}')"
[[ "$before_hash" == "$after_hash" ]] || fail 'invalid override partially modified persisted state'

missing_wallpaper="$TMP/missing-wallpaper.png"
stale="$(jq -c --arg path "$missing_wallpaper" '.lockscreen_background="wallpaper" | .lockscreen_wallpaper_path=$path' <<<"$shared")"
stale_overrides="$(jq -cn --argjson stale "$stale" '{"DP-STALE":$stale}')"
output="$(
  XDG_CONFIG_HOME="$TMP/config" XDG_CACHE_HOME="$TMP/cache" HOME="$TMP/home" HYPR_QUICKSHELL_SCRIPT=/bin/false \
    bash "$TMP/config/hypr/scripts/quickshell_lockscreen_editor_save.sh" --profiles "$shared" "$stale_overrides"
)" || fail 'stale optional monitor wallpaper still bricks profile save'
jq -e '.lockscreen_monitor_overrides["DP-STALE"].lockscreen_background == "black"
  and .lockscreen_monitor_overrides["DP-STALE"].lockscreen_wallpaper_path == ""' \
  "$TMP/cache/awtarchy/quickshell-state.json" >/dev/null \
  || fail 'stale monitor wallpaper was not repaired to safe black mode'

# BarState must expose one resolver-backed facade instead of duplicating profile rules.
grep -Fq 'import "LockscreenPresentationState.js" as LockscreenPresentationState' "$BAR" \
  || fail 'BarState does not import the shared lockscreen profile resolver'
grep -Fq 'function lockscreenSharedProfile()' "$BAR" \
  || fail 'BarState has no Shared profile facade'
grep -Fq 'function lockscreenMonitorOverrides()' "$BAR" \
  || fail 'BarState has no monitor override facade'
grep -Fq 'function lockscreenProfileForMonitor(name)' "$BAR" \
  || fail 'BarState has no effective per-monitor profile facade'
grep -Fq 'LockscreenPresentationState.profileForMonitor(' "$BAR" \
  || fail 'BarState does not delegate effective profile resolution to the shared resolver'

printf '%s\n' 'PASS: lockscreen monitor profile persistence and BarState facade'
