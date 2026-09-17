#!/usr/bin/env python3
from pathlib import Path

path = Path(".github/scripts/feature-lockscreen-monitor-profile-task4.py")
text = path.read_text(encoding="utf-8")
old = r'''    r'            LockPreviewScene \{ id: secondaryPreviewScene;.*?\n            \}\n            LockPreviewTransitionLayer \{ id: secondaryPreviewTransitionLayer;.*?\n            \}',
'''
new = r'''    r'            LockPreviewScene \{ id: secondaryPreviewScene;.*?\n            \}\n            LockPreviewTransitionLayer \{ id: secondaryPreviewTransitionLayer;.*?autoStart: false \}',
'''
if old in text:
    text = text.replace(old, new, 1)
elif new not in text:
    raise SystemExit("Task 4 secondary-preview matcher anchor missing")
path.write_text(text, encoding="utf-8")
