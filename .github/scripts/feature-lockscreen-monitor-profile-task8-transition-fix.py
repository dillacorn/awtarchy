#!/usr/bin/env python3
from pathlib import Path

path = Path("config/quickshell/awtarchy-lock/shell.qml")
text = path.read_text(encoding="utf-8")

anchor = '''    property var lockSharedProfile: LockscreenPresentationState.sharedProfile(({}))
    property var lockMonitorOverrides: ({})
'''
insert = anchor + '''    readonly property int captureCleanupTransitionDuration: {
        let maximum = Number(root.lockSharedProfile.lockscreen_entry_transition_duration);
        if (!Number.isFinite(maximum))
            maximum = 1800;
        const overrides = root.lockMonitorOverrides;
        if (overrides && typeof overrides === "object" && !Array.isArray(overrides)) {
            for (const name of Object.keys(overrides)) {
                const profile = overrides[name];
                if (profile && typeof profile === "object" && !Array.isArray(profile))
                    maximum = Math.max(maximum, Number(profile.lockscreen_entry_transition_duration));
            }
        }
        return Math.max(800, Math.min(6000, Math.round(maximum)));
    }
'''
if 'readonly property int captureCleanupTransitionDuration:' not in text:
    if anchor not in text:
        raise SystemExit("capture cleanup duration property anchor missing")
    text = text.replace(anchor, insert, 1)

old = '        interval: Math.max(3000, Math.min(8000, root.lockEntryTransitionDuration + 2000))\n'
new = '        interval: Math.max(3000, Math.min(8000, root.captureCleanupTransitionDuration + 2000))\n'
if old in text:
    text = text.replace(old, new, 1)
elif new not in text:
    raise SystemExit("capture cleanup timer anchor missing")

path.write_text(text, encoding="utf-8")
