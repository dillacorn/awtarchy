#!/usr/bin/env python3
"""Keep Mango's XCursor selection aligned with Awtarchy's shared preference.

No compositor reload is attempted: Mango reads env= options on session start.
The Hyprland config and other preferences are not changed here.
"""
import argparse
import json
import os
from pathlib import Path
import re
import stat
import sys
import tempfile

THEMES = {
    "ice": "Bibata-Modern-Ice",
    "classic": "Bibata-Modern-Classic",
    "amber": "Bibata-Modern-Amber",
    "ice-sharp": "Bibata-Original-Ice",
    "classic-sharp": "Bibata-Original-Classic",
    "amber-sharp": "Bibata-Original-Amber",
    "ice-right": "Bibata-Modern-Ice-Right",
    "classic-right": "Bibata-Modern-Classic-Right",
    "amber-right": "Bibata-Modern-Amber-Right",
    "ice-sharp-right": "Bibata-Original-Ice-Right",
    "classic-sharp-right": "Bibata-Original-Classic-Right",
    "amber-sharp-right": "Bibata-Original-Amber-Right",
}


def requested_theme(state_path: Path):
    if state_path.is_symlink():
        raise ValueError("cursor preference state is symlinked")
    if not state_path.exists():
        return THEMES["ice"]
    settings = json.loads(state_path.read_text(encoding="utf-8"))
    if not isinstance(settings, dict):
        raise ValueError("cursor state is not a JSON object")
    variant = settings.get("cursor_variant", "ice")
    if variant not in THEMES:
        raise ValueError("unrecognized saved cursor variant")
    return THEMES[variant]


def update_config(config_path: Path, theme: str, apply: bool):
    if config_path.is_symlink() or not config_path.is_file():
        raise ValueError("Mango config missing, linked, or not a regular file")
    if config_path.parent.is_symlink():
        raise ValueError("Mango configuration directory is linked")
    before = config_path.read_text(encoding="utf-8")
    if len(before) > 1024 * 1024:
        raise ValueError("Mango configuration is unexpectedly large")
    theme_lines = re.findall(r"^env=XCURSOR_THEME,.*$", before, flags=re.M)
    size_lines = re.findall(r"^env=XCURSOR_SIZE,.*$", before, flags=re.M)
    if len(theme_lines) != 1 or len(size_lines) != 1:
        raise ValueError("Expected one managed Mango XCursor theme and size line")
    if not re.fullmatch(r"Bibata-[A-Za-z0-9-]+", theme):
        raise ValueError("Invalid cursor theme")
    if size_lines[0] != "env=XCURSOR_SIZE,24":
        raise ValueError("Unexpected Mango cursor size; preserving user customizations")
    after = before.replace(theme_lines[0], f"env=XCURSOR_THEME,{theme}", 1)
    if before == after:
        return False
    if not apply:
        return True

    # Keep the original mode and avoid replacing an unexpected new target.
    old_stat = config_path.stat()
    if not stat.S_ISREG(old_stat.st_mode) or old_stat.st_uid != os.geteuid():
        raise ValueError("Mango config is not owned by the invoking user")
    fd, temporary = tempfile.mkstemp(prefix=".mango-cursor-", dir=config_path.parent)
    try:
        os.fchmod(fd, stat.S_IMODE(old_stat.st_mode))
        with os.fdopen(fd, "w", encoding="utf-8") as file:
            file.write(after)
            file.flush()
            os.fsync(file.fileno())
        if config_path.is_symlink():
            raise ValueError("Mango config was replaced with a symlink")
        os.replace(temporary, config_path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    return True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--state", type=Path, required=True)
    parser.add_argument("--apply", action="store_true")
    opts = parser.parse_args()
    theme = requested_theme(opts.state)
    changed = update_config(opts.config, theme, opts.apply)
    print(f"Mango cursor preference: {theme}; change={'required' if changed else 'none'}")
    if changed and not opts.apply:
        return 3
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, OSError, KeyError, TypeError, json.JSONDecodeError) as exc:
        print(f"mango-cursor: {exc}", file=sys.stderr)
        sys.exit(1)
