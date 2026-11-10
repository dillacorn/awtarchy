#!/usr/bin/env python3
"""Persist Jay output modes without overwriting unrelated config or Hyprland.

Jay's control-center edits apply live but are not persisted. This helper writes
only its own marked block. Reads are read-only, writes are atomic and backed up.
"""
import argparse
import json
import math
import subprocess
from datetime import datetime, timezone
import os
from pathlib import Path
import re
import sys
import tempfile
import tomllib

BEGIN = "# AWTARCHY-JAY-OUTPUTS-BEGIN"
END = "# AWTARCHY-JAY-OUTPUTS-END"
CONNECTOR = re.compile(r"^[A-Za-z][A-Za-z0-9._-]{0,79}$")
MODE = re.compile(r"^(\d{3,5})x(\d{3,5})@(\d{1,4}(?:\.\d{1,3})?)$")
POSITION = re.compile(r"^(\d{1,6})x(\d{1,6})$")

def validate_entry(item):
    if not isinstance(item, dict) or set(item) != {"match", "x", "y", "scale", "mode"}:
        raise ValueError("Unrecognized/customized output block; refusing to rewrite")
    matcher = item["match"]
    mode = item["mode"]
    if not isinstance(matcher, dict) or set(matcher) != {"connector"} or not CONNECTOR.fullmatch(matcher["connector"]):
        raise ValueError("Unsupported output matcher")
    if not isinstance(mode, dict) or set(mode) != {"width", "height", "refresh-rate"}:
        raise ValueError("Unrecognized output mode")
    return matcher["connector"]

def source_state(path):
    if path.parent.is_symlink() or path.is_symlink() or not path.is_file():
        raise ValueError("Expected an installed regular Jay config, not a symlink")
    if path.stat().st_uid != os.getuid():
        raise ValueError("Jay config ownership mismatch")
    contents = path.read_text(encoding="utf-8")
    data = tomllib.loads(contents)
    if contents.count(BEGIN) != 1 or contents.count(END) != 1:
        raise ValueError("Jay profile markers are missing or duplicated")
    start = contents.index(BEGIN) + len(BEGIN)
    finish = contents.index(END)
    if start >= finish:
        raise ValueError("Jay profile markers out of order")
    section = contents[start:finish]
    parsed = tomllib.loads(section)
    entries = parsed.get("outputs", [])
    if set(parsed) != {"outputs"} and parsed:
        raise ValueError("Unexpected data inside Jay profile block")
    # Any other output declaration outside our block would introduce
    # overlapping owners. Do not silently adopt/rewrite it.
    if len(data.get("outputs", [])) != len(entries):
        raise ValueError("Foreign output declaration exists; refusing to rewrite")
    indexed = {}
    for item in entries:
        name = validate_entry(item)
        if name in indexed:
            raise ValueError("Duplicate output connector in Jay profile")
        indexed[name] = item
    return contents, start, finish, indexed

def make_entry(connector, mode_str, position_str, scale_str):
    if not CONNECTOR.fullmatch(connector):
        raise ValueError("Connector must look like DP-1 or HDMI-A-1")
    match = MODE.fullmatch(mode_str)
    position = POSITION.fullmatch(position_str)
    if match is None or position is None:
        raise ValueError("Expected WIDTHxHEIGHT@HZ and XxY")
    width, height, hz = int(match[1]), int(match[2]), float(match[3])
    x, y = int(position[1]), int(position[2])
    scale = float(scale_str)
    if not (320 <= width <= 16384 and 240 <= height <= 16384):
        raise ValueError("Unreasonable resolution")
    if not (20 <= hz <= 1000 and 0.5 <= scale <= 4.0):
        raise ValueError("Unreasonable refresh or scale")
    return {"match": {"connector": connector}, "x": x, "y": y, "scale": scale,
            "mode": {"width": width, "height": height, "refresh-rate": hz}}

def render(index):
    parts = []
    for connector in sorted(index):
        item = index[connector]
        mode = item["mode"]
        parts.append('[[outputs]]\n'
                     f'match.connector = "{connector}"\n'
                     f'x = {item["x"]}\ny = {item["y"]}\n'
                     f'scale = {float(item["scale"]):g}\n'
                     f'mode = {{ width = {mode["width"]}, height = {mode["height"]}, '
                     f'refresh-rate = {float(mode["refresh-rate"]):g} }}')
    return "\n" + "\n\n".join(parts) + "\n"

def write_safely(path, old, new):
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S-%f")
    backup = path.with_name(path.name + ".backup-" + timestamp)
    # Exclusive creation: never replace an existing backup or a symlink.
    fd = os.open(backup, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "wb") as f:
        f.write(old.encode("utf-8"))
        f.flush()
        os.fsync(f.fileno())
    temp = None
    try:
        with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=path.parent,
                                         prefix=".jay-profile-", delete=False) as stream:
            temp = Path(stream.name)
            stream.write(new)
            stream.flush()
            os.fsync(stream.fileno())
        temp.chmod(path.stat().st_mode & 0o777)
        # Refuse a late symlink replacement rather than following it.
        if path.is_symlink() or not path.is_file():
            raise ValueError("Jay config changed while writing; retaining backup")
        os.replace(temp, path)
    finally:
        if temp and temp.exists():
            temp.unlink()
    return backup

def import_hyprland_active_outputs(monitors):
    """Parse actual Hyprland output geometry; never infer refresh/modes."""
    if not isinstance(monitors, list) or not monitors:
        raise ValueError("Hyprland returned no monitor list")
    active = {}
    for mon in monitors:
        if not isinstance(mon, dict):
            raise ValueError("Malformed Hyprland monitor entry")
        if mon.get("disabled") is True:
            continue
        name = mon.get("name")
        if not isinstance(name, str) or not CONNECTOR.fullmatch(name):
            raise ValueError("Invalid Hyprland connector name")
        if name in active:
            raise ValueError("Duplicate monitor connector")
        for field in ("width", "height", "x", "y", "refreshRate", "scale"):
            value = mon.get(field)
            if isinstance(value, bool) or not isinstance(value, (float, int)) or not math.isfinite(value):
                raise ValueError(f"{name}: unknown {field}; refusing guessed mode")
        if mon["width"] <= 0 or mon["height"] <= 0:
            raise ValueError(f"{name}: zero-size monitor")
        if int(mon["x"]) != mon["x"] or int(mon["y"]) != mon["y"]:
            raise ValueError(f"{name}: unsupported fractional output coordinates")
        active[name] = dict(mon)
    if not active:
        raise ValueError("No enabled Hyprland outputs")
    # Jay requires nonnegative coordinates; preserve relative layout.
    min_x = min(int(v["x"]) for v in active.values())
    min_y = min(int(v["y"]) for v in active.values())
    result = {}
    for name, mon in active.items():
        mode = f'{int(mon["width"])}x{int(mon["height"])}@{float(mon["refreshRate"]):.3f}'
        position = f'{int(mon["x"])-min_x}x{int(mon["y"])-min_y}'
        result[name] = make_entry(name, mode, position, str(mon["scale"]))
    return result

def live_hyprland_outputs():
    if (os.environ.get("XDG_CURRENT_DESKTOP") != "Hyprland"
            or not os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
            or not os.environ.get("WAYLAND_DISPLAY")):
        raise ValueError("Import requires an active Hyprland desktop session")
    result = subprocess.run(["hyprctl", "monitors", "-j"], check=True,
                            capture_output=True, text=True, timeout=4)
    return import_hyprland_active_outputs(json.loads(result.stdout))

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--list", action="store_true")
    group.add_argument("--set", nargs=4, metavar=("CONNECTOR", "MODE", "POSITION", "SCALE"))
    group.add_argument("--preview-hyprland", action="store_true")
    group.add_argument("--import-hyprland", action="store_true")
    args = parser.parse_args()
    config = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))) / "jay/config.toml"
    contents, start, finish, indexed = source_state(config)
    if args.list:
        for name, entry in sorted(indexed.items()):
            print(f'{name}: {entry["mode"]["width"]}x{entry["mode"]["height"]}'
                  f'@{float(entry["mode"]["refresh-rate"]):g}, {entry["x"]}x{entry["y"]}, '
                  f'scale={float(entry["scale"]):g}')
        if not indexed:
            print("No persistent overrides; use jay randr show --modes")
        return
    if args.preview_hyprland or args.import_hyprland:
        imported = live_hyprland_outputs()
        for name, entry in sorted(imported.items()):
            mode = entry["mode"]
            print(f'{name}: {mode["width"]}x{mode["height"]}'
                  f'@{float(mode["refresh-rate"]):g} -> '
                  f'{entry["x"]}x{entry["y"]}, scale={float(entry["scale"]):g}')
        if args.preview_hyprland:
            print("PREVIEW ONLY; Jay config was not modified.")
            return
        indexed = imported
    else:
        connector, mode, position, scale = args.set
        indexed[connector] = make_entry(connector, mode, position, scale)
    new = contents[:start] + render(indexed) + contents[finish:]
    tomllib.loads(new)
    backup = write_safely(config, contents, new)
    print(f'Saved Jay output: {connector}; backup: {backup}')
    print('Config auto-reload applies the saved profile; verify after a new login.')

if __name__ == "__main__":
    try:
        main()
    except (OSError, UnicodeError, ValueError, TypeError, KeyError,
            subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
        print(f'Jay profile error: {exc}', file=sys.stderr)
        sys.exit(1)
