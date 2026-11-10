#!/usr/bin/env python3
"""Test Jay output persistence without a Wayland session or user config writes."""
from pathlib import Path
import os
import importlib.util
import subprocess
import sys
import tempfile
import tomllib

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "trials/jay/config.toml"
HELPER = ROOT / "trials/jay/monitor-profile.py"

def run(args, env):
    return subprocess.run([sys.executable, str(HELPER), *args],
                          env=env, text=True, capture_output=True)

def test_hyprland_import():
    spec = importlib.util.spec_from_file_location("jay_trial_monitor", HELPER)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    monitors = [
        {"name": "DP-3", "width": 1920, "height": 1080, "refreshRate": 239.964,
         "scale": 1.0, "x": -1920, "y": 0, "disabled": False},
        {"name": "DP-1", "width": 1920, "height": 1080, "refreshRate": 360.0,
         "scale": 1.0, "x": 0, "y": 0, "disabled": False},
        {"name": "HDMI-A-1", "disabled": True},
    ]
    result = module.import_hyprland_active_outputs(monitors)
    assert set(result) == {"DP-3", "DP-1"}
    assert result["DP-3"]["x"] == 0
    assert result["DP-1"]["x"] == 1920
    assert result["DP-3"]["mode"]["refresh-rate"] == 239.964
    assert result["DP-1"]["mode"]["refresh-rate"] == 360
    for invalid in [
        [],
        [{"name": "DP-1", "disabled": True}],
        [monitors[0], monitors[0]],
        [{**monitors[0], "refreshRate": None}],
        [{**monitors[0], "scale": 0}],
        [{**monitors[0], "width": 0}],
        [{**monitors[0], "x": 1.5}],
        [{**monitors[0], "refreshRate": float("nan")}],
    ]:
        try:
            module.import_hyprland_active_outputs(invalid)
        except ValueError:
            pass
        else:
            raise AssertionError(f"Invalid Hyprland monitor list accepted: {invalid}")


def test_profile():
    with tempfile.TemporaryDirectory() as root:
        config = Path(root) / "jay/config.toml"
        config.parent.mkdir()
        config.write_bytes(SRC.read_bytes())
        env = dict(os.environ, XDG_CONFIG_HOME=root)
        assert run(["--list"], env).returncode == 0
        result = run(["--set", "DP-1", "1920x1080@240", "0x0", "1.0"], env)
        assert result.returncode == 0, result.stderr
        data = tomllib.loads(config.read_text())
        assert data["outputs"][0]["match"]["connector"] == "DP-1"
        assert data["outputs"][0]["mode"]["refresh-rate"] == 240
        assert data["tearing"]["mode"] == "variant2"
        assert len(list(config.parent.glob("config.toml.backup-*"))) == 1
        for args in [
            ["--set", "../DP-2", "1920x1080@240", "0x0", "1"],
            ["--set", "DP-1", "1920x1080@0", "0x0", "1"],
            ["--set", "DP-1", "1920x1080@240", "-20x0", "1"],
        ]:
            assert run(args, env).returncode != 0
        second = run(["--set", "DP-2", "1920x1080@144", "1920x0", "1.0"], env)
        assert second.returncode == 0, second.stderr
        data = tomllib.loads(config.read_text())
        assert len(data["outputs"]) == 2
        assert run(["--list"], env).returncode == 0
        # Foreign additional [[outputs]] outside the managed block blocks changes.
        with config.open("a") as f:
            f.write('\n[[outputs]]\nmatch.connector = "HDMI-A-1"\n')
        assert run(["--set", "DP-3", "1920x1080@144", "3840x0", "1.0"], env).returncode != 0
        # Reject symlink targets, even if they currently point to valid content.
        original = config.with_name("original.toml")
        config.rename(original)
        config.symlink_to(original)
        assert run(["--set", "DP-3", "1920x1080@144", "3840x0", "1.0"], env).returncode != 0

if __name__ == "__main__":
    test_profile()
    test_hyprland_import()
    print("PASS: Jay monitor profile writes, backups, validation, collision and symlink guards")
