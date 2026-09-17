#!/usr/bin/env python3
from pathlib import Path

path = Path("tests/test-quickshell-lockscreen-runtime-regressions.sh")
text = path.read_text()
replacements = [
    (
'''require_text "$SURFACE_QML" 'required property string animationPreference' \\
    'lock surface does not receive the selected animation preference'
require_text "$SURFACE_QML" 'required property int randomFormationMode' \\
    'lock surface does not receive the shared random formation family'
''',
'''require_text "$SURFACE_QML" 'animationPreference: root.profile.lockscreen_animation' \\
    'lock scene does not resolve the selected animation preference from the effective monitor profile'
require_text "$SURFACE_QML" 'required property int randomFormationMode' \\
    'lock surface does not receive the shared random formation family'
'''),
    (
'''require_text "$SURFACE_QML" 'required property bool showTime' \\
    'lockscreen does not carry optional time display state'
require_text "$SURFACE_QML" 'required property bool showDate' \\
    'lockscreen does not carry optional date display state'
require_text "$SURFACE_QML" 'required property bool showUsername' \\
    'lockscreen does not carry optional username display state'
''',
'''require_text "$SURFACE_QML" 'showTime: root.profile.lockscreen_show_time' \\
    'lockscreen does not resolve optional time display state from the effective monitor profile'
require_text "$SURFACE_QML" 'showDate: root.profile.lockscreen_show_date' \\
    'lockscreen does not resolve optional date display state from the effective monitor profile'
require_text "$SURFACE_QML" 'showUsername: root.profile.lockscreen_show_username' \\
    'lockscreen does not resolve optional username display state from the effective monitor profile'
''')
]
for old, new in replacements:
    if old not in text:
        raise SystemExit("runtime-regressions legacy surface block not found")
    text = text.replace(old, new, 1)
path.write_text(text)
