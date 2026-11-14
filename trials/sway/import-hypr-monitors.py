#!/usr/bin/env python3
"""One-time exact active Hyprland display import into Sway trial only."""
import argparse
from datetime import datetime, timezone
from decimal import Decimal
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile

START = "# AWTARCHY-SWAY-OUTPUTS-BEGIN"
END = "# AWTARCHY-SWAY-OUTPUTS-END"
NAME = re.compile(r"^[A-Za-z0-9_.-]{1,48}$")

def outputs_from_hyprland():
    if os.environ.get("XDG_CURRENT_DESKTOP") != "Hyprland":
        raise ValueError("Import must run from active Hyprland")
    if not os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
        raise ValueError("Hyprland instance not detected")
    p = subprocess.run(["hyprctl", "monitors", "-j"], capture_output=True,
                       text=True, timeout=6, check=True)
    data = json.loads(p.stdout)
    if not isinstance(data, list) or not data:
        raise ValueError("No monitor data returned")
    out = []
    names = set()
    for monitor in data:
        if not isinstance(monitor, dict):
            raise ValueError("Malformed output entry")
        name = monitor["name"]
        if not isinstance(name, str) or not NAME.fullmatch(name) or name in names:
            raise ValueError("Unsafe or duplicate output name")
        names.add(name)
        w, h = int(monitor["width"]), int(monitor["height"])
        x, y = int(monitor["x"]), int(monitor["y"])
        hz = Decimal(str(monitor["refreshRate"]))
        scale = Decimal(str(monitor["scale"]))
        if w <= 0 or h <= 0 or not 20 <= hz <= 1000 or not 0 < scale <= 8:
            raise ValueError("Invalid display mode")
        out.append((name, w, h, x, y, hz, scale))
    # Sway can represent both positive and negative positions, but place the
    # leftmost/topmost origin at zero as the former Jay import did.
    min_x = min(row[3] for row in out)
    min_y = min(row[4] for row in out)
    return [
        f"output {name} mode {w}x{h}@{hz}Hz position {x-min_x} {y-min_y} scale {scale}"
        for name, w, h, x, y, hz, scale in out
    ]

def insert_profile(original, lines):
    if original.count(START) != 1 or original.count(END) != 1:
        raise ValueError("Sway output markers are unavailable or duplicated")
    before, rest = original.split(START, 1)
    existing, after = rest.split(END, 1)
    if any(line.strip() and not line.strip().startswith("#") for line in existing.splitlines()):
        raise ValueError("Existing Sway output profile; refusing to overwrite")
    return before + START + "\n" + "\n".join(lines) + "\n" + END + after

def main():
    ap = argparse.ArgumentParser()
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--preview", action="store_true")
    mode.add_argument("--apply", action="store_true")
    ap.add_argument("--config", type=Path, default=Path(
        os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))
    ) / "sway/awtarchy-trial/config")
    args = ap.parse_args()
    if os.geteuid() == 0:
        raise ValueError("Do not run monitor import as root")
    cfg = args.config
    if cfg.is_symlink() or cfg.parent.is_symlink() or not cfg.is_file():
        raise ValueError("Missing or linked Sway config")
    info = cfg.stat()
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid() or info.st_nlink != 1:
        raise ValueError("Unexpected Sway config ownership")
    previous = cfg.read_text(encoding="utf-8")
    if "# Awtarchy Sway dual-compositor trial. Does not touch Hyprland." not in previous:
        raise ValueError("Unknown Sway profile")
    lines = outputs_from_hyprland()
    result = insert_profile(previous, lines)
    print("Proposed Sway output profile:")
    for line in lines:
        print("  " + line)
    if args.preview:
        return
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S-%f")
    backup = cfg.with_name("config.backup-" + stamp)
    with backup.open("xb") as handle:
        os.fchmod(handle.fileno(), 0o600)
        handle.write(previous.encode())
        handle.flush()
        os.fsync(handle.fileno())
    temp_name = None
    try:
        with tempfile.NamedTemporaryFile(dir=cfg.parent, prefix=".sway-display-",
                                         delete=False) as handle:
            temp_name = handle.name
            handle.write(result.encode())
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temp_name, stat.S_IMODE(info.st_mode))
        if cfg.read_text(encoding="utf-8") != previous:
            raise ValueError("Sway config changed while importing; backup retained")
        os.replace(temp_name, cfg)
    finally:
        if temp_name and os.path.exists(temp_name):
            os.unlink(temp_name)
    if cfg.read_text(encoding="utf-8") != result:
        raise ValueError("Written Sway output profile was not verified")
    print("PASS: one-time Sway monitor import; backup: " + str(backup))

if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError, UnicodeError, json.JSONDecodeError,
            subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        print("Sway monitor import: " + str(error), file=sys.stderr)
        sys.exit(1)
