#!/usr/bin/env python3
from pathlib import Path

# Migrate assertions whose old shell/editor singleton presentation API is
# intentionally replaced by complete per-monitor presentation profiles.

path = Path("tests/test-quickshell-lockscreen-runtime-acceptance-187.sh")
text = path.read_text(encoding="utf-8")
old = '''has "$SURFACE" 'required property int entryTransitionDuration' 'secure surface duration input is missing'\nhas "$SHELL" 'entryTransitionDuration: root.lockEntryTransitionDuration' 'secure shell does not pass duration'\n'''
new = '''has "$SURFACE" 'duration: root.profile.lockscreen_entry_transition_duration' 'secure surface transition duration is not monitor-profile local'\nhas "$SHELL" 'sharedProfile: root.lockSharedProfile' 'secure shell does not pass the Shared presentation snapshot'\nhas "$SHELL" 'monitorOverrides: root.lockMonitorOverrides' 'secure shell does not pass monitor presentation overrides'\n'''
if old in text:
    text = text.replace(old, new, 1)
elif new not in text:
    raise SystemExit("Task 7 runtime acceptance migration anchor missing")
path.write_text(text, encoding="utf-8")

path = Path("tests/test-quickshell-lockscreen-element-system.sh")
text = path.read_text(encoding="utf-8")
old = '''require_text "$SURFACE" 'required property var customImages' \\
    'secure lock surface does not pass custom images presentation-only'\nrequire_text "$LOCK_SHELL" 'property var lockCustomImages: []' \\
    'secure shell has no safe custom-image default'\nrequire_text "$LOCK_SHELL" 'function normalizedCustomImages(value)' \\
    'secure shell does not re-normalize persisted custom images'\nrequire_text "$LOCK_SHELL" 'scale > 100.00' \\
    'secure shell still uses an old scale ceiling'\nrequire_text "$LOCK_SHELL" 'customImages: root.lockCustomImages' \\
    'secure shell does not pass normalized images to the surface'\n'''
new = '''require_text "$SURFACE" 'required property var sharedProfile' \\
    'secure lock surface has no Shared presentation snapshot'\nrequire_text "$SURFACE" 'required property var monitorOverrides' \\
    'secure lock surface has no monitor override snapshot'\nrequire_text "$SURFACE" 'readonly property var profile: LockscreenPresentationState.profileForMonitor(' \\
    'secure lock surface does not resolve a normalized monitor profile'\nrequire_text "$SURFACE" 'customImages: root.profile.lockscreen_custom_images' \\
    'secure lock surface does not use profile-normalized custom media'\nrequire_text "$LOCK_SHELL" 'lockSharedProfile = LockscreenPresentationState.sharedProfile(parsed);' \\
    'secure shell does not normalize the Shared presentation snapshot'\nrequire_text "$LOCK_SHELL" 'lockMonitorOverrides = LockscreenPresentationState.monitorOverrides(parsed);' \\
    'secure shell does not normalize monitor presentation overrides'\n'''
if old in text:
    text = text.replace(old, new, 1)
elif new not in text:
    raise SystemExit("Task 7 element-system migration anchor missing")
path.write_text(text, encoding="utf-8")

path = Path("tests/test-quickshell-lockscreen-editor.sh")
text = path.read_text(encoding="utf-8")
old = '''require_text "$DESKTOP_WEATHER" 'BarState.lockscreenShowWeather()' \\
    'unlocked weather refresh service is not gated by the Weather toggle'\nreject_text "$DESKTOP_WEATHER" '&& configuredLocation.length > 0' \\
    'unlocked weather refresh still requires manual location configuration'\nrequire_text "$DESKTOP_WEATHER" 'refreshProcess.exec([root.weatherHelper, "refresh", location, units])' \\
    'unlocked weather refresh does not pass location and units through to the helper'\n'''
new = '''require_text "$DESKTOP_WEATHER" 'profile.lockscreen_show_weather === true' \\
    'unlocked weather refresh service is not gated by each profile Weather toggle'\nreject_text "$DESKTOP_WEATHER" '&& configuredLocation.length > 0' \\
    'unlocked weather refresh still requires manual location configuration'\nrequire_text "$DESKTOP_WEATHER" 'refreshProcess.exec([root.weatherHelper, "refresh-set", location, JSON.stringify(modes)])' \\
    'unlocked weather refresh does not pass the profile unit set through to the helper'\n'''
if old in text:
    text = text.replace(old, new, 1)
elif new not in text:
    raise SystemExit("Task 7 editor weather migration anchor missing")
path.write_text(text, encoding="utf-8")
