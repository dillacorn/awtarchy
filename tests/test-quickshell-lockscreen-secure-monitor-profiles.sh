#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL="$ROOT/config/quickshell/awtarchy-lock/shell.qml"
SURFACE="$ROOT/config/quickshell/awtarchy-lock/LockSurface.qml"
AUTH="$ROOT/config/quickshell/awtarchy-lock/LockAuth.qml"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
require_text() {
    grep -Fq -- "$2" "$1" || fail "$3"
}
reject_text() {
    ! grep -Fq -- "$2" "$1" || fail "$3"
}

# Secure shell loads presentation snapshots once, while authentication/session
# controls remain global.
require_text "$SHELL" 'property var lockSharedProfile:' \
    'secure shell has no Shared profile snapshot'
require_text "$SHELL" 'property var lockMonitorOverrides:' \
    'secure shell has no monitor override snapshot'
require_text "$SHELL" 'lockSharedProfile = LockscreenPresentationState.sharedProfile(parsed);' \
    'secure shell does not load Shared presentation through the resolver'
require_text "$SHELL" 'lockMonitorOverrides = LockscreenPresentationState.monitorOverrides(parsed);' \
    'secure shell does not load monitor overrides through the resolver'
require_text "$SHELL" 'lockLogoPhysicsHz = normalizedLogoPhysicsHz(parsed.lockscreen_logo_physics_hz);' \
    'logo physics stopped being a global secure-session setting'
require_text "$SHELL" 'lockMouseInteractive = normalizedBoolean(parsed.lockscreen_mouse_interactive, true);' \
    'mouse interaction stopped being a global secure-session setting'
require_text "$SHELL" 'LockAuth {' 'secure shell no longer owns the single LockAuth instance'
require_text "$SHELL" 'auth: lockAuth' 'secure surfaces no longer share the single LockAuth owner'

# Presentation services must live on each WlSessionLock surface so two monitors
# can render different media, weather, accents, clocks, and visualizers.
require_text "$SURFACE" 'import "LockscreenPresentationState.js" as LockscreenPresentationState' \
    'secure surface does not import the monitor profile resolver'
require_text "$SURFACE" 'required property var sharedProfile' \
    'secure surface has no Shared profile input'
require_text "$SURFACE" 'required property var monitorOverrides' \
    'secure surface has no monitor override input'
require_text "$SURFACE" 'readonly property string monitorName:' \
    'secure surface does not derive its monitor name'
require_text "$SURFACE" 'String(root.screen.name)' \
    'secure surface monitor identity does not use screen.name'
require_text "$SURFACE" 'readonly property var profile: LockscreenPresentationState.profileForMonitor(' \
    'secure surface does not resolve its own effective profile'
require_text "$SURFACE" 'root.sharedProfile, root.monitorOverrides, root.monitorName)' \
    'secure surface resolver does not use Shared + monitor overrides + monitor name'
require_text "$SURFACE" 'LockWallpaperState {' \
    'secure surface does not own its wallpaper service'
require_text "$SURFACE" 'path: root.profile.lockscreen_wallpaper_path' \
    'secure surface wallpaper does not use its effective profile'
require_text "$SURFACE" 'LockContrastCache {' \
    'secure surface does not own its contrast cache'
require_text "$SURFACE" 'monitorName: root.monitorName' \
    'secure surface contrast cache is not keyed by monitor'
require_text "$SURFACE" 'LockWeatherCache {' \
    'secure surface does not own its weather cache'
require_text "$SURFACE" 'enabled: root.profile.lockscreen_show_weather' \
    'secure surface weather visibility is not profile-local'
require_text "$SURFACE" 'units: root.profile.lockscreen_weather_units' \
    'secure surface weather units are not profile-local'
require_text "$SURFACE" 'LockAudioAnalyzer {' \
    'secure surface does not own its audio analyzer'
require_text "$SURFACE" 'enabled: root.profile.lockscreen_visualizer.enabled' \
    'secure surface visualizer activation is not profile-local'
require_text "$SURFACE" 'performanceMode: root.profile.lockscreen_visualizer.performance' \
    'secure surface visualizer performance is not profile-local'

# Representative LockScene inputs must bind to the effective surface profile.
for binding in \
    'animationPreference: root.profile.lockscreen_animation' \
    'showLogo: root.profile.lockscreen_show_logo' \
    'showWeather: root.profile.lockscreen_show_weather' \
    'backgroundMode: root.profile.lockscreen_background' \
    'layout: root.profile.lockscreen_layout' \
    'customImages: root.profile.lockscreen_custom_images' \
    'timezoneClocks: root.profile.lockscreen_timezone_clocks' \
    'customTexts: root.profile.lockscreen_custom_texts' \
    'visualizer: root.profile.lockscreen_visualizer' \
    'backgroundOpacity: root.profile.lockscreen_background_opacity' \
    'clockFormat: root.profile.lockscreen_clock_format'; do
    require_text "$SURFACE" "$binding" "secure surface missing profile binding: $binding"
done

# Transition/security invariants survive the presentation split.
require_text "$SURFACE" 'readonly property string captureOutputName:' \
    'secure surface lost per-output transition capture lookup'
require_text "$SURFACE" 'interval: 750' \
    'secure video pre-roll timeout changed'
require_text "$SURFACE" 'autoStart: false' \
    'secure transition unexpectedly auto-starts'
require_text "$SURFACE" 'required property var auth' \
    'secure surface no longer receives the shared auth owner'

# Authentication must never select or normalize presentation profiles.
reject_text "$AUTH" 'LockscreenPresentationState' \
    'LockAuth contains presentation profile logic'
reject_text "$AUTH" 'lockscreen_monitor_overrides' \
    'LockAuth reads monitor presentation overrides'
reject_text "$AUTH" 'profileForMonitor' \
    'LockAuth selects a monitor presentation profile'

printf '%s\n' 'PASS: secure lockscreen per-monitor profile contracts'
