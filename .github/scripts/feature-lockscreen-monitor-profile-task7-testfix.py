#!/usr/bin/env python3
from pathlib import Path

path = Path("tests/test-quickshell-lockscreen-runtime-acceptance-187.sh")
text = path.read_text(encoding="utf-8")
old = '''has "$SURFACE" 'required property int entryTransitionDuration' 'secure surface duration input is missing'\nhas "$SHELL" 'entryTransitionDuration: root.lockEntryTransitionDuration' 'secure shell does not pass duration'\n'''
new = '''has "$SURFACE" 'duration: root.profile.lockscreen_entry_transition_duration' 'secure surface transition duration is not monitor-profile local'\nhas "$SHELL" 'sharedProfile: root.lockSharedProfile' 'secure shell does not pass the Shared presentation snapshot'\nhas "$SHELL" 'monitorOverrides: root.lockMonitorOverrides' 'secure shell does not pass monitor presentation overrides'\n'''
if old in text:
    text = text.replace(old, new, 1)
elif new not in text:
    raise SystemExit("Task 7 runtime acceptance migration anchor missing")
path.write_text(text, encoding="utf-8")
