#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$ROOT/config/hypr/scripts/quickshell_lockscreen_contrast.sh"
DESKTOP_CACHE="$ROOT/config/quickshell/awtarchy/LockscreenContrast.qml"
SECURE_CACHE="$ROOT/config/quickshell/awtarchy-lock/LockContrastCache.qml"
EDITOR="$ROOT/config/quickshell/awtarchy/LockscreenEditor.qml"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
require_text() { grep -Fq -- "$2" "$1" || fail "$3"; }
reject_text() { ! grep -Fq -- "$2" "$1" || fail "$3"; }

layout='{"logo":{"x":0.5,"y":0.34},"time":{"x":0.5,"y":0.51},"date":{"x":0.5,"y":0.555},"username":{"x":0.5,"y":0.595},"weather":{"x":0.5,"y":0.635},"password":{"x":0.5,"y":0.7}}'
mkdir -p "$TMP/cache/awtarchy" "$TMP/home"
jq -n --argjson layout "$layout" '
{
  lockscreen_background:"black",
  lockscreen_background_color:"#000000",
  lockscreen_wallpaper_path:"",
  lockscreen_layout:$layout,
  lockscreen_monitor_overrides:{
    "DP-1":{
      lockscreen_background:"color",
      lockscreen_background_color:"#ffffff",
      lockscreen_wallpaper_path:"",
      lockscreen_layout:$layout
    }
  }
}' >"$TMP/cache/awtarchy/quickshell-state.json"

XDG_CACHE_HOME="$TMP/cache" HOME="$TMP/home" bash "$HELPER"
cache="$TMP/cache/awtarchy/lockscreen-contrast.json"
jq -e '
    .version == 3
    and .provider == "awtarchy-local-contrast"
    and .colors.logo == "#ffffff"
    and .colors.password == "#ffffff"
    and .monitor_colors["DP-1"].logo == "#000000"
    and .monitor_colors["DP-1"].password == "#000000"
' "$cache" >/dev/null || fail 'persisted contrast cache does not resolve Shared and DP-1 independently'

require_text "$HELPER" 'monitor_colors' 'contrast helper does not persist monitor color maps'
require_text "$HELPER" 'lockscreen_monitor_overrides' 'contrast helper ignores persisted monitor overrides'
require_text "$HELPER" 'function prepare_wallpaper_sample()' 'one-shot animated-media sampling was removed'
require_text "$HELPER" 'magick "${image}[0]" "$output"' 'GIF contrast no longer samples one deterministic first frame'
require_text "$HELPER" 'ffmpeg -v error -nostdin -i "$image" -map 0:v:0 -frames:v 1 -y "$output"' 'MP4 contrast no longer samples exactly one deterministic frame'
reject_text "$HELPER" '-stream_loop' 'contrast helper loops animated media while sampling'

require_text "$DESKTOP_CACHE" 'property var monitorAccents:' 'unlocked contrast service has no monitor accent map'
require_text "$DESKTOP_CACHE" 'function colorsForMonitor(name)' 'unlocked contrast service cannot resolve monitor colors'
require_text "$DESKTOP_CACHE" 'parsed.monitor_colors' 'unlocked contrast service ignores v3 monitor colors'

require_text "$SECURE_CACHE" 'property string monitorName: ""' 'secure contrast cache has no monitor identity'
require_text "$SECURE_CACHE" 'parsed.monitor_colors' 'secure contrast cache ignores monitor colors'
require_text "$SECURE_CACHE" 'parsed.monitor_colors[root.monitorName]' 'secure contrast cache does not select by monitor name'
require_text "$SECURE_CACHE" 'parsed.colors' 'secure contrast cache lost v2/Shared fallback'

require_text "$EDITOR" 'property var draftSharedAutoAccents:' 'editor has no Shared derived accent state'
require_text "$EDITOR" 'property var draftMonitorAutoAccents:' 'editor has no per-monitor derived accent map'
require_text "$EDITOR" 'function stashAutoAccentsForActiveProfile()' 'editor cannot stash active derived accents by profile'
require_text "$EDITOR" 'function loadAutoAccentsForActiveProfile()' 'editor cannot load target-profile derived accents'
require_text "$EDITOR" 'function autoAccentsForMonitor(name)' 'passive previews cannot resolve their own derived accents'
require_text "$EDITOR" 'autoAccents: root.autoAccentsForMonitor(modelData.name)' 'passive preview still uses active-monitor contrast'
require_text "$EDITOR" 'draftSharedAutoAccents = cloneAutoAccents(LockscreenContrast.accents)' 'editor does not initialize Shared accents from persisted cache'
require_text "$EDITOR" 'LockscreenContrast.colorsForMonitor(name)' 'editor does not initialize persisted per-monitor accents'

printf '%s\n' 'PASS: lockscreen per-monitor Auto Contrast contracts'
