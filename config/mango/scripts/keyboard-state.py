#!/usr/bin/env python3
"""Compatibility output for Awtarchy's Caps Lock indicator under Mango.

Mango's mmsg device API lacks lock LED state. Use kernel keyboard LED
brightness when present; absent devices produce an unknown (empty) list.
"""
from pathlib import Path
import json

statuses = []
for path in sorted(Path("/sys/class/leds").glob("*::capslock/brightness")):
    try:
        statuses.append(int(path.read_text(encoding="ascii").strip()) > 0)
    except (OSError, ValueError):
        continue
print(json.dumps({"keyboards": [{"capsLock": value} for value in statuses]}))
