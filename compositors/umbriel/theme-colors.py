#!/usr/bin/env python3
"""Umbriel-only border palette derived from existing Awtarchy themes.

No Hyprland configuration, Sway configuration, or shared theme is modified.
The generated file is a separate TOML include watched by Umbriel. Only
validated theme names and exact 6/8-hex color values are accepted.
"""
from __future__ import annotations
import argparse
import json
import os
from pathlib import Path
import re
import sys
import tempfile
import tomllib

def valid_theme_name(name: str) -> bool:
    # Awtarchy includes accented palette names. Accept Unicode letters while
    # keeping paths a single, safe file component.
    return (isinstance(name, str) and 1 <= len(name) <= 100
            and name[0].isalnum()
            and all(c.isalnum() or c in "-._" for c in name))
EIGHT = re.compile(r"[0-9a-fA-F]{8}\Z")
SIX = re.compile(r"#[0-9a-fA-F]{6}\Z")


def theme_source(home: Path, name: str) -> Path:
    if not valid_theme_name(name) or name in (".", ".."):
        raise ValueError("Invalid Awtarchy theme name")
    path = home / ".config/hypr/themes" / name
    if path.is_symlink() or not path.is_file() or path.stat().st_uid != os.geteuid():
        raise ValueError("Missing or unsafe Awtarchy theme: " + name)
    return path


def palette(home: Path, name: str | None = None) -> dict:
    """Return conservative defaults if no selected theme is available.

    Explicitly selected themes must exist; never silently apply the wrong one.
    """
    colors = {
        "active_border": "a0a0a0ff",
        "inactive_border": "4b4b4bff",
        "background": "#353535",
        "foreground": "#d0d0d0",
        "hover": "#404040", "focus": "#4a4a4a", "active": "#2b2b2b",
        "urgent": "#ff5555", "charging": "#6a9955", "critical": "#ff5555",
        "dark": "#1a1a1a", "muted": "#4a4a4a",
    }
    if name is None:
        state = home / ".local/state/awtarchy/active-theme"
        if state.is_file() and not state.is_symlink() and state.stat().st_uid == os.geteuid():
            candidate = state.read_text(encoding="utf-8").strip()
            name = candidate if valid_theme_name(candidate) else None
    if name is None:
        return colors
    try:
        path = theme_source(home, name)
    except ValueError:
        if name:
            raise
        return colors
    for line in path.read_text(encoding="utf-8").splitlines():
        match = re.match(r"^\s*(NEW_ACTIVE_BORDER|NEW_INACTIVE_BORDER|QS_BACKGROUND|QS_FOREGROUND|QS_HOVER|QS_FOCUS|QS_ACTIVE|QS_URGENT|QS_CHARGING|QS_CRITICAL|QS_DARK|QS_MUTED)\s*=\s*(.*?)\s*$", line)
        if not match:
            continue
        value = match.group(2).strip().strip('"').strip("'")
        slot = {
            "NEW_ACTIVE_BORDER": "active_border",
            "NEW_INACTIVE_BORDER": "inactive_border",
            "QS_BACKGROUND": "background",
            "QS_FOREGROUND": "foreground",
            "QS_HOVER": "hover", "QS_FOCUS": "focus",
            "QS_ACTIVE": "active", "QS_URGENT": "urgent",
            "QS_CHARGING": "charging", "QS_CRITICAL": "critical",
            "QS_DARK": "dark", "QS_MUTED": "muted",
        }[match.group(1)]
        if (EIGHT if slot.endswith("_border") else SIX).fullmatch(value) is None:
            raise ValueError("Invalid palette entry: " + match.group(1))
        colors[slot] = value
    return colors


def render_toml(colors: dict) -> bytes:
    active = "#" + colors["active_border"].upper()
    inactive = "#" + colors["inactive_border"].upper()
    body = (
        "# Awtarchy Umbriel theme: auto-generated; owned by the selected theme.\n"
        "[colors]\n"
        f'accent_primary = "{active}"\n'
        # Use the active-border RGB with a translucent overlay, matching
        # Umbriel's native drop/insertion preview rather than a fixed blue.
        f'insert_hint = "#{colors["active_border"][:6].upper()}80"\n'
        f'background = "{colors["background"].upper()}FF"\n'
        f'text_primary = "{colors["foreground"].upper()}FF"\n\n'
        "[colors.border]\n"
        f'focused = "{active}"\n'
        f'unfocused = "{inactive}"\n'
        f'outer = "{inactive}"\n'
    ).encode("utf-8")
    tomllib.loads(body.decode())
    return body


def quickshell_palette(colors: dict, name: str | None = None) -> bytes:
    # Boot appearance only. ThemePicker's runtime application remains the
    # canonical writer for the full Quickshell palette.
    return (json.dumps({
        "background": colors["background"], "hover": colors["hover"],
        "focus": colors["focus"], "active": colors["active"],
        "urgent": colors["urgent"], "charging": colors["charging"],
        "critical": colors["critical"], "foreground": colors["foreground"],
        "dark": colors["dark"], "muted": colors["muted"],
        "lockAccent": "#" + colors["active_border"][:6],
    }, indent=2) + "\n").encode()


def save_theme(home: Path, name: str):
    colors = palette(home, name)
    target = home / ".config/umbriel/awtarchy-trial/theme.toml"
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.is_symlink() or (target.exists() and (
            not target.is_file() or target.stat().st_uid != os.geteuid())):
        raise ValueError("Unsafe Umbriel theme output")
    body = render_toml(colors)
    fd, stage = tempfile.mkstemp(prefix=".umbriel-theme-", dir=target.parent)
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(body)
            f.flush()
            os.fsync(f.fileno())
        os.chmod(stage, 0o644)
        os.replace(stage, target)
    finally:
        if os.path.exists(stage):
            os.unlink(stage)
    # Preserve other compositors' current active theme. Umbriel has its own.
    state = home / ".local/state/awtarchy/active-theme-umbriel"
    state.parent.mkdir(parents=True, exist_ok=True)
    if state.is_symlink() or (state.exists() and not state.is_file()):
        raise ValueError("Unsafe Umbriel theme state")
    state.write_text(name + "\n", encoding="utf-8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("name", nargs="?")
    parser.add_argument("--print", dest="show", action="store_true")
    args = parser.parse_args()
    try:
        home = Path.home()
        colors = palette(home, args.name)
        if args.show or not args.name:
            print(render_toml(colors).decode(), end="")
        else:
            save_theme(home, args.name)
    except (OSError, ValueError, UnicodeError) as exc:
        print("Umbriel theme: " + str(exc), file=sys.stderr)
        sys.exit(1)
