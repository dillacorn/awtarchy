#!/usr/bin/env python3
from pathlib import Path

shell_path = Path("config/quickshell/awtarchy-lock/shell.qml")
surface_path = Path("config/quickshell/awtarchy-lock/LockSurface.qml")

shell = shell_path.read_text(encoding="utf-8")
surface = surface_path.read_text(encoding="utf-8")

# Secure shell owns one immutable presentation snapshot plus global auth/session
# settings. Each WlSessionLock surface resolves presentation independently.
if 'property var lockSharedProfile:' not in shell:
    anchor = '    property bool unlockRequested: false\n'
    if anchor not in shell:
        raise SystemExit("Task 7 shell root anchor missing")
    shell = shell.replace(
        anchor,
        anchor
        + '    property var lockSharedProfile: LockscreenPresentationState.sharedProfile(({}))\n'
        + '    property var lockMonitorOverrides: ({})\n',
        1,
    )

reset_anchor = '    function resetPreferences() {\n'
if 'lockSharedProfile = LockscreenPresentationState.sharedProfile(({}));' not in shell:
    if reset_anchor not in shell:
        raise SystemExit("Task 7 resetPreferences anchor missing")
    shell = shell.replace(
        reset_anchor,
        reset_anchor
        + '        lockSharedProfile = LockscreenPresentationState.sharedProfile(({}));\n'
        + '        lockMonitorOverrides = ({});\n',
        1,
    )

load_anchor = '''            if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
                resetPreferences();
                return;
            }

'''
load_insert = load_anchor + '''            lockSharedProfile = LockscreenPresentationState.sharedProfile(parsed);
            lockMonitorOverrides = LockscreenPresentationState.monitorOverrides(parsed);

'''
if 'lockSharedProfile = LockscreenPresentationState.sharedProfile(parsed);' not in shell:
    if load_anchor not in shell:
        raise SystemExit("Task 7 loadPreferences anchor missing")
    shell = shell.replace(load_anchor, load_insert, 1)

# Per-surface timezone ownership supersedes the old Shared-only secure timer.
shell = shell.replace('        Qt.callLater(root.refreshTimezoneValues);\n', '', 1)
timezone_runtime = '''    Process {
        id: timezoneProcess
        stdout: SplitParser { onRead: line => root.applyTimezoneValues(line) }
    }
    Timer { interval: 15000; repeat: true; running: root.lockTimezoneClocks.length > 0; triggeredOnStart: true; onTriggered: root.refreshTimezoneValues() }

'''
if timezone_runtime in shell:
    shell = shell.replace(timezone_runtime, '', 1)

# Remove Shared-only presentation services from the shell. Authentication and
# WlSessionLock remain global.
service_start = shell.find('    LockWeatherCache {\n')
service_end = shell.find('    WlSessionLock {\n')
if service_start >= 0 and service_end > service_start:
    shell = shell[:service_start] + shell[service_end:]
elif service_start >= 0 or service_end < 0:
    raise SystemExit("Task 7 shell presentation-service anchors are inconsistent")

component_start = shell.find('        surface: Component {\n            LockSurface {\n')
component_end = shell.find('        onSecureChanged: {\n', component_start)
if component_start < 0 or component_end < 0:
    raise SystemExit("Task 7 LockSurface component anchors missing")
new_component = '''        surface: Component {
            LockSurface {
                auth: lockAuth
                theme: lockTheme
                unlocking: root.unlockRequested
                sharedProfile: root.lockSharedProfile
                monitorOverrides: root.lockMonitorOverrides
                randomFormationMode: root.randomFormationMode
                logoPhysicsHz: root.lockLogoPhysicsHz
                mouseInteractive: root.lockMouseInteractive
                captureDirectory: root.captureDirectory
            }
        }

'''
shell = shell[:component_start] + new_component + shell[component_end:]

# ---------------------------------------------------------------------------
# LockSurface: resolve and own all presentation state by monitor.
# ---------------------------------------------------------------------------
if 'import "LockscreenPresentationState.js" as LockscreenPresentationState' not in surface:
    anchor = 'import Quickshell.Wayland\n'
    if anchor not in surface:
        raise SystemExit("Task 7 LockSurface import anchor missing")
    surface = surface.replace(
        anchor,
        anchor + 'import "LockscreenPresentationState.js" as LockscreenPresentationState\n',
        1,
    )

old_props = '''    required property var auth
    required property var theme
    required property bool unlocking
    required property string animationPreference
    required property string entryTransition
    required property int entryTransitionDuration
    required property int randomFormationMode
    required property int logoPhysicsHz
    required property bool mouseInteractive
    required property bool showLogo
    required property bool showTime
    required property bool showDate
    required property bool showUsername
    required property bool showWeather
    required property string weatherText
    required property string backgroundMode
    required property string wallpaperSource
    required property color backgroundColor
    required property string wallpaperFit
    required property real wallpaperFocalX
    required property real wallpaperFocalY
    required property string overlayMode
    required property real overlayStrength
    required property real wallpaperBlur
    required property string blurStyle
    required property var autoAccents
    required property var layout
    required property var customImages
    required property var timezoneClocks
    required property var timezoneValues
    required property var customTexts
    required property var visualizer
    required property var audioBands
    required property int backgroundOpacity
    required property string passwordMaskMode
    required property string passwordMaskCharacter
    required property string clockFormat
    required property string captureDirectory
'''
new_props = '''    required property var auth
    required property var theme
    required property bool unlocking
    required property var sharedProfile
    required property var monitorOverrides
    required property int randomFormationMode
    required property int logoPhysicsHz
    required property bool mouseInteractive
    required property string captureDirectory
'''
if old_props in surface:
    surface = surface.replace(old_props, new_props, 1)
elif 'required property var sharedProfile' not in surface:
    raise SystemExit("Task 7 LockSurface property block anchor missing")

old_capture = '''    readonly property string captureOutputName: root.screen && root.screen.name
        ? String(root.screen.name) : ""
'''
new_capture = '''    readonly property string monitorName: root.screen && root.screen.name
        ? String(root.screen.name) : ""
    readonly property var profile: LockscreenPresentationState.profileForMonitor(
        root.sharedProfile, root.monitorOverrides, root.monitorName)
    readonly property string captureOutputName: root.monitorName
'''
if old_capture in surface:
    surface = surface.replace(old_capture, new_capture, 1)
elif 'readonly property var profile: LockscreenPresentationState.profileForMonitor(' not in surface:
    raise SystemExit("Task 7 LockSurface monitor identity anchor missing")

service_anchor = '''    readonly property string timezoneBackend: configHome
        + "/hypr/scripts/quickshell_lockscreen_timezones.sh"

'''
service_block = service_anchor + '''    LockWallpaperState {
        id: lockWallpaperState
        path: root.profile.lockscreen_wallpaper_path
    }

    LockContrastCache {
        id: lockContrastCache
        monitorName: root.monitorName
    }

    LockWeatherCache {
        id: lockWeatherCache
        enabled: root.profile.lockscreen_show_weather
        units: root.profile.lockscreen_weather_units
    }

    LockAudioAnalyzer {
        id: lockAudioAnalyzer
        enabled: root.profile.lockscreen_visualizer.enabled
        performanceMode: root.profile.lockscreen_visualizer.performance
    }

'''
if 'path: root.profile.lockscreen_wallpaper_path' not in surface:
    if service_anchor not in surface:
        raise SystemExit("Task 7 LockSurface service anchor missing")
    surface = surface.replace(service_anchor, service_block, 1)

surface = surface.replace(
    '        const clocks = root.timezoneClocks || [];\n',
    '        const clocks = root.profile.lockscreen_timezone_clocks || [];\n',
    1,
)
surface = surface.replace(
    '        running: Array.isArray(root.timezoneClocks) && root.timezoneClocks.length > 0\n',
    '        running: Array.isArray(root.profile.lockscreen_timezone_clocks)\n            && root.profile.lockscreen_timezone_clocks.length > 0\n',
    1,
)
surface = surface.replace(
    '    onTimezoneClocksChanged: Qt.callLater(() => root.refreshTimezoneValues())\n',
    '    onProfileChanged: Qt.callLater(() => root.refreshTimezoneValues())\n',
    1,
)

scene_replacements = {
    'animationPreference: root.animationPreference': 'animationPreference: root.profile.lockscreen_animation',
    'showLogo: root.showLogo': 'showLogo: root.profile.lockscreen_show_logo',
    'showTime: root.showTime': 'showTime: root.profile.lockscreen_show_time',
    'showDate: root.showDate': 'showDate: root.profile.lockscreen_show_date',
    'showUsername: root.showUsername': 'showUsername: root.profile.lockscreen_show_username',
    'showWeather: root.showWeather': 'showWeather: root.profile.lockscreen_show_weather',
    'weatherText: root.weatherText': 'weatherText: lockWeatherCache.summary',
    'backgroundMode: root.backgroundMode': 'backgroundMode: root.profile.lockscreen_background',
    'wallpaperSource: root.wallpaperSource': 'wallpaperSource: lockWallpaperState.source',
    'backgroundColor: root.backgroundColor': 'backgroundColor: root.profile.lockscreen_background_color',
    'wallpaperFit: root.wallpaperFit': 'wallpaperFit: root.profile.lockscreen_wallpaper_fit',
    'wallpaperFocalX: root.wallpaperFocalX': 'wallpaperFocalX: root.profile.lockscreen_wallpaper_focal_x',
    'wallpaperFocalY: root.wallpaperFocalY': 'wallpaperFocalY: root.profile.lockscreen_wallpaper_focal_y',
    'overlayMode: root.overlayMode': 'overlayMode: root.profile.lockscreen_overlay_mode',
    'overlayStrength: root.overlayStrength': 'overlayStrength: root.profile.lockscreen_overlay_strength',
    'wallpaperBlur: root.wallpaperBlur': 'wallpaperBlur: root.profile.lockscreen_wallpaper_blur',
    'blurStyle: root.blurStyle': 'blurStyle: root.profile.lockscreen_blur_style',
    'autoAccents: root.autoAccents': 'autoAccents: lockContrastCache.colors',
    'layout: root.layout': 'layout: root.profile.lockscreen_layout',
    'customImages: root.customImages': 'customImages: root.profile.lockscreen_custom_images',
    'timezoneClocks: root.timezoneClocks': 'timezoneClocks: root.profile.lockscreen_timezone_clocks',
    'customTexts: root.customTexts': 'customTexts: root.profile.lockscreen_custom_texts',
    'visualizer: root.visualizer': 'visualizer: root.profile.lockscreen_visualizer',
    'audioBands: root.audioBands': 'audioBands: lockAudioAnalyzer.bands',
    'backgroundOpacity: root.backgroundOpacity': 'backgroundOpacity: root.profile.lockscreen_background_opacity',
    'passwordMaskMode: root.passwordMaskMode': 'passwordMaskMode: root.profile.lockscreen_password_mask_mode',
    'passwordMaskCharacter: root.passwordMaskCharacter': 'passwordMaskCharacter: root.profile.lockscreen_password_mask_character',
    'clockFormat: root.clockFormat': 'clockFormat: root.profile.lockscreen_clock_format',
}
for old, new in scene_replacements.items():
    if old in surface:
        surface = surface.replace(old, new, 1)
    elif new not in surface:
        raise SystemExit(f"Task 7 LockScene binding anchor missing: {old}")

surface = surface.replace(
    '        mode: root.entryTransition\n',
    '        mode: root.profile.lockscreen_entry_transition\n',
    1,
)
surface = surface.replace(
    '        duration: root.entryTransitionDuration\n',
    '        duration: root.profile.lockscreen_entry_transition_duration\n',
    1,
)

shell_path.write_text(shell, encoding="utf-8")
surface_path.write_text(surface, encoding="utf-8")
