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

base="$(jq -cn --argjson layout "$layout" --argjson visualizer "$visualizer" '{
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

dp1="$(jq -c '.lockscreen_background="black" | .lockscreen_background_color="#000000"' <<<"$base")"
hdmi="$(jq -c '.lockscreen_clock_format="12h" | .lockscreen_show_time=true' <<<"$base")"
disconnected="$(jq -c '.lockscreen_entry_transition="wipe"' <<<"$base")"
monitor_profiles="$(jq -cn --argjson dp1 "$dp1" --argjson hdmi "$hdmi" --argjson disconnected "$disconnected"   '{"DP-1":$dp1,"HDMI-A-1":$hdmi,"DP-DISCONNECTED":$disconnected}')"
last_edited="$(jq -c '.lockscreen_background_color="#445566"' <<<"$base")"
saved_profiles="$(jq -cn --argjson profile "$base" '[{id:"profile-work",name:"Work",profile:$profile}]')"

mkdir -p "$TMP/config/hypr/scripts" "$TMP/cache/awtarchy" "$TMP/home"
cp -- "$STATE" "$TMP/config/hypr/scripts/quickshell_application_state.sh"
cp -- "$EDITOR_SAVE" "$TMP/config/hypr/scripts/quickshell_lockscreen_editor_save.sh"
printf '%s\n' '{"enabled":true,"monitors":{},"launcher_sizes":{},"update_notifications_enabled":true,"unrelated_marker":"keep-me","lockscreen_monitor_overrides":{"OLD-DP":{"stale":true}}}' >"$TMP/cache/awtarchy/quickshell-state.json"

run_save() {
  XDG_CONFIG_HOME="$TMP/config" XDG_CACHE_HOME="$TMP/cache" HOME="$TMP/home" HYPR_QUICKSHELL_SCRIPT=/bin/false \
    bash "$TMP/config/hypr/scripts/quickshell_lockscreen_editor_save.sh" "$@"
}

output="$(run_save --profiles "$monitor_profiles" "$last_edited" "$saved_profiles")" \
  || fail 'per-display profile save mode rejected valid state'

jq -e '.ok == true' <<<"$output" >/dev/null || fail 'profile save mode did not return JSON success'
state_file="$TMP/cache/awtarchy/quickshell-state.json"

jq -e '
  .unrelated_marker == "keep-me"
  and .lockscreen_monitor_profiles["DP-1"].lockscreen_background == "black"
  and .lockscreen_monitor_profiles["HDMI-A-1"].lockscreen_clock_format == "12h"
  and .lockscreen_monitor_profiles["DP-DISCONNECTED"].lockscreen_entry_transition == "wipe"
  and .lockscreen_last_edited_profile.lockscreen_background_color == "#445566"
  and .lockscreen_background_color == "#445566"
  and .lockscreen_entry_transition == "pixel"
  and (.lockscreen_monitor_overrides | not)
  and (.lockscreen_saved_profiles | length) == 1
  and .lockscreen_saved_profiles[0].name == "Work"
' "$state_file" >/dev/null || fail 'per-display profiles were not persisted atomically'

before_hash="$(sha256sum "$state_file" | awk '{print $1}')"
invalid_profiles="$(jq -c '.["DP-1"].lockscreen_background="invalid"' <<<"$monitor_profiles")"
if run_save --profiles "$invalid_profiles" "$last_edited" "$saved_profiles" >/dev/null 2>&1; then
  fail 'invalid monitor profile was accepted'
fi
[[ "$before_hash" == "$(sha256sum "$state_file" | awk '{print $1}')" ]] \
  || fail 'invalid monitor profile partially modified persisted state'

missing_wallpaper="$TMP/missing-wallpaper.png"
stale="$(jq -c --arg path "$missing_wallpaper" '.lockscreen_background="wallpaper" | .lockscreen_wallpaper_path=$path' <<<"$base")"
stale_profiles="$(jq -cn --argjson stale "$stale" '{"DP-STALE":$stale}')"
run_save --profiles "$stale_profiles" "$last_edited" "$saved_profiles" >/dev/null \
  || fail 'stale optional monitor wallpaper still bricks profile save'
jq -e '.lockscreen_monitor_profiles["DP-STALE"].lockscreen_background == "black"
  and .lockscreen_monitor_profiles["DP-STALE"].lockscreen_wallpaper_path == ""' "$state_file" >/dev/null \
  || fail 'stale monitor wallpaper was not repaired to safe black mode'

grep -Fq 'import "LockscreenPresentationState.js" as LockscreenPresentationState' "$BAR" \
  || fail 'BarState does not import the profile resolver'
grep -Fq 'function lockscreenMonitorProfiles()' "$BAR" \
  || fail 'BarState has no per-display profile facade'
grep -Fq 'function lockscreenLastEditedProfile()' "$BAR" \
  || fail 'BarState has no last-edited profile facade'
grep -Fq 'function lockscreenProfileForMonitor(name)' "$BAR" \
  || fail 'BarState has no effective per-monitor profile facade'
grep -Fq 'LockscreenPresentationState.profileForMonitor(' "$BAR" \
  || fail 'BarState does not delegate per-monitor resolution to the resolver'

printf '%s\n' 'PASS: lockscreen per-display profile persistence and BarState facade'
