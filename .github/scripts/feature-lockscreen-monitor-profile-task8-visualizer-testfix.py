#!/usr/bin/env python3
from pathlib import Path

path = Path("tests/test-quickshell-lockscreen-visualizer-transparency.sh")
text = path.read_text()
old = '''# Secure root owns exactly one analyzer and every surface receives only
# presentation data.
require_count "$LOCK_SHELL" 'LockAudioAnalyzer {' 1 \\
    'secure shell does not own exactly one audio analyzer'
require_text "$LOCK_SHELL" 'enabled: root.lockVisualizer.enabled' \\
    'secure analyzer lifecycle does not follow visualizer enabled state'
require_text "$LOCK_SHELL" 'audioBands: lockAudioAnalyzer.bands' \\
    'secure surfaces do not receive the shared analyzer spectrum'
require_text "$LOCK_SHELL" 'visualizer: root.lockVisualizer' \\
    'secure surfaces do not receive normalized visualizer state'
require_text "$LOCK_SHELL" 'backgroundOpacity: root.lockBackgroundOpacity' \\
    'secure surfaces do not receive normalized background opacity'

# LockSurface remains the secure authority-facing surface. Transparency is
# backing/presentation only; auth and password ownership remain unchanged.
require_text "$SURFACE" 'WlSessionLockSurface {' \\
    'secure surface is no longer a WlSessionLockSurface'
require_text "$SURFACE" 'color: "transparent"' \\
    'secure surface backing still forces opaque black'
require_text "$SURFACE" 'required property var visualizer' \\
    'secure surface has no visualizer presentation input'
require_text "$SURFACE" 'required property var audioBands' \\
    'secure surface has no analyzer spectrum input'
require_text "$SURFACE" 'required property int backgroundOpacity' \\
    'secure surface has no background-opacity input'
'''
new = '''# Every secure output owns its analyzer so Individual monitor profiles can
# select visualizer lifecycle/performance independently without leaking state
# across surfaces.
require_count "$SURFACE" 'LockAudioAnalyzer {' 1 \\
    'secure lock surface does not own exactly one per-monitor audio analyzer'
require_text "$SURFACE" 'enabled: root.profile.lockscreen_visualizer.enabled' \\
    'per-monitor visualizer enabled state does not gate analyzer lifecycle'
require_text "$SURFACE" 'performanceMode: root.profile.lockscreen_visualizer.performance' \\
    'per-monitor visualizer performance mode does not reach the analyzer'
require_text "$SURFACE" 'audioBands: lockAudioAnalyzer.bands' \\
    'secure scene does not receive the local analyzer spectrum'
require_text "$SURFACE" 'visualizer: root.profile.lockscreen_visualizer' \\
    'secure scene does not receive the effective monitor visualizer state'
require_text "$SURFACE" 'backgroundOpacity: root.profile.lockscreen_background_opacity' \\
    'secure scene does not receive the effective monitor background opacity'
reject_text "$LOCK_SHELL" 'LockAudioAnalyzer {' \\
    'secure shell still owns a Shared-only audio analyzer'

# LockSurface remains the secure authority-facing surface. Transparency is
# confined to the frozen pre-lock composition while the session-lock surface
# itself keeps an opaque black fail-safe backing.
require_text "$SURFACE" 'WlSessionLockSurface {' \\
    'secure surface is no longer a WlSessionLockSurface'
require_text "$SURFACE" 'color: "#000000"' \\
    'secure surface lost its opaque black fail-safe backing'
require_text "$SURFACE" 'desktopBackingSource: desktopBacking' \\
    'secure transparency no longer uses the frozen pre-lock backing'
'''
if old not in text:
    raise SystemExit("visualizer-transparency legacy secure analyzer block not found")
path.write_text(text.replace(old, new, 1))
