#!/usr/bin/env python3
"""Verify real Jay randr schema and precise 400 Hz / secondary layout mismatch."""
import importlib.util
from pathlib import Path
import json

repo = Path(__file__).resolve().parents[1]
script = repo / "trials/jay/diagnose.py"
spec = importlib.util.spec_from_file_location("jay_diagnose", script)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

sample = {"drm_devices": [
    {"gfx_api": "Vulkan", "connectors": [
        {"name": "DP-1", "enabled": True, "output": {
            "mode": {"width": 1920, "height": 1080, "refresh_rate_millihz": 400000},
            "x": 0, "y": 0, "scale": 1.0, "tearing_mode": "variant2",
            "vrr_mode": "variant1", "vrr_capable": True}},
        {"name": "DP-3", "enabled": True, "output": {
            "mode": {"width": 1920, "height": 1080, "refresh_rate_millihz": 240000},
            "x": 1920, "y": 0, "scale": 1.0, "tearing_mode": "variant2",
            "vrr_mode": "variant1", "vrr_capable": False}},
    ]}
]}
outputs, gpus = mod.randr_data(json.dumps(sample))
assert gpus == ["Vulkan"]
config = {"outputs": [
    {"match": {"connector": "DP-1"}, "mode": {"width": 1920, "height": 1080, "refresh-rate": 400.0},
     "x": 0, "y": 0, "scale": 1.0},
    {"match": {"connector": "DP-3"}, "mode": {"width": 1920, "height": 1080, "refresh-rate": 240.0},
     "x": 1920, "y": 0, "scale": 1.0}
]}
failures, successes = mod.compare_outputs(config, outputs)
assert not failures and len(successes) == 2
sample["drm_devices"][0]["connectors"][1]["output"]["mode"]["refresh_rate_millihz"] = 60000
outputs, _ = mod.randr_data(json.dumps(sample))
failures, _ = mod.compare_outputs(config, outputs)
assert len(failures) == 1 and "DP-3" in failures[0] and "60.000" in failures[0]
sample["drm_devices"][0]["connectors"][1]["output"]["x"] = 0
outputs, _ = mod.randr_data(json.dumps(sample))
failures, _ = mod.compare_outputs(config, outputs)
assert any("DP-3" in x for x in failures)
print("PASS: Jay first-login monitor audit detects 400Hz/60Hz mismatches and geometry changes")
