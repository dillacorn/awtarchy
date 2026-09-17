#!/usr/bin/env python3
from pathlib import Path

path = Path("tests/test-quickshell-lockscreen-presentation-sequencing.sh")
text = path.read_text()
old = '''require_text "$SURFACE" 'passwordMaskMode: root.passwordMaskMode' \\
    'secure surface does not share password-mask presentation with the scene'
'''
new = '''require_text "$SURFACE" 'passwordMaskMode: root.profile.lockscreen_password_mask_mode' \\
    'secure surface does not resolve password-mask presentation from the effective monitor profile'
require_text "$SURFACE" 'passwordMaskCharacter: root.profile.lockscreen_password_mask_character' \\
    'secure surface does not resolve custom password-mask presentation from the effective monitor profile'
require_text "$SURFACE" 'clockFormat: root.profile.lockscreen_clock_format' \\
    'secure surface does not resolve clock format from the effective monitor profile'
'''
if old not in text:
    raise SystemExit("presentation-sequencing legacy password-mask binding not found")
path.write_text(text.replace(old, new, 1))
