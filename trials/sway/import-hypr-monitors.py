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

def connected_drm_outputs():
    """Return kernel connector names; empty means no safe offline match."""
    result = set()
    directory = Path("/sys/class/drm")
    if not directory.is_dir():
        return result
    for entry in directory.glob("card*-*/status"):
        match = re.fullmatch(r"card\\d+-(.+)", entry.parent.name)
        if not match or not NAME.fullmatch(match.group(1)):
            continue
        try:
            if entry.read_text(encoding="ascii").strip() == "connected":
                result.add(match.group(1))
        except OSError:
            continue
    return result


def outputs_from_saved_hyprland():
    """Import literal monitor declarations without evaluating untrusted Lua.

    Only complete explicit modes, positions and scales can be translated.
    The Awtarchy default 'preferred/auto' entry is intentionally ignored.
    """
    path = Path(os.environ.get(
        "XDG_CONFIG_HOME", str(Path.home() / ".config"))) / "hypr/hyprland.lua"
    if path.is_symlink() or not path.is_file() or path.stat().st_size > 1024 * 1024:
        raise ValueError("No safe saved Hyprland monitor config")
    lines = []
    names = set()
    text = path.read_text(encoding="utf-8")
    for line in text.splitlines():
        # Never run Lua or infer values from functions, expressions or variables.
        match = re.fullmatch(r"\s*hl\.monitor\(\{(.*?)\}\)\s*(?:--.*)?", line)
        if not match:
            continue
        fields = {}
        source = match.group(1).strip().rstrip(",").strip()
        fields_re = re.compile(
            r"""\s*(output|mode|position|scale|vrr)\s*=\s*("[^"]*"|'[^']*'|\d+(?:\.\d+)?)\s*(?:,|$)"""
        )
        cursor = 0
        while cursor < len(source):
            found = fields_re.match(source, cursor)
            if not found or found.group(1) in fields:
                fields = {}
                break
            value = found.group(2)
            fields[found.group(1)] = value[1:-1] if value[:1] in ("'", '"') else value
            cursor = found.end()
        name = fields.get("output", "")
        if not name:
            continue
        if not NAME.fullmatch(name) or name in names:
            raise ValueError("Duplicate or unsafe saved Hyprland output")
        mode = re.fullmatch(r"(\d{3,5})x(\d{3,5})@(\d+(?:\.\d+)?)", fields.get("mode", ""))
        position = re.fullmatch(r"(-?\d+)x(-?\d+)", fields.get("position", ""))
        try:
            scale = Decimal(fields.get("scale", ""))
            refresh = Decimal(mode.group(3)) if mode else Decimal(0)
        except (ValueError, ArithmeticError):
            continue
        if (not mode or not position or not 20 <= refresh <= 1000
                or not 0 < scale <= 8 or int(mode.group(1)) <= 0
                or int(mode.group(2)) <= 0):
            continue
        vrr = fields.get("vrr", "0")
        if vrr not in ("0", "1"):
            continue
        names.add(name)
        lines.append((name, int(mode.group(1)), int(mode.group(2)),
                      int(position.group(1)), int(position.group(2)), refresh, scale, vrr))
    if not lines:
        raise ValueError("No complete literal Hyprland monitor settings to import")
    connected = connected_drm_outputs()
    if not connected or not names.issubset(connected):
        raise ValueError("Saved monitor names are not verified against connected DRM outputs")
    min_x = min(row[3] for row in lines)
    min_y = min(row[4] for row in lines)
    result = [
        f"output {name} mode {width}x{height}@{hz}Hz position {x-min_x} {y-min_y} scale {scale}"
        for name, width, height, x, y, hz, scale, _ in lines
    ]
    result.extend(f"output {name} adaptive_sync on"
                  for name, *_rest, vrr in lines if vrr == "1")
    return result


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
    lines = [
        f"output {name} mode {w}x{h}@{hz}Hz position {x-min_x} {y-min_y} scale {scale}"
        for name, w, h, x, y, hz, scale in out
    ]
    # Hyprland/Hyprmoncfg's active transform and VRR become native Sway
    # commands. Unset fields stay on Sway's normal defaults.
    transforms = ("normal", "90", "180", "270", "flipped",
                  "flipped-90", "flipped-180", "flipped-270")
    for monitor in data:
        name = monitor["name"]
        transform = monitor.get("transform", 0)
        if type(transform) is int and 1 <= transform < len(transforms):
            lines.append(f"output {name} transform {transforms[transform]}")
        if monitor.get("vrr") is True or monitor.get("vrr") == 1:
            lines.append(f"output {name} adaptive_sync on")
    return lines


def active_hyprmoncfg_additions(live_lines):
    """Transfer only representable extra settings from the active saved profile.

    hyprctl owns the actual current modes/scale/positions. Never blindly apply
    another saved profile with mismatched connected outputs or unsupported
    mirror, color, rotation-auto or workspace strategy settings.
    """
    live = {match.group(1) for line in live_lines
            if (match := re.match(r"^output ([A-Za-z0-9_.-]+) mode ", line))}
    if not live:
        return [], []
    try:
        status = subprocess.run(["hyprmoncfg", "status", "--json"],
                                capture_output=True, text=True, timeout=5, check=True)
        active = json.loads(status.stdout).get("active_profile")
        name = active.get("name") if isinstance(active, dict) else None
        if not isinstance(name, str) or not name:
            return [], []
        directory = Path(os.environ.get(
            "XDG_CONFIG_HOME", str(Path.home() / ".config"))) / "hyprmoncfg/profiles"
        if directory.is_symlink() or not directory.is_dir():
            return [], []
        profile = None
        for item in sorted(directory.glob("*.json"))[:128]:
            if item.is_symlink() or not item.is_file() or item.stat().st_size > 262144:
                continue
            candidate = json.loads(item.read_text(encoding="utf-8"))
            if isinstance(candidate, dict) and candidate.get("name") == name:
                if profile is not None:
                    return [], []  # Never select between duplicate names.
                profile = candidate
        if not isinstance(profile, dict):
            return [], []
        outputs = profile.get("outputs")
        if not isinstance(outputs, list) or not 0 < len(outputs) <= 32:
            return [], []
        names, enabled, by_key = set(), set(), {}
        for value in outputs:
            if not isinstance(value, dict):
                return [], []
            output_name = value.get("name")
            if (not isinstance(output_name, str)
                    or not NAME.fullmatch(output_name) or output_name in names
                    or type(value.get("enabled")) is not bool):
                return [], []
            names.add(output_name)
            if value["enabled"]:
                enabled.add(output_name)
            key = value.get("key")
            if isinstance(key, str):
                by_key[key] = output_name
        if enabled != live:
            return [], []  # The saved profile is not the live layout.
        extra = []
        for value in outputs:
            output_name = value["name"]
            if not value["enabled"]:
                extra.append(f"output {output_name} disable")
                continue
            # Hyprmoncfg's saved VRR=1 is a direct mapping. Its auto VRR=2
            # and specialized HDR/color/mirroring settings are not portable.
            if value.get("vrr") == 1 and not any(
                    line == f"output {output_name} adaptive_sync on"
                    for line in live_lines):
                extra.append(f"output {output_name} adaptive_sync on")
            transform = value.get("transform")
            transforms = ("normal", "90", "180", "270", "flipped",
                          "flipped-90", "flipped-180", "flipped-270")
            if (type(transform) is int and 1 <= transform < len(transforms)
                    and not any(line.startswith(f"output {output_name} transform ")
                                for line in live_lines)):
                extra.append(f"output {output_name} transform {transforms[transform]}")
        workspaces = profile.get("workspaces") or {}
        rules = []
        if (isinstance(workspaces, dict) and workspaces.get("enabled") is True
                and workspaces.get("strategy", "manual") == "manual"):
            seen = set()
            for rule in workspaces.get("rules", []):
                if not isinstance(rule, dict):
                    return extra, []
                number = str(rule.get("workspace", ""))
                output_name = rule.get("output_name") or by_key.get(rule.get("output_key"))
                if (not number.isdecimal() or not 1 <= int(number) <= 10
                        or number in seen or output_name not in enabled):
                    return extra, []
                seen.add(number)
                rules.append(f"workspace {number} output {output_name}")
        return extra, rules
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError,
            subprocess.CalledProcessError, subprocess.TimeoutExpired):
        return [], []  # Live Hyprland geometry remains authoritative.


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
    ap.add_argument("--from-saved", action="store_true", help="Use only literal saved Hyprland monitor settings")
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
    if args.from_saved:
        lines = outputs_from_saved_hyprland()
        workspace_lines = []
    else:
        lines = outputs_from_hyprland()
        profile_extras, workspace_lines = active_hyprmoncfg_additions(lines)
        lines.extend(profile_extras)
    result = insert_profile(previous, lines)
    # nwg-displays owns this Sway-only file after the first customization.
    # Import only into the untouched stock stub, never into user settings.
    workspace_target = cfg.parent.parent / "workspaces"
    stub = "# Sway workspace-to-output bindings saved by nwg-displays. This file belongs to the user after editing.\n"
    if workspace_target.is_symlink() or (workspace_target.exists()
            and (not workspace_target.is_file()
                 or workspace_target.stat().st_uid != os.geteuid())):
        workspace_lines = []
    previous_workspaces = (workspace_target.read_text(encoding="utf-8")
                           if workspace_target.is_file() and not workspace_target.is_symlink()
                           else "")
    if previous_workspaces not in ("", stub):
        workspace_lines = []
    print("Proposed Sway output profile:")
    for line in lines:
        print("  " + line)
    if workspace_lines:
        print("Proposed active Hyprmoncfg workspace assignments:")
        for line in workspace_lines:
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
    if workspace_lines:
        # Guard against concurrent nwg-displays edits during the import.
        if (workspace_target.is_symlink()
                or (workspace_target.exists() and
                    workspace_target.read_text(encoding="utf-8") != previous_workspaces)):
            print("PRESERVE: Sway workspaces changed during import", file=sys.stderr)
        else:
            if workspace_target.exists():
                ws_backup = workspace_target.with_name("workspaces.backup-" + stamp)
                with ws_backup.open("xb") as handle:
                    os.fchmod(handle.fileno(), 0o600)
                    handle.write(previous_workspaces.encode())
                    handle.flush()
                    os.fsync(handle.fileno())
            with tempfile.NamedTemporaryFile(dir=workspace_target.parent,
                    prefix=".sway-workspaces-", delete=False) as handle:
                workspace_temp = Path(handle.name)
                handle.write(("\n".join(workspace_lines) + "\n").encode())
                handle.flush()
                os.fsync(handle.fileno())
            try:
                workspace_temp.chmod(0o600)
                os.replace(workspace_temp, workspace_target)
            finally:
                workspace_temp.unlink(missing_ok=True)
            print("Imported active Hyprmoncfg workspace-to-output rules")
    print("PASS: one-time Sway monitor import; backup: " + str(backup))

if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError, UnicodeError, json.JSONDecodeError,
            subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        print("Sway monitor import: " + str(error), file=sys.stderr)
        sys.exit(1)
