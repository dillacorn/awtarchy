#!/usr/bin/env python3
from pathlib import Path

path = Path("tests/test-quickshell-lockscreen-animation-preference.sh")
text = path.read_text(encoding="utf-8")

old = '''require_text "$SHELL_QML" 'animationPreference: root.lockAnimationPreference' \\
    'lock surfaces do not receive the saved animation preference'\n'''
new = '''require_text "$SURFACE_QML" 'animationPreference: root.profile.lockscreen_animation' \\
    'lock surface does not resolve the saved animation preference from its monitor profile'\n'''
if old in text:
    text = text.replace(old, new, 1)
elif new not in text:
    raise SystemExit("animation preference shell migration anchor missing")

old = '''# LockSurface keeps the secure pass-through properties; LockScene implements the\n# actual presentation families shared with the unlocked editor.\nrequire_text "$SURFACE_QML" 'required property string animationPreference' \\
    'lock surface does not receive the animation preference'\nrequire_text "$SURFACE_QML" 'required property int randomFormationMode' \\
    'lock surface does not receive the shared random family'\nrequire_text "$SURFACE_QML" 'animationPreference: root.animationPreference' \\
    'lock surface does not pass animation preference into the shared scene'\n'''
new = '''# LockSurface resolves presentation from the effective monitor profile;\n# LockScene implements the actual families shared with the unlocked editor.\nrequire_text "$SURFACE_QML" 'required property var sharedProfile' \\
    'lock surface does not receive the Shared presentation snapshot'\nrequire_text "$SURFACE_QML" 'required property var monitorOverrides' \\
    'lock surface does not receive monitor presentation overrides'\nrequire_text "$SURFACE_QML" 'readonly property var profile: LockscreenPresentationState.profileForMonitor(' \\
    'lock surface does not resolve its effective monitor profile'\nrequire_text "$SURFACE_QML" 'required property int randomFormationMode' \\
    'lock surface does not receive the shared per-lock random family'\nrequire_text "$SURFACE_QML" 'animationPreference: root.profile.lockscreen_animation' \\
    'lock surface does not pass its profile animation preference into the shared scene'\n'''
if old in text:
    text = text.replace(old, new, 1)
elif new not in text:
    raise SystemExit("animation preference surface migration anchor missing")

old = '''# Pass 3 legitimately owns one analyzer for the standalone visualizer. Its\n# lifecycle and output must be tied to visualizer state, never logo animation.\nrequire_count "$SHELL_QML" 'LockAudioAnalyzer {' 1 \\
    'secure lock shell does not own exactly one standalone visualizer analyzer'\nrequire_text "$SHELL_QML" 'enabled: root.lockVisualizer.enabled' \\
    'secure analyzer lifecycle is not tied to standalone visualizer state'\nrequire_text "$SHELL_QML" 'audioBands: lockAudioAnalyzer.bands' \\
    'secure analyzer output is not routed as visualizer presentation data'\n'''
new = '''# Each secure monitor surface owns one analyzer for that profile's standalone\n# visualizer. It remains independent from logo formation animation.\nrequire_count "$SURFACE_QML" 'LockAudioAnalyzer {' 1 \\
    'secure lock surface does not own exactly one standalone visualizer analyzer'\nrequire_text "$SURFACE_QML" 'enabled: root.profile.lockscreen_visualizer.enabled' \\
    'secure analyzer lifecycle is not tied to the monitor-profile visualizer state'\nrequire_text "$SURFACE_QML" 'audioBands: lockAudioAnalyzer.bands' \\
    'secure analyzer output is not routed as visualizer presentation data'\n'''
if old in text:
    text = text.replace(old, new, 1)
elif new not in text:
    raise SystemExit("visualizer analyzer migration anchor missing")

path.write_text(text, encoding="utf-8")

path = Path("tests/test-quickshell-lockscreen-background-composition.sh")
text = path.read_text(encoding="utf-8")
old = '''# Secure shell independently validates persisted presentation fields.\nrequire_text "$LOCK_SHELL" 'readonly property string wallpaperFit:' 'secure shell does not normalize wallpaper fit'\nrequire_text "$LOCK_SHELL" 'readonly property real wallpaperFocalX:' 'secure shell does not normalize focal x'\nrequire_text "$LOCK_SHELL" 'readonly property real wallpaperFocalY:' 'secure shell does not normalize focal y'\nrequire_text "$LOCK_SHELL" 'readonly property string overlayMode:' 'secure shell does not normalize overlay mode'\nrequire_text "$LOCK_SHELL" 'readonly property int overlayStrength:' 'secure shell does not normalize overlay strength'\nrequire_text "$LOCK_SHELL" 'readonly property int wallpaperBlur:' 'secure shell does not normalize wallpaper blur'\nrequire_text "$LOCK_SHELL" 'readonly property string blurStyle:' 'secure shell does not normalize blur style'\nrequire_text "$LOCK_SHELL" 'wallpaperFit: root.wallpaperFit' 'secure scene does not receive wallpaper fit'\nrequire_text "$LOCK_SHELL" 'overlayStrength: root.overlayStrength' 'secure scene does not receive overlay strength'\nrequire_text "$LOCK_SHELL" 'wallpaperBlur: root.wallpaperBlur' 'secure scene does not receive blur'\nrequire_text "$LOCK_SHELL" 'blurStyle: root.blurStyle' 'secure scene does not receive blur style'\n'''
new = '''# Secure shell snapshots normalized presentation profiles, and each secure\n# surface binds composition fields from its effective monitor profile.\nrequire_text "$LOCK_SHELL" 'lockSharedProfile = LockscreenPresentationState.sharedProfile(parsed);' 'secure shell does not normalize the Shared presentation snapshot'\nrequire_text "$LOCK_SHELL" 'lockMonitorOverrides = LockscreenPresentationState.monitorOverrides(parsed);' 'secure shell does not normalize monitor presentation overrides'\nrequire_text "$SURFACE" 'wallpaperFit: root.profile.lockscreen_wallpaper_fit' 'secure scene does not receive profile wallpaper fit'\nrequire_text "$SURFACE" 'wallpaperFocalX: root.profile.lockscreen_wallpaper_focal_x' 'secure scene does not receive profile focal x'\nrequire_text "$SURFACE" 'wallpaperFocalY: root.profile.lockscreen_wallpaper_focal_y' 'secure scene does not receive profile focal y'\nrequire_text "$SURFACE" 'overlayMode: root.profile.lockscreen_overlay_mode' 'secure scene does not receive profile overlay mode'\nrequire_text "$SURFACE" 'overlayStrength: root.profile.lockscreen_overlay_strength' 'secure scene does not receive profile overlay strength'\nrequire_text "$SURFACE" 'wallpaperBlur: root.profile.lockscreen_wallpaper_blur' 'secure scene does not receive profile blur'\nrequire_text "$SURFACE" 'blurStyle: root.profile.lockscreen_blur_style' 'secure scene does not receive profile blur style'\n'''
if old in text:
    text = text.replace(old, new, 1)
elif new not in text:
    raise SystemExit("background composition monitor-profile migration anchor missing")
path.write_text(text, encoding="utf-8")
