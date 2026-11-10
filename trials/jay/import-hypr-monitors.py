#!/usr/bin/env python3
"""Opt-in snapshot of active Hyprland monitor settings into separate Jay config."""
import argparse
import importlib.util
import json
import math
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent

def read_hyprland():
    if os.getenv("XDG_CURRENT_DESKTOP") != "Hyprland" or not os.getenv("HYPRLAND_INSTANCE_SIGNATURE") or not os.getenv("WAYLAND_DISPLAY"):
        raise ValueError("Run from the active Hyprland session")
    proc = subprocess.run(["hyprctl", "-j", "monitors"], check=True, capture_output=True,
                          text=True, timeout=5)
    return json.loads(proc.stdout)

def normalize(monitors):
    if not isinstance(monitors, list) or not 1 <= len(monitors) <= 16:
        raise ValueError("Expected 1-16 monitor records")
    rows, seen = [], set()
    for monitor in monitors:
        if not isinstance(monitor, dict) or monitor.get("disabled", False):
            continue
        name = monitor.get("name")
        if not isinstance(name, str) or not name or name in seen:
            raise ValueError("Missing or duplicated connector name")
        seen.add(name)
        keys = ["width", "height", "refreshRate", "x", "y", "scale"]
        values = [monitor.get(k) for k in keys]
        if any(isinstance(v, bool) or not isinstance(v, (int, float))
               or not math.isfinite(v) for v in values):
            raise ValueError(f"{name}: invalid geometry")
        w, h, hz, x, y, scale = values
        if not all(isinstance(v, int) for v in (w, h, x, y)):
            raise ValueError(f"{name}: geometry must be integral")
        if not (320 <= w <= 16384 and 240 <= h <= 16384 and 20 <= hz <= 1000 and 0.5 <= scale <= 4):
            raise ValueError(f"{name}: unsupported mode or scale")
        if not (-100000 <= x <= 100000 and -100000 <= y <= 100000):
            raise ValueError(f"{name}: position out of range")
        rows.append((name, w, h, hz, x, y, scale))
    if not rows:
        raise ValueError("No enabled monitors")
    x0 = min(row[4] for row in rows)
    y0 = min(row[5] for row in rows)
    return [(name, f"{w}x{h}@{hz:.3f}", f"{x-x0}x{y-y0}", f"{scale:.3f}")
            for name, w, h, hz, x, y, scale in rows]

def writer():
    path = ROOT / "monitor-profile.py"
    if path.is_symlink() or not path.is_file():
        raise ValueError("Trusted Jay monitor writer unavailable")
    spec = importlib.util.spec_from_file_location("jay_profile", path)
    if not spec or not spec.loader:
        raise ValueError("Could not import trusted Jay monitor writer")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

def apply(rows, config):
    profile = writer()
    source, start, finish, existing = profile.source_state(config)
    if existing:
        raise ValueError("Jay already contains saved outputs; refusing to replace independent Jay preferences")
    items = {name: profile.make_entry(name, mode, position, scale)
             for name, mode, position, scale in rows}
    result = source[:start] + profile.render(items) + source[finish:]
    profile.tomllib.loads(result)
    return profile.write_safely(config, source, result)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--preview", action="store_true")
    mode.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    rows = normalize(read_hyprland())
    for name, mode, position, scale in rows:
        print(f"{name}: {mode} at {position}, scale {scale}")
    if args.apply:
        target = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))) / "jay/config.toml"
        backup = apply(rows, target)
        print(f"Jay profile saved with backup: {backup}")
        print("Hyprland unchanged. Verify these modes after logging in to Jay.")

if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, TypeError, KeyError,
            subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
        print(f"Jay monitor import failed: {e}", file=sys.stderr)
        sys.exit(1)
