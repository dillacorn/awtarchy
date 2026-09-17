#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STATE="$ROOT/config/hypr/scripts/quickshell_application_state.sh"
EDITOR_SAVE="$ROOT/config/hypr/scripts/quickshell_lockscreen_editor_save.sh"
BAR="$ROOT/config/quickshell/awtarchy/BarState.qml"
EDITOR="$ROOT/config/quickshell/awtarchy/LockscreenEditor.qml"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
require_text() { grep -Fq -- "$2" "$1" || fail "$3"; }

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

work="$(jq -c '.lockscreen_background_color="#223344" | .lockscreen_show_time=true' <<<"$shared")"
gaming="$(jq -c '.lockscreen_background_color="#334455" | .lockscreen_entry_transition="wipe"' <<<"$shared")"
saved_profiles="$(jq -cn --argjson work "$work" --argjson gaming "$gaming" '[
  {id:"profile-work",name:"Work",profile:$work},
  {id:"profile-gaming",name:"Gaming",profile:$gaming}
]')"

mkdir -p "$TMP/config/hypr/scripts" "$TMP/cache/awtarchy" "$TMP/home"
cp -- "$STATE" "$TMP/config/hypr/scripts/quickshell_application_state.sh"
cp -- "$EDITOR_SAVE" "$TMP/config/hypr/scripts/quickshell_lockscreen_editor_save.sh"
printf '%s\n' '{"enabled":true,"monitors":{},"launcher_sizes":{},"unrelated_marker":"keep-me"}' >"$TMP/cache/awtarchy/quickshell-state.json"

run_save() {
  XDG_CONFIG_HOME="$TMP/config" XDG_CACHE_HOME="$TMP/cache" HOME="$TMP/home" HYPR_QUICKSHELL_SCRIPT=/bin/false \
    bash "$TMP/config/hypr/scripts/quickshell_lockscreen_editor_save.sh" "$@"
}

output="$(run_save --profiles "$shared" '{}' "$saved_profiles")" \
  || fail 'atomic profile save rejected valid saved configurations'
jq -e '.ok == true' <<<"$output" >/dev/null || fail 'saved-configuration profile save did not return success'

state_file="$TMP/cache/awtarchy/quickshell-state.json"
jq -e '
  .unrelated_marker == "keep-me"
  and (.lockscreen_saved_profiles | length) == 2
  and .lockscreen_saved_profiles[0].id == "profile-work"
  and .lockscreen_saved_profiles[0].name == "Work"
  and .lockscreen_saved_profiles[0].profile.lockscreen_background_color == "#223344"
  and .lockscreen_saved_profiles[1].id == "profile-gaming"
  and .lockscreen_saved_profiles[1].name == "Gaming"
  and .lockscreen_saved_profiles[1].profile.lockscreen_entry_transition == "wipe"
' "$state_file" >/dev/null || fail 'saved lockscreen configuration order/content was not persisted'

# The old Shared+overrides form remains valid and must preserve an existing
# saved-profile library rather than erase it.
legacy_shared="$(jq -c '.lockscreen_background_color="#445566"' <<<"$shared")"
run_save --profiles "$legacy_shared" '{}' >/dev/null \
  || fail 'legacy two-profile payload stopped working'
jq -e '.lockscreen_background_color == "#445566"
  and (.lockscreen_saved_profiles | length) == 2
  and .lockscreen_saved_profiles[0].name == "Work"' "$state_file" >/dev/null \
  || fail 'legacy profile save did not preserve saved configurations'

before_hash="$(sha256sum "$state_file" | awk '{print $1}')"
duplicate_names="$(jq -c '.[1].name="work"' <<<"$saved_profiles")"
if run_save --profiles "$shared" '{}' "$duplicate_names" >/dev/null 2>&1; then
  fail 'case-insensitive duplicate saved-configuration names were accepted'
fi
[[ "$before_hash" == "$(sha256sum "$state_file" | awk '{print $1}')" ]] \
  || fail 'duplicate saved-configuration name partially modified state'

invalid_profile="$(jq -c '.[1].profile.lockscreen_background="invalid"' <<<"$saved_profiles")"
if run_save --profiles "$shared" '{}' "$invalid_profile" >/dev/null 2>&1; then
  fail 'invalid saved configuration profile was accepted'
fi
[[ "$before_hash" == "$(sha256sum "$state_file" | awk '{print $1}')" ]] \
  || fail 'invalid saved profile partially modified state'

invalid_name="$(jq -c '.[0].name="   "' <<<"$saved_profiles")"
if run_save --profiles "$shared" '{}' "$invalid_name" >/dev/null 2>&1; then
  fail 'blank saved-configuration name was accepted'
fi
[[ "$before_hash" == "$(sha256sum "$state_file" | awk '{print $1}')" ]] \
  || fail 'invalid saved name partially modified state'

require_text "$BAR" 'lockscreen_saved_profiles: []' 'BarState defaults do not include saved lockscreen profiles'
require_text "$BAR" 'function lockscreenSavedProfiles()' 'BarState has no saved-profile facade'
require_text "$BAR" 'LockscreenPresentationState.cloneProfile(raw.profile)' 'BarState saved profiles do not use the shared profile resolver'
require_text "$EDITOR" 'property var draftSavedProfiles: []' 'editor has no saved-profile session draft'
require_text "$EDITOR" 'BarState.lockscreenSavedProfiles()' 'editor does not load persisted saved profiles'
require_text "$EDITOR" 'JSON.stringify(draftSavedProfiles)' 'Ctrl+S does not include saved profiles in the atomic transaction'

printf '%s\n' 'PASS: reusable lockscreen configurations persist atomically'
