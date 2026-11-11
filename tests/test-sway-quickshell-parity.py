#!/usr/bin/env python3
"""Regression coverage for first-login Sway Quickshell failures."""
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
TRIAL = ROOT / "trials/sway"


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


state = load("sway_state", TRIAL / "workspace-state.py")
sync = load("sway_sync", TRIAL / "sync.py")
monitors = [
    {"type": "output", "name": "DP-1", "nodes": [
        {"type": "workspace", "name": "2", "nodes": [
            {"type": "con", "name": "Firefox", "app_id": "firefox",
             "visible": True, "focused": True, "id": 20}
        ], "floating_nodes": []},
        {"type": "workspace", "name": "4", "nodes": [
            {"type": "con", "name": "Steam", "app_id": None, "window": 40,
             "window_properties": {"class": "steam"}, "visible": False,
             "focused": False, "id": 40}
        ], "floating_nodes": []},
        {"type": "workspace", "name": "__i3_scratch", "nodes": [
            {"type": "con", "name": "Awtarchy Quick Settings",
             "app_id": "quickshell", "id": 44}
        ], "floating_nodes": []},
    ], "floating_nodes": []}
]
workspaces = [
    {"num": 2, "name": "2", "output": "DP-1", "visible": True, "focused": True},
    {"num": 4, "name": "4", "output": "DP-1", "visible": False, "focused": False},
    {"num": -1, "name": "__i3_scratch", "output": "__i3", "visible": False},
]
result = state.collect({"type": "root", "nodes": monitors}, workspaces)
assert [w["id"] for w in result] == [2, 4], result
assert [len(w["clients"]) for w in result] == [1, 1], result
assert result[1]["clients"][0]["app_id"] == "steam"
assert result[1]["clients"][0]["title"] == "Steam"
assert result[0]["focused"] and not result[1]["focused"]

config = (TRIAL / "config").read_bytes()
profile = ("output DP-1 mode 1920x1080@400.00201Hz position 0 1080 scale 1\n"
           "output DP-3 mode 1920x1080@239.761Hz position 0 0 scale 1\n")
start = b"# AWTARCHY-SWAY-OUTPUTS-BEGIN"
end = b"# AWTARCHY-SWAY-OUTPUTS-END"
old = config.replace(start + b"\n", start + b"\n" + profile.encode(), 1)
new = config.replace(b"gaps inner 6", b"gaps inner 7")
merged = sync.prepare_config_update(old, new)
assert profile.encode() in merged
assert b"gaps inner 7" in merged
assert merged.split(start, 1)[1].split(end, 1)[0] == old.split(start, 1)[1].split(end, 1)[0]
for invalid in (old.replace(start, b"missing"), new.replace(end, b"missing")):
    try:
        sync.prepare_config_update(invalid, new)
    except ValueError:
        pass
    else:
        raise AssertionError("Invalid compositor output markers accepted")

with tempfile.TemporaryDirectory(prefix="sway-ui-regression-") as directory:
    temp = Path(directory)
    shell = temp / "awtarchy-sway"
    subprocess.run([
        "python3", str(TRIAL / "render-quickshell.py"),
        "--source", str(ROOT / "config/quickshell/awtarchy"),
        "--dest", str(shell), "--bridge-dir", str(TRIAL)
    ], check=True, timeout=40)
    bar = (shell / "Bar.qml").read_text(encoding="utf-8")
    qml_shell = (shell / "shell.qml").read_text(encoding="utf-8")
    theme = (shell / "Theme.qml").read_text(encoding="utf-8")
    picker = (shell / "ThemePicker.qml").read_text(encoding="utf-8")
    assert bar.count("acceptedModifiers: Qt.AltModifier") == 2
    assert bar.count("SwayDragBridge.beginBarDrag") == 1
    assert bar.count("onActiveTranslationChanged:") == 2
    assert qml_shell.count("target: SwayDragBridge") == 1
    assert "SwayBridge.moveWorkspace" in bar
    assert "/quickshell/awtarchy-sway/theme.json" in theme
    assert "/sway/awtarchy-trial/theme-apply.sh" in picker
    assert (shell / "SwayDragBridge.qml").is_file()
    assert "SwayBridge" in qml_shell

source = (TRIAL / "capture.sh").read_text(encoding="utf-8")
assert 'satty --filename "$image"' in source
assert "slurp -r -f" in source
assert "hyprpicker" not in source
assert "hyprctl" not in source
assert "wl-copy --type image/png" in source
script = (TRIAL / "theme-apply.sh").read_text(encoding="utf-8")
assert '/quickshell/awtarchy-sway/theme.json' in script
assert "hyprctl" not in script
assert 'HYPR_LUA=' not in script

for name, title in (
    ("launcher", "Awtarchy Application Search"),
    ("clipboard", "Awtarchy Clipboard History"),
    ("quick-settings", "Awtarchy Quick Settings"),
    ("notifications", "Awtarchy Notification Center"),
    ("network", "Awtarchy Network"),
    ("bluetooth", "Awtarchy Bluetooth"),
    ("battery", "Awtarchy Battery"),
):
    cfg = config.decode()
    assert 'for_window [title="^' + title + '$"] floating enable' in cfg, name
assert "bindsym Mod1+Shift+m exec foot --app-id maccel maccel" in config.decode()
assert "bindsym Mod4+Shift+m exec foot --app-id maccel maccel" in config.decode()
assert 'for_window [app_id="maccel"] floating enable' in config.decode()

print("PASS: Sway hidden workspace occupancy, scratchpad filtering, UI positioning, gestures, theme and Satty")
