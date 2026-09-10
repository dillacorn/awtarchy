#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
APP_STATE="${ROOT}/config/hypr/scripts/quickshell_application_state.sh"
DESKTOP_SHELL="${ROOT}/config/quickshell/awtarchy/shell.qml"
EDITOR="${ROOT}/config/quickshell/awtarchy/LockscreenEditor.qml"
WEATHER="${ROOT}/config/quickshell/awtarchy/LockscreenWeather.qml"
WALLPAPER="${ROOT}/config/quickshell/awtarchy-lock/LockWallpaperState.qml"
PREVIEW_WALLPAPER="${ROOT}/config/quickshell/awtarchy/LockPreviewWallpaperState.qml"
LOCK_SHELL="${ROOT}/config/quickshell/awtarchy-lock/shell.qml"
LOCK_SCENE="${ROOT}/config/quickshell/awtarchy-lock/LockScene.qml"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

require_file() {
    [[ -f "$1" ]] || fail "$2"
}

require_text() {
    local file="$1" text="$2" message="$3"
    grep -Fq -- "$text" "$file" || fail "$message"
}

reject_text() {
    local file="$1" text="$2" message="$3"
    if grep -Fq -- "$text" "$file"; then
        fail "$message"
    fi
}

# RED gate: unlocked weather refresh ownership and dedicated local lockscreen
# wallpaper state must exist as explicit components rather than placeholders.
require_file "$WEATHER" 'unlocked LockscreenWeather singleton is missing'
require_file "$WALLPAPER" 'local LockWallpaperState reader is missing'
require_file "$PREVIEW_WALLPAPER" 'desktop lock preview wallpaper reader is missing'

# Unlocked weather refresh is rate-limited and only uses the dedicated helper.
require_text "$WEATHER" 'pragma Singleton' \
    'LockscreenWeather is not an unlocked-session singleton'
require_text "$WEATHER" 'quickshell_lockscreen_weather.sh' \
    'LockscreenWeather does not use the dedicated weather helper'
require_text "$WEATHER" 'BarState.lockscreenShowWeather()' \
    'LockscreenWeather does not honor the saved Weather toggle'
require_text "$WEATHER" 'BarState.lockscreenWeatherLocation()' \
    'LockscreenWeather does not use the explicit saved location'
require_text "$WEATHER" 'interval: 1200000' \
    'LockscreenWeather refresh cadence is more frequent than the 20-minute floor'
require_text "$WEATHER" 'Connections {' \
    'LockscreenWeather does not react to saved state changes'
require_text "$WEATHER" 'target: BarState' \
    'LockscreenWeather does not watch BarState changes'
reject_text "$WEATHER" 'WlSessionLock' \
    'unlocked weather refresh component owns lock authority'
reject_text "$WEATHER" 'LockAuth' \
    'unlocked weather refresh component references PAM'
require_text "$DESKTOP_SHELL" 'LockscreenWeather !== null' \
    'desktop shell does not force weather singleton construction'
reject_text "$LOCK_SHELL" 'quickshell_lockscreen_weather.sh' \
    'secure lock shell launches the network weather helper'

# Wallpaper source is dedicated persisted lockscreen state. The secure shell
# reads the local Quickshell cache, normalizes the path, and passes it to a
# presentation-only local-file encoder. It must never follow desktop Awtwall
# backend state or accept a URL-style source at lock time.
require_text "$APP_STATE" 'lockscreen_wallpaper_path' \
    'application state does not persist a dedicated lockscreen wallpaper path'
require_text "$APP_STATE" 'normalize_lockscreen_wallpaper_path()' \
    'application state does not validate the dedicated lockscreen wallpaper path'
require_text "$LOCK_SHELL" '/awtarchy/quickshell-state.json' \
    'secure lock shell does not read the local persisted Quickshell state cache'
require_text "$LOCK_SHELL" 'lockWallpaperPath = normalizedWallpaperPath(parsed.lockscreen_wallpaper_path);' \
    'secure lock shell does not load the dedicated wallpaper path from persisted state'
require_text "$LOCK_SHELL" 'path: root.lockWallpaperPath' \
    'secure lock wallpaper reader does not receive the normalized persisted path'
reject_text "$WALLPAPER" 'backend_state.tsv' \
    'LockWallpaperState still follows desktop Awtwall backend state'
reject_text "$WALLPAPER" 'FileView {' \
    'LockWallpaperState owns state-file I/O instead of remaining presentation-only'
require_text "$WALLPAPER" 'startsWith("/")' \
    'LockWallpaperState does not require an absolute local path'
require_text "$WALLPAPER" 'indexOf("://")' \
    'LockWallpaperState does not explicitly reject URL-style sources'
require_text "$WALLPAPER" 'encodeURI("file://" + value)' \
    'LockWallpaperState does not convert local paths to file URLs safely'
for forbidden in curl wget http:// https://; do
    reject_text "$WALLPAPER" "$forbidden" \
        "LockWallpaperState contains network behavior: $forbidden"
done
require_text "$LOCK_SHELL" 'LockWallpaperState {' \
    'secure lock shell does not own a local wallpaper-state reader'
require_text "$LOCK_SHELL" 'wallpaperSource: lockWallpaperState.source' \
    'secure lock surfaces do not receive the local wallpaper source'
cmp -s "$WALLPAPER" "$PREVIEW_WALLPAPER" \
    || fail 'desktop wallpaper preview reader drifted from secure lock wallpaper reader'
require_text "$EDITOR" 'LockPreviewWallpaperState {' \
    'lockscreen editor does not use its config-local wallpaper-state reader'
require_text "$EDITOR" 'path: root.draftWallpaperPath' \
    'lockscreen editor preview does not receive its dedicated wallpaper draft path'
require_text "$EDITOR" 'wallpaperSource: wallpaperState.source' \
    'lockscreen editor preview does not receive the local wallpaper source'
require_text "$LOCK_SCENE" 'root.backgroundMode === "color" ? root.backgroundColor : "#000000"' \
    'shared scene no longer has a black wallpaper fallback'

printf 'PASS: lockscreen runtime service contracts\n'
