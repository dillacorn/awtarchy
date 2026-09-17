#!/usr/bin/env python3
from pathlib import Path

path = Path("tests/test-quickshell-lockscreen-foundation.sh")
text = path.read_text(encoding="utf-8")
old = '''require_text "$SURFACE_QML" 'required property int backgroundOpacity' \\
    'lock surface has no presentation-only background opacity input'\n'''
new = '''require_text "$SURFACE_QML" 'backgroundOpacity: root.profile.lockscreen_background_opacity' \\
    'lock surface does not resolve presentation-only background opacity from its monitor profile'\n'''
if old in text:
    text = text.replace(old, new, 1)
elif new not in text:
    raise SystemExit("foundation background-opacity profile migration anchor missing")
path.write_text(text, encoding="utf-8")
