#!/usr/bin/env python3
"""Preview or import explicitly configured Hyprland outputs into Mango rules.

Only literal hl.monitor({ ... }) statements are supported. This tool does not
execute Lua, infer unknown monitor modes, mutate Hyprland files, or replace
an existing Mango user profile.
"""
import argparse
from decimal import Decimal, InvalidOperation
import os
from pathlib import Path
import re
import sys

MONITOR_CALL = re.compile(r"(?m)^\s*hl\.monitor\s*\(\s*\{([^{}]*)\}\s*\)")
FIELD = re.compile(r'\s*([a-z_]+)\s*=\s*(?:"([^"]*)"|(-?\d+(?:\.\d+)?))\s*')
MODE = re.compile(r"(\d{2,4})x(\d{2,4})@(\d+(?:\.\d+)?)")
POSITION = re.compile(r"(-?\d+)x(-?\d+)")
NAME = re.compile(r"[A-Za-z0-9_.-]{1,80}")


class ProfileError(ValueError):
    pass


def parse_monitors(lua: str):
    # Hyprland's Lua convention uses -- comments. Strip them before matching.
    unmarked = "\n".join(line.split("--", 1)[0] for line in lua.splitlines())
    count = len(re.findall(r"(?m)^\s*hl\.monitor\s*\(", unmarked))
    calls = list(MONITOR_CALL.finditer(unmarked))
    if count != len(calls):
        raise ProfileError("Dynamic/nested hl.monitor statement; cannot import safely")

    screens = []
    skipped = []
    for match in calls:
        args = {}
        for field in match.group(1).split(","):
            if not field.strip():
                continue
            parsed = FIELD.fullmatch(field)
            if not parsed:
                raise ProfileError("Unsupported monitor field: " + field.strip())
            name, quoted, numeric = parsed.groups()
            if name in args or name not in ("output", "mode", "position", "scale", "vrr"):
                raise ProfileError("Duplicate or unsupported monitor field: " + name)
            args[name] = quoted if quoted is not None else numeric

        output = args.get("output", "")
        if not output:  # Catch-all hardware defaults must not become a regex.
            continue
        if not NAME.fullmatch(output):
            raise ProfileError("Invalid monitor connector: " + repr(output))
        m = MODE.fullmatch(args.get("mode", ""))
        p = POSITION.fullmatch(args.get("position", ""))
        if not (m and p):
            # A virtual monitor with an 'auto' position has no exact physical
            # placement to preserve; do not fabricate one.
            skipped.append(output)
            continue
        width, height = map(int, m.group(1, 2))
        refresh = Decimal(m.group(3))
        try:
            scale = Decimal(str(args.get("scale", "1")))
        except InvalidOperation as exc:
            raise ProfileError(f"Invalid scale for {output}") from exc
        if not (320 <= width <= 9999 and 240 <= height <= 9999 and
                Decimal("1") <= refresh <= Decimal("999") and
                Decimal("0.5") <= scale <= Decimal("4")):
            raise ProfileError(f"Unsafe mode/scale for {output}")
        vrr = str(args.get("vrr", "0"))
        if vrr not in ("0", "1"):
            raise ProfileError(f"Invalid VRR for {output}: {vrr}")
        if output in {item["name"] for item in screens}:
            raise ProfileError("Duplicate monitor connector: " + output)
        screens.append({
            "name": output, "width": width, "height": height,
            "refresh": refresh, "x": int(p.group(1)), "y": int(p.group(2)),
            "scale": scale, "vrr": vrr,
        })
    if not screens:
        raise ProfileError("No literal, positioned monitor rules to import")
    if len(screens) > 8:
        raise ProfileError("Too many explicit monitors")
    return screens, skipped


def rule_lines(screens, primary):
    if primary and primary not in {screen["name"] for screen in screens}:
        raise ProfileError(f"Requested primary {primary} is missing from Hyprland profile")
    left = min(screen["x"] for screen in screens)
    top = min(screen["y"] for screen in screens)
    result = [
        "# Awtarchy Mango trial: imported from explicit Hyprland monitor rules.",
        "# Coordinates normalized for XWayland; refresh rates are requested,",
        "# and Mango chooses the nearest EDID-advertised mode at this size.",
    ]
    for screen in screens:
        name = re.escape(screen["name"])
        fields = [
            f"name:^{name}$",
            f"width:{screen['width']}",
            f"height:{screen['height']}",
            f"refresh:{screen['refresh']}",
            f"x:{screen['x'] - left}",
            f"y:{screen['y'] - top}",
            f"scale:{screen['scale']}",
            f"vrr:{screen['vrr']}",
        ]
        if screen["name"] == primary:
            fields.append("primary:1")
        result.append("monitor_rule=" + ",".join(fields))
    return "\n".join(result) + "\n"


def apply_new_file(dest: Path, rendered: str):
    # Fail closed on existing profiles: these may contain the user's edits.
    if dest.is_symlink() or dest.exists():
        raise ProfileError(f"Refusing to overwrite existing Mango profile: {dest}")
    parent = dest.parent
    if not parent.is_dir() or parent.is_symlink():
        raise ProfileError(f"Destination directory missing or linked: {parent}")
    if parent.stat().st_uid != os.getuid():
        raise ProfileError("Mango profile parent is not owned by the current user")
    fd = os.open(dest, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as output:
            output.write(rendered)
            output.flush()
            os.fsync(output.fileno())
    except BaseException:
        dest.unlink(missing_ok=True)
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path,
                        default=Path.home() / ".config/hypr/hyprland.lua")
    parser.add_argument("--output", type=Path,
                        default=Path.home() / ".config/mango/monitors-local.conf")
    parser.add_argument("--primary", default="", help="XWayland primary output")
    parser.add_argument("--apply", action="store_true",
                        help="Create a new user-owned Mango profile; never overwrite")
    args = parser.parse_args()
    if not args.source.is_file() or args.source.is_symlink():
        raise ProfileError("Expected non-linked Hyprland Lua configuration")
    screens, skipped = parse_monitors(args.source.read_text(encoding="utf-8"))
    rendered = rule_lines(screens, args.primary)
    if skipped:
        print("Skipped unpositioned outputs: " + ", ".join(skipped), file=sys.stderr)
    print(rendered, end="")
    if args.apply:
        apply_new_file(args.output, rendered)
        print(f"Created: {args.output}", file=sys.stderr)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ProfileError) as exc:
        print(f"Monitor import refused: {exc}", file=sys.stderr)
        sys.exit(1)
