#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
APP_STATE="${ROOT}/config/hypr/scripts/quickshell_application_state.sh"
BAR_STATE="${ROOT}/config/quickshell/awtarchy/BarState.qml"
QUICK_SETTINGS="${ROOT}/config/quickshell/awtarchy/QuickSettings.qml"
SHELL_QML="${ROOT}/config/quickshell/awtarchy-lock/shell.qml"
SURFACE_QML="${ROOT}/config/quickshell/awtarchy-lock/LockSurface.qml"
SCENE_QML="${ROOT}/config/quickshell/awtarchy-lock/LockScene.qml"
AUDIO_QML="${ROOT}/config/quickshell/awtarchy-lock/LockAudioAnalyzer.qml"
WEATHER_QML="${ROOT}/config/quickshell/awtarchy-lock/LockWeatherCache.qml"
CAVA_CONFIG="${ROOT}/config/quickshell/awtarchy-lock/cava.conf"
AUDIO_HELPER="${ROOT}/config/hypr/scripts/quickshell_lockscreen_audio.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
require_file() { [[ -f "$1" ]] || fail "$2"; }
require_text() { grep -Fq -- "$2" "$1" || fail "$3"; }
reject_text() { if grep -Fq -- "$2" "$1"; then fail "$3"; fi; }

mkdir -p "$TMP/cache/awtarchy" "$TMP/home" "$TMP/config"
printf '%s\n' '{"enabled":true,"monitors":{},"launcher_sizes":{},"update_notifications_enabled":true}' \
    >"$TMP/cache/awtarchy/quickshell-state.json"

check_bool_setting() {
    local command="$1" field="$2"
    XDG_CACHE_HOME="$TMP/cache" XDG_CONFIG_HOME="$TMP/config" HOME="$TMP/home" \
        bash "$APP_STATE" "$command" true
    jq -e --arg field "$field" '.[$field] == true' "$TMP/cache/awtarchy/quickshell-state.json" >/dev/null \
        || fail "$command did not persist true to $field"
    XDG_CACHE_HOME="$TMP/cache" XDG_CONFIG_HOME="$TMP/config" HOME="$TMP/home" \
        bash "$APP_STATE" "$command" false
    jq -e --arg field "$field" '.[$field] == false' "$TMP/cache/awtarchy/quickshell-state.json" >/dev/null \
        || fail "$command did not persist false to $field"
}

check_bool_setting set-lockscreen-mouse-interactive lockscreen_mouse_interactive
check_bool_setting set-lockscreen-show-time lockscreen_show_time
check_bool_setting set-lockscreen-show-date lockscreen_show_date
check_bool_setting set-lockscreen-show-username lockscreen_show_username
check_bool_setting set-lockscreen-show-weather lockscreen_show_weather

require_text "$BAR_STATE" 'lockscreen_logo_physics_hz: 30' \
    'BarState stock logo physics rate is not 30 Hz'
require_text "$BAR_STATE" 'lockscreen_mouse_interactive: true' \
    'BarState stock mouse interaction is not enabled'
require_text "$BAR_STATE" 'function lockscreenLogoPhysicsHz()' \
    'BarState does not normalize the logo physics rate'
require_text "$BAR_STATE" 'function lockscreenMouseInteractiveEnabled()' \
    'BarState does not normalize mouse interaction'
require_text "$QUICK_SETTINGS" 'text: "Logo Physics"' \
    'Quick Settings has no Logo Physics control'
require_text "$QUICK_SETTINGS" 'text: "Mouse Interaction"' \
    'Quick Settings has no Mouse Interaction control'
reject_text "$QUICK_SETTINGS" 'text: "Audio Reactive"' \
    'retired audio-reactive logo control remains visible'

require_text "$SHELL_QML" 'property int lockLogoPhysicsHz: 30' \
    'secure lock shell does not default logo physics to 30 Hz'
require_text "$SHELL_QML" 'property bool lockMouseInteractive: true' \
    'secure lock shell has no mouse-interaction preference'
require_text "$SHELL_QML" 'lockLogoPhysicsHz = normalizedLogoPhysicsHz(parsed.lockscreen_logo_physics_hz);' \
    'secure lock shell does not load the persisted logo physics rate'
reject_text "$SHELL_QML" 'LockAudioAnalyzer {' \
    'secure lock still starts an analyzer solely to move the AWTARCHY logo'
require_text "$SHELL_QML" 'LockWeatherCache {' \
    'secure lock shell lost its cache-only weather reader'
require_text "$SHELL_QML" 'logoPhysicsHz: root.lockLogoPhysicsHz' \
    'secure lock surfaces do not receive logo physics rate'
require_text "$SHELL_QML" 'mouseInteractive: root.lockMouseInteractive' \
    'secure lock surfaces do not receive mouse interaction state'

require_text "$SURFACE_QML" 'cursorShape: Qt.BlankCursor' \
    'lockscreen exposes the real pointer'
require_text "$SURFACE_QML" 'required property int logoPhysicsHz' \
    'lock surface has no logo physics input'
require_text "$SURFACE_QML" 'scene.handlePointerClick(mouse.x, mouse.y)' \
    'secure surface drops pointer clicks before presentation physics'
require_text "$SURFACE_QML" 'password.forceActiveFocus()' \
    'click interaction no longer restores password focus'

require_text "$SCENE_QML" 'readonly property int ghostTrailLength: 6' \
    'ghost cursor no longer uses the bounded six-sample trail'
require_text "$SCENE_QML" 'readonly property int cursorFadeDelayMs: 180' \
    'ghost cursor idle delay changed unexpectedly'
require_text "$SCENE_QML" 'readonly property int cursorFadeDurationMs: 320' \
    'ghost cursor fade duration changed unexpectedly'
require_text "$SCENE_QML" 'function triggerLogoExplosion(x, y)' \
    'shared scene has no click explosion path'
require_text "$SCENE_QML" 'running: root.logoExplosionActive' \
    'logo physics runs while idle'
reject_text "$SCENE_QML" 'required property bool audioReactive' \
    'shared scene still exposes logo audio-reactive state'
reject_text "$SCENE_QML" 'function updatePointerField(' \
    'ordinary pointer motion still drives logo deformation'

require_file "$WEATHER_QML" 'lockscreen weather cache reader QML is missing'
require_text "$WEATHER_QML" 'lockscreen-weather.json' \
    'weather cache reader does not use the dedicated local cache'
reject_text "$WEATHER_QML" 'https://' \
    'secure weather reader contains network behavior'

# Analyzer/helper assets remain available for the dedicated visualizer pass but
# are not instantiated solely for the logo anymore.
require_file "$AUDIO_QML" 'lockscreen audio analyzer component is missing'
require_file "$CAVA_CONFIG" 'lockscreen CAVA configuration is missing'
require_file "$AUDIO_HELPER" 'lockscreen audio helper is missing'
require_text "$AUDIO_HELPER" 'command -v cava >/dev/null 2>&1 || exit 0' \
    'audio helper does not safely tolerate missing CAVA'
reject_text "$AUDIO_HELPER" 'microphone' \
    'audio helper contains microphone capture behavior'

for token in logoPhysicsHz LockAudioAnalyzer LockWeatherCache weatherText mouseInteractive; do
    reject_text "${ROOT}/config/quickshell/awtarchy-lock/LockAuth.qml" "$token" \
        "authentication owner was coupled to optional lockscreen state: $token"
done

printf '%s\n' 'PASS: lockscreen click-only interactive effects contracts'
