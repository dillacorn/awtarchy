#!/usr/bin/env python3
from pathlib import Path

path = Path("tests/test-quickshell-lockscreen-entry-transitions.sh")
text = path.read_text(encoding="utf-8")

old = '''contains "$SHELL" 'property string lockEntryTransition: "fade"' \\
    'secure shell transition state is missing'\ncontains "$SHELL" 'property int lockEntryTransitionDuration: 1800' \\
    'secure shell does not use the approved 1800ms default'\ncontains "$SHELL" 'Math.max(800, Math.min(6000' \\
    'secure shell does not clamp transition duration to 800-6000ms'\ncontains "$SHELL" 'entryTransition: root.lockEntryTransition' \\
    'secure shell does not pass entry transition to lock surfaces'\ncontains "$SHELL" 'entryTransitionDuration: root.lockEntryTransitionDuration' \\
    'secure shell does not pass transition duration to lock surfaces'\n'''
new = '''contains "$SHELL" 'lockSharedProfile = LockscreenPresentationState.sharedProfile(parsed);' \\
    'secure shell does not snapshot the Shared presentation profile'\ncontains "$SHELL" 'lockMonitorOverrides = LockscreenPresentationState.monitorOverrides(parsed);' \\
    'secure shell does not snapshot Individual presentation profiles'\ncontains "$SURFACE" 'mode: root.profile.lockscreen_entry_transition' \\
    'secure surface does not resolve entry transition from its monitor profile'\ncontains "$SURFACE" 'duration: root.profile.lockscreen_entry_transition_duration' \\
    'secure surface does not resolve transition duration from its monitor profile'\ncontains "$SHELL" 'readonly property int captureCleanupTransitionDuration:' \\
    'secure shell does not retain captures for monitor-local transition durations'\n'''
if old in text:
    text = text.replace(old, new, 1)
elif new not in text:
    raise SystemExit("entry-transition profile migration anchor missing")

path.write_text(text, encoding="utf-8")
