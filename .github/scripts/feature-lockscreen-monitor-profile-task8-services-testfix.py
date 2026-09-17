#!/usr/bin/env python3
from pathlib import Path

path = Path("tests/test-quickshell-lockscreen-runtime-services.sh")
text = path.read_text()
replacements = [
    (
'''require_text "$WEATHER" 'BarState.lockscreenShowWeather()' \\
    'LockscreenWeather does not honor the saved Weather toggle'
require_text "$WEATHER" 'BarState.lockscreenWeatherLocation()' \\
    'LockscreenWeather does not use the explicit saved location'
''',
'''require_text "$WEATHER" 'if (profile.lockscreen_show_weather === true)' \\
    'LockscreenWeather does not honor per-profile Weather visibility'
require_text "$WEATHER" 'addProfile(BarState.lockscreenSharedProfile());' \\
    'LockscreenWeather does not include the Shared profile when deriving refresh modes'
require_text "$WEATHER" 'BarState.lockscreenMonitorOverrides()' \\
    'LockscreenWeather does not include Individual monitor profiles when deriving refresh modes'
require_text "$WEATHER" 'BarState.lockscreenWeatherLocation()' \\
    'LockscreenWeather does not use the explicit saved location'
'''),
    (
'''require_text "$LOCK_SHELL" 'lockWallpaperPath = normalizedWallpaperPath(parsed.lockscreen_wallpaper_path);' \\
    'secure lock shell does not load the dedicated wallpaper path from persisted state'
require_text "$LOCK_SHELL" 'path: root.lockWallpaperPath' \\
    'secure lock wallpaper reader does not receive the normalized persisted path'
''',
'''require_text "$LOCK_SHELL" 'lockSharedProfile = LockscreenPresentationState.sharedProfile(parsed);' \\
    'secure lock shell does not load the Shared presentation profile from persisted state'
require_text "$LOCK_SHELL" 'lockMonitorOverrides = LockscreenPresentationState.monitorOverrides(parsed);' \\
    'secure lock shell does not load Individual monitor presentation profiles from persisted state'
'''),
    (
'''require_text "$LOCK_SHELL" 'LockWallpaperState {' \\
    'secure lock shell does not own a local wallpaper-state reader'
require_text "$LOCK_SHELL" 'wallpaperSource: lockWallpaperState.source' \\
    'secure lock surfaces do not receive the local wallpaper source'
''',
'''require_text "$SURFACE" 'LockWallpaperState {' \\
    'secure lock surface does not own its per-monitor local wallpaper-state reader'
require_text "$SURFACE" 'path: root.profile.lockscreen_wallpaper_path' \\
    'secure wallpaper reader does not use the effective monitor profile path'
require_text "$SURFACE" 'wallpaperSource: lockWallpaperState.source' \\
    'secure lock scene does not receive the local per-monitor wallpaper source'
''')
]

# Add secure surface path alongside the existing shell path declaration.
old_decl = 'LOCK_SHELL="${ROOT}/config/quickshell/awtarchy-lock/shell.qml"\nLOCK_SCENE='
new_decl = 'LOCK_SHELL="${ROOT}/config/quickshell/awtarchy-lock/shell.qml"\nSURFACE="${ROOT}/config/quickshell/awtarchy-lock/LockSurface.qml"\nLOCK_SCENE='
if old_decl not in text:
    raise SystemExit("runtime-services secure path declaration anchor not found")
text = text.replace(old_decl, new_decl, 1)

for old, new in replacements:
    if old not in text:
        raise SystemExit("runtime-services legacy service block not found")
    text = text.replace(old, new, 1)
path.write_text(text)
