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

monitor_profiles="$(jq -cn --argjson shared "$shared" '{"DP-1":$shared}')"

mkdir -p "$TMP/config/hypr/scripts" "$TMP/cache/awtarchy" "$TMP/home"
cp -- "$STATE" "$TMP/config/hypr/scripts/quickshell_application_state.sh"
cp -- "$EDITOR_SAVE" "$TMP/config/hypr/scripts/quickshell_lockscreen_editor_save.sh"
printf '%s\n' '{"enabled":true,"monitors":{},"launcher_sizes":{},"unrelated_marker":"keep-me"}' >"$TMP/cache/awtarchy/quickshell-state.json"

run_save() {
  XDG_CONFIG_HOME="$TMP/config" XDG_CACHE_HOME="$TMP/cache" HOME="$TMP/home" HYPR_QUICKSHELL_SCRIPT=/bin/false \
    bash "$TMP/config/hypr/scripts/quickshell_lockscreen_editor_save.sh" "$@"
}

output="$(run_save --profiles "$monitor_profiles" "$shared" "$saved_profiles")" \
  || fail 'atomic per-display profile save rejected valid saved configurations'
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

# Omitting the optional saved-profile payload must preserve an existing
# saved-profile library rather than erase it.
updated_last="$(jq -c '.lockscreen_background_color="#445566"' <<<"$shared")"
updated_profiles="$(jq -cn --argjson profile "$updated_last" '{"DP-1":$profile}')"
run_save --profiles "$updated_profiles" "$updated_last" >/dev/null \
  || fail 'per-display save without saved-profile payload stopped working'
jq -e '.lockscreen_background_color == "#445566"
  and .lockscreen_monitor_profiles["DP-1"].lockscreen_background_color == "#445566"
  and (.lockscreen_saved_profiles | length) == 2
  and .lockscreen_saved_profiles[0].name == "Work"' "$state_file" >/dev/null \
  || fail 'per-display profile save did not preserve saved configurations'

before_hash="$(sha256sum "$state_file" | awk '{print $1}')"
duplicate_names="$(jq -c '.[1].name="work"' <<<"$saved_profiles")"
if run_save --profiles "$monitor_profiles" "$shared" "$duplicate_names" >/dev/null 2>&1; then
  fail 'case-insensitive duplicate saved-configuration names were accepted'
fi
[[ "$before_hash" == "$(sha256sum "$state_file" | awk '{print $1}')" ]] \
  || fail 'duplicate saved-configuration name partially modified state'

invalid_profile="$(jq -c '.[1].profile.lockscreen_background="invalid"' <<<"$saved_profiles")"
if run_save --profiles "$monitor_profiles" "$shared" "$invalid_profile" >/dev/null 2>&1; then
  fail 'invalid saved configuration profile was accepted'
fi
[[ "$before_hash" == "$(sha256sum "$state_file" | awk '{print $1}')" ]] \
  || fail 'invalid saved profile partially modified state'

invalid_name="$(jq -c '.[0].name="   "' <<<"$saved_profiles")"
if run_save --profiles "$monitor_profiles" "$shared" "$invalid_name" >/dev/null 2>&1; then
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

# Layout-tab reusable configuration controls and actions.
require_text "$EDITOR" 'function confirmSaveCurrentConfiguration()' 'editor cannot create a named saved configuration'
require_text "$EDITOR" 'function confirmRenameSavedConfiguration()' 'editor cannot rename a saved configuration'
require_text "$EDITOR" 'function confirmDeleteSavedConfiguration()' 'editor cannot delete a saved configuration'
require_text "$EDITOR" 'function moveSavedConfiguration(' 'editor cannot reorder saved configurations'
require_text "$EDITOR" 'function confirmOverwriteSavedConfiguration()' 'editor cannot overwrite a saved configuration from the current display'
require_text "$EDITOR" 'function applySavedConfigurationToMonitor(' 'editor cannot apply a saved configuration to a display'
require_text "$EDITOR" 'function applySavedConfigurationToAllOthers(' 'editor cannot apply a saved configuration to all other displays'
require_text "$EDITOR" 'label: "Save Current Configuration"' 'Layout tab is missing Save Current Configuration'
require_text "$EDITOR" 'label: "Rename"' 'Layout tab is missing saved-configuration Rename'
require_text "$EDITOR" 'label: "Delete"' 'Layout tab is missing saved-configuration Delete'
require_text "$EDITOR" 'label: "Move Up"' 'Layout tab is missing Move Up'
require_text "$EDITOR" 'label: "Move Down"' 'Layout tab is missing Move Down'
require_text "$EDITOR" 'label: "Overwrite"' 'Layout tab is missing Overwrite'
require_text "$EDITOR" 'text: "Apply To"' 'Layout tab is missing Apply To target controls'
require_text "$EDITOR" 'model: Quickshell.screens' 'saved configurations do not expose connected display targets'
require_text "$EDITOR" 'label: "All Other Displays"' 'saved configurations cannot be applied to all other connected displays'
! grep -Fq 'label: "Shared Configuration"' "$EDITOR" || fail 'saved configurations still expose a Shared target'
require_text "$EDITOR" 'text: "Delete Saved Configuration?"' 'saved-configuration delete has no confirmation dialog'
require_text "$EDITOR" 'text: "Overwrite Saved Configuration?"' 'saved-configuration overwrite has no confirmation dialog'

python3 - "$EDITOR" <<'PY'
import pathlib
import sys

text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")

def body(name):
    marker = f"function {name}("
    start = text.find(marker)
    if start < 0:
        raise SystemExit(f"FAIL: missing function {name}")
    brace = text.find("{", start)
    if brace < 0:
        raise SystemExit(f"FAIL: malformed function {name}")
    depth = 0
    quote = None
    escape = False
    for i in range(brace, len(text)):
        ch = text[i]
        if quote is not None:
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == quote:
                quote = None
            continue
        if ch in ('"', "'"):
            quote = ch
            continue
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return text[brace + 1:i]
    raise SystemExit(f"FAIL: unterminated function {name}")

monitor = body("applySavedConfigurationToMonitor")
if 'next[targetName] = cloneSnapshot(profile)' not in monitor or 'draftMonitorProfiles = next' not in monitor:
    raise SystemExit("FAIL: applying a saved configuration does not replace the target display profile")
if 'loadProfileIntoDraft(profile)' not in monitor:
    raise SystemExit("FAIL: applying a saved configuration to the active display does not load the preset")
if '"monitor:" + targetName' not in monitor:
    raise SystemExit("FAIL: monitor-target preset application does not scope history to the target display")

all_others = body("applySavedConfigurationToAllOthers")
if 'Quickshell.screens' not in all_others or 'draftMonitorProfiles' not in all_others:
    raise SystemExit("FAIL: applying a saved configuration to all other displays does not update the per-display map")

if "function applySavedConfigurationToShared(" in text:
    raise SystemExit("FAIL: saved configuration actions still expose Shared mode")

print("PASS: saved configuration editor actions target per-display profiles correctly")
PY

printf '%s\n' 'PASS: reusable lockscreen configurations persist atomically and expose Layout actions'
