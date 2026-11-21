#!/usr/bin/env python3
"""Monitor import contract for the first Sway login (read-only)."""
import importlib.util
import json
import os
from pathlib import Path
from unittest.mock import patch
import subprocess

ROOT = Path(__file__).resolve().parents[1]
TRIAL = ROOT / "compositors/sway"
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


# Real Hyprmoncfg profile JSON is optional. Only an active profile that
# exactly matches the running Hyprland outputs can contribute extra settings.
from tempfile import TemporaryDirectory

with TemporaryDirectory(prefix="hyprmoncfg-import-test-") as temp:
    profile_dir = Path(temp) / "hyprmoncfg/profiles"
    profile_dir.mkdir(parents=True)
    saved = {
        "name": "Desktop",
        "outputs": [
            {"key": "primary", "name": "DP-1", "enabled": True, "vrr": 1, "transform": 0},
            {"key": "secondary", "name": "DP-3", "enabled": True, "vrr": 0, "transform": 1},
            {"key": "off", "name": "HDMI-A-1", "enabled": False},
        ],
        "workspaces": {
            "enabled": True, "strategy": "manual",
            "rules": [
                {"workspace": "1", "output_key": "primary"},
                {"workspace": "2", "output_name": "DP-3"},
            ],
        },
    }
    file = profile_dir / "desktop.json"
    file.write_text(json.dumps(saved), encoding="utf-8")
    active = subprocess.CompletedProcess(
        args=["hyprmoncfg", "status", "--json"], returncode=0,
        stdout=json.dumps({"active_profile": {"name": "Desktop"}}), stderr="")
    with patch.dict(os.environ, {"XDG_CONFIG_HOME": temp}):
        with patch.object(module.subprocess, "run", return_value=active):
            extra, rules = module.active_hyprmoncfg_additions(lines)
            assert extra == [
                "output DP-1 adaptive_sync on",
                "output DP-3 transform 90",
                "output HDMI-A-1 disable",
            ], extra
            assert rules == [
                "workspace 1 output DP-1",
                "workspace 2 output DP-3",
            ], rules
            saved["outputs"][0]["name"] = "DP-5"
            file.write_text(json.dumps(saved), encoding="utf-8")
            assert module.active_hyprmoncfg_additions(lines) == ([], [])
            saved["outputs"][0]["name"] = "DP-1"
            saved["workspaces"]["rules"].append(
                {"workspace": "1", "output_name": "DP-3"})
            file.write_text(json.dumps(saved), encoding="utf-8")
            assert module.active_hyprmoncfg_additions(lines)[1] == []

# Hyprland's actual active transform and VRR also import without hyprmoncfg.
with patch.dict(os.environ, {
    "XDG_CURRENT_DESKTOP": "Hyprland",
    "HYPRLAND_INSTANCE_SIGNATURE": "test-only",
}):
    adjusted = [dict(monitors[0], transform=3, vrr=True), monitors[1]]
    with patch.object(module.subprocess, "run", return_value=subprocess.CompletedProcess(
        args=["hyprctl"], returncode=0, stdout=json.dumps(adjusted), stderr="")):
        live = module.outputs_from_hyprland()
    assert "output DP-1 transform 270" in live
    assert "output DP-1 adaptive_sync on" in live

# An install outside Hyprland may reuse only explicit literal saved rules.
# Do not execute Lua or guess 'preferred', dynamic modes or unknown positions.
with TemporaryDirectory(prefix="sway-saved-monitors-") as temp:
    folder = Path(temp) / "hypr"
    folder.mkdir()
    config = folder / "hyprland.lua"
    config.write_text(
        'hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto", vrr = 0 })\n'
        'hl.monitor({ output = "DP-1", mode = "1920x1080@400.002", position = "0x1080", scale = 1, vrr = 1 })\n'
        'hl.monitor({ output = "DP-3", mode = "1920x1080@239.761", position = "0x0", scale = 1, vrr = 0 })\n'
        '-- hl.monitor({ output = "DP-2", mode = "bad", position = "auto", scale = 2 })\n',
        encoding="utf-8")
    with patch.dict(os.environ, {"XDG_CONFIG_HOME": temp, "XDG_CURRENT_DESKTOP": "sway"}), \
         patch.object(module, "connected_drm_outputs", return_value={"DP-1", "DP-3"}):
        saved_lines = module.outputs_from_saved_hyprland()
        assert saved_lines == [
            "output DP-1 mode 1920x1080@400.002Hz position 0 1080 scale 1",
            "output DP-3 mode 1920x1080@239.761Hz position 0 0 scale 1",
            "output DP-1 adaptive_sync on",
        ], saved_lines
        with patch.object(module, "connected_drm_outputs", return_value={"Virtual-1"}):
            try:
                module.outputs_from_saved_hyprland()
            except ValueError:
                pass
            else:
                raise AssertionError("Imported settings for disconnected monitors")
        config.write_text('hl.monitor({ output = "DP-1", mode = "preferred", position = "auto", scale = "auto" })\n')
        try:
            module.outputs_from_saved_hyprland()
        except ValueError:
            pass
        else:
            raise AssertionError("Guessed an automatic saved Hyprland monitor mode")

print("PASS: safe live/offline Hyprland monitor import without overwrites")
