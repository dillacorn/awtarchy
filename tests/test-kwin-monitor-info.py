#!/usr/bin/env python3
"""KScreen output fixture contract, including virtual outputs with missing enabled."""
import importlib.util
from pathlib import Path

root = Path(__file__).resolve().parents[1]
path = root / "trials/kwin/monitor-info.py"
spec = importlib.util.spec_from_file_location("monitor_info", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

data = {
    "outputs": [
        {"name": "DP-3", "connected": True, "enabled": True, "currentModeId": "2",
         "pos": {"x": 0, "y": 0}, "scale": 1.25,
         "modes": [{"id": 1, "size": {"width": 1920, "height": 1080}, "refreshRate": 60},
                   {"id": 2, "size": {"width": 2560, "height": 1440}, "refreshRate": 239.97}]},
        {"name": "DP-1", "connected": True, "enabled": False,
         "modes": [], "pos": {"x": 2560, "y": 0}, "scale": 1},
        {"name": "Virtual-1", "connected": True, "currentModeId": "3",
         "pos": {"x": -100, "y": 150}, "scale": 1,
         "modes": [{"id": "3", "size": {"width": 1600, "height": 900}, "refreshRate": 60}]},
        {"name": "HDMI-A-1", "connected": False}
    ]
}
output = module.show(data)
assert "DP-3: enabled, 2560x1440@239.97Hz, 0,0, scale 1.25" in output, output
assert "DP-1: disabled" in output
assert "Virtual-1: enabled unknown, 1600x900@60.00Hz, -100,150, scale 1" in output
assert "HDMI-A-1: disconnected" in output
for invalid in ({}, {"outputs": {}}, {"outputs": [{"name": "bad\nunsafe"}]}):
    try:
        module.show(invalid)
    except ValueError:
        pass
    else:
        raise AssertionError(f"Accepted invalid monitor data: {invalid}")
print("PASS: KWin monitor JSON parser, missing enabled, mixed mode IDs")
