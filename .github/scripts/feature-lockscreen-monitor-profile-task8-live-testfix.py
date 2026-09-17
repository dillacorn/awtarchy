#!/usr/bin/env python3
from pathlib import Path

path = Path("tests/test-quickshell-lockscreen-live-editor.sh")
text = path.read_text()
old = '''require_text "$LOCK_SHELL" 'LockContrastCache {' \\
    'secure lock shell does not construct the cache-only contrast reader'
require_text "$SURFACE" 'required property var autoAccents' \\
    'secure lock surface does not receive per-element automatic contrast colors'

require_text "$BAR_STATE" 'function lockscreenShowLogo()' \\
    'BarState has no normalized logo visibility reader'
require_text "$LOCK_SHELL" 'property bool lockShowLogo: true' \\
    'secure lock shell has no safe logo visibility default'
require_text "$LOCK_SHELL" 'showLogo: root.lockShowLogo' \\
    'secure lock surface does not receive saved logo visibility'
require_text "$SURFACE" 'required property bool showLogo' \\
    'secure surface does not pass logo visibility to the shared scene'
'''
new = '''require_text "$SURFACE" 'LockContrastCache {' \\
    'secure lock surface does not construct the per-monitor cache-only contrast reader'
require_text "$SURFACE" 'monitorName: root.monitorName' \\
    'secure contrast reader is not scoped to the current monitor'
require_text "$SURFACE" 'autoAccents: lockContrastCache.colors' \\
    'secure lock scene does not receive the local per-monitor contrast colors'

require_text "$BAR_STATE" 'function lockscreenShowLogo()' \\
    'BarState has no normalized logo visibility reader'
require_text "$SURFACE" 'showLogo: root.profile.lockscreen_show_logo' \\
    'secure surface does not resolve logo visibility from the effective monitor profile'
'''
if old not in text:
    raise SystemExit("live-editor legacy secure presentation block not found")
path.write_text(text.replace(old, new, 1))
