#!/usr/bin/env python3
"""Persist Jay output modes without overwriting unrelated config or Hyprland.

Jay's control-center edits apply live but are not persisted. This helper writes
only its own marked block. Reads are read-only, writes are atomic and backed up.
"""
import argparse
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
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
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

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--list", action="store_true")
    group.add_argument("--set", nargs=4, metavar=("CONNECTOR", "MODE", "POSITION", "SCALE"))
    args = parser.parse_args()
    config = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))) / "jay/config.toml"
    contents, start, finish, indexed = source_state(config)
    if args.list:
        for name, entry in sorted(indexed.items()):
            print(f'{name}: {entry["mode"]["width"]}x{entry["mode"]["height"]}'
                  f'@{entry["mode"]["refresh-rate"]:g}, {entry["x"]}x{entry["y"]}, '
                  f'scale={entry["scale"]:g}')
        if not indexed:
            print("No persistent overrides; use jay randr show --modes")
        return
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
    except (OSError, UnicodeError, ValueError, TypeError, KeyError) as exc:
        print(f'Jay profile error: {exc}', file=sys.stderr)
        sys.exit(1)
