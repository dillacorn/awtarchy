#!/usr/bin/env python3
"""Monitor import contract for the first Sway login (read-only)."""
import importlib.util
import json
import os
from pathlib import Path
from unittest.mock import patch
import subprocess

ROOT = Path(__file__).resolve().parents[1]
TRIAL = ROOT / "trials/sway"
spec = importlib.util.spec_from_file_location(
    "sway_monitor_import", TRIAL / "import-hypr-monitors.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

source = (TRIAL / "config").read_text(encoding="utf-8")
assert source.count(module.START) == 1
assert source.count(module.END) == 1
monitors = [
    {"name": "DP-1", "width": 1920, "height": 1080,
     "x": 0, "y": 1080, "refreshRate": 400.002, "scale": 1.0},
    {"name": "DP-3", "width": 1920, "height": 1080,
     "x": 0, "y": 0, "refreshRate": 239.761, "scale": 1.0},
]
fake = subprocess.CompletedProcess(
    args=["hyprctl", "monitors", "-j"],
    returncode=0, stdout=json.dumps(monitors), stderr="")
with patch.dict(os.environ, {
    "XDG_CURRENT_DESKTOP": "Hyprland",
    "HYPRLAND_INSTANCE_SIGNATURE": "test-only",
}):
    with patch.object(module.subprocess, "run", return_value=fake) as call:
        lines = module.outputs_from_hyprland()
        assert call.call_count == 1
assert lines == [
    "output DP-1 mode 1920x1080@400.002Hz position 0 1080 scale 1.0",
    "output DP-3 mode 1920x1080@239.761Hz position 0 0 scale 1.0",
], lines

updated = module.insert_profile(source, lines)
assert module.START in updated and module.END in updated
assert all(line in updated for line in lines)
assert source.split(module.START)[0] == updated.split(module.START)[0]
assert source.split(module.END)[1] == updated.split(module.END)[1]

for source_with_user_settings in (
    updated,
    source.replace(module.START, module.START + "\noutput DP-1 scale 2"),
):
    try:
        module.insert_profile(source_with_user_settings, lines)
    except ValueError:
        pass
    else:
        raise AssertionError("Monitor importer would overwrite a personalized output block")

with patch.dict(os.environ, {"XDG_CURRENT_DESKTOP": "sway"}):
    try:
        module.outputs_from_hyprland()
    except ValueError:
        pass
    else:
        raise AssertionError("Hyprland-only import was permitted under Sway")

with patch.dict(os.environ, {
    "XDG_CURRENT_DESKTOP": "Hyprland",
    "HYPRLAND_INSTANCE_SIGNATURE": "mock",
}):
    with patch.object(module.subprocess, "run", return_value=subprocess.CompletedProcess(
        args=["hyprctl"], returncode=0,
        stdout=json.dumps(monitors + [monitors[0]]), stderr="")):
        try:
            module.outputs_from_hyprland()
        except ValueError:
            pass
        else:
            raise AssertionError("Duplicate outputs were accepted")

print("PASS: Sway output import retains exact 400/240Hz modes and refuses overwrites")
