#!/usr/bin/env python3
"""Best-effort Caps Lock LED query; no Hyprland IPC in Sway."""
import json
from pathlib import Path

values = []
for led in sorted(Path("/sys/class/leds").glob("*::capslock/brightness")):
    try:
        values.append({"capsLock": int(led.read_text(encoding="ascii").strip()) > 0})
    except (OSError, ValueError):
        continue
print(json.dumps({"keyboards": values}))
