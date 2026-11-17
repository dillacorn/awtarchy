#!/usr/bin/env python3
"""Rename only the existing Awtarchy Sway Ly label; no Sway config changes.

Scope is the exact root-owned Awtarchy Sway entry, never the package-provided
sway.desktop or another compositor. Apply preserves the original as a backup.
"""
from __future__ import annotations
import argparse
import datetime
import os
from pathlib import Path
import subprocess
import sys
import tempfile

TARGET = Path("/usr/share/wayland-sessions/awtarchy-sway-trial.desktop")
ALLOWED_NAMES = {"Sway", "Sway (Awtarchy)", "Sway (Awtarchy Trial)",
                 "Sway (Awtarchy trial)"}
ALLOWED_EXEC = {"Exec=/usr/local/bin/awtarchy-sway-session",
                "Exec=/usr/local/bin/awtarchy-sway-trial-session"}


def renamed(text: str) -> str:
    # Preserve every non-Name field, including Exec, DesktopNames and Comment.
    lines = text.splitlines(keepends=True)
    entries = [line.rstrip("\r\n") for line in lines]
    if entries.count("[Desktop Entry]") != 1:
        raise ValueError("Not a single desktop entry")
    names = [i for i, line in enumerate(entries) if line.startswith("Name=")]
    if len(names) != 1 or entries[names[0]][5:] not in ALLOWED_NAMES:
        raise ValueError("Unknown Sway Ly display name; refusing edit")
    if any(line.startswith("Name[") for line in entries):
        raise ValueError("Localized names present; refusing partial rename")
    if not any(line in ALLOWED_EXEC for line in entries):
        raise ValueError("Unexpected Sway session launcher; refusing edit")
    if entries.count("Type=Application") != 1 or entries.count("DesktopNames=sway") != 1:
        raise ValueError("Unexpected Sway desktop entry")
    index = names[0]
    suffix = "\r\n" if lines[index].endswith("\r\n") else ("\n" if lines[index].endswith("\n") else "")
    lines[index] = "Name=Sway" + suffix
    return "".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--plan", action="store_true")
    group.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    try:
        if os.geteuid() == 0:
            raise ValueError("Run without sudo; privileged install is scoped internally")
        if TARGET.is_symlink() or not TARGET.is_file():
            raise ValueError(f"Exact Sway Ly entry not found/unsafe: {TARGET}")
        if TARGET.stat().st_uid != 0 or TARGET.parent.is_symlink():
            raise ValueError("Sway Ly entry is not root-owned or parent is linked")
        owned = subprocess.run(["pacman", "-Qo", "--", str(TARGET)],
                               capture_output=True, check=False)
        if owned.returncode == 0:
            raise ValueError("Sway entry is package-owned, refusing to change it")
        before = TARGET.read_bytes()
        text = before.decode("utf-8")
        after = renamed(text).encode("utf-8")
        if after == before:
            print("Already Name=Sway; no changes")
            return 0
        if args.plan:
            print(f"Would change Name= to Sway in {TARGET}")
            print("Exec, DesktopNames, other fields and Sway configs unchanged")
            return 0
        with tempfile.TemporaryDirectory(prefix="awtarchy-sway-ly-") as temp:
            staged = Path(temp) / "new.desktop"
            staged.write_bytes(after)
            os.chmod(staged, 0o644)
            # Re-read immediately before privileged work.
            if TARGET.read_bytes() != before:
                raise ValueError("Sway session file changed; refusing to overwrite")
            name = datetime.datetime.now(datetime.timezone.utc).strftime(
                "%Y%m%d-%H%M%S-%f")
            backup = TARGET.with_name(TARGET.name + ".backup-" + name)
            if backup.exists() or backup.is_symlink():
                raise ValueError("Sway session backup collision")
            subprocess.run(["sudo", "install", "-m", "0644", "--",
                            str(TARGET), str(backup)], check=True)
            subprocess.run(["sudo", "install", "-m", "0644", "--",
                            str(staged), str(TARGET)], check=True)
            if TARGET.read_bytes() != after:
                raise ValueError(f"Verification failed. Original preserved at {backup}")
            print(f"Changed Ly display name to Sway; backup: {backup}")
            print("All existing Sway paths, session launchers, and configs preserved")
        return 0
    except (ValueError, OSError, subprocess.CalledProcessError, UnicodeError) as exc:
        print(f"Sway Ly label: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
