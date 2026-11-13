#!/usr/bin/env python3
"""Sway-native Quickshell Quick Settings status and supported commands.

Every unavailable compositor feature remains visibly unavailable; never call
Hyprland scripts or acknowledge a no-op as a successful setting change.
"""
import json
import os
from pathlib import Path
import re
import subprocess
import sys

HOME = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config")))
TRIAL = HOME / "sway/awtarchy-trial"
MANAGER = TRIAL / "quickshell.sh"
OUTPUT_INFO = TRIAL / "monitor-info.py"
DDC_STATUS = TRIAL / "ddc.sh"
DDC_CONTROL = TRIAL / "hypr-ddc-brightness.sh"

def command(args):
    result = subprocess.run(args, capture_output=True, text=True, timeout=5)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "Backend command failed")
    return result.stdout.strip()

def manager(action, name, value=None):
    if not MANAGER.is_file() or MANAGER.is_symlink():
        raise RuntimeError("Sway Quickshell manager unavailable")
    return command(["bash", str(MANAGER), action, name] + ([] if value is None else [value]))

def output_list():
    if not OUTPUT_INFO.is_file() or OUTPUT_INFO.is_symlink():
        raise RuntimeError("Sway monitor inventory backend unavailable")
    monitors = json.loads(command(["python3", str(OUTPUT_INFO), "monitors"]))
    if not isinstance(monitors, list):
        raise RuntimeError("Invalid Sway monitor inventory")
    return [
        {
            "name": str(m.get("name", "")),
            "description": "",
            "focused": bool(m.get("focused")),
            "width": int(m.get("width") or 0),
            "height": int(m.get("height") or 0),
            "refresh_rate": float(m.get("refresh_rate") or 0)
        }
        for m in monitors if isinstance(m, dict) and not m.get("disabled")
    ]

def brightness_status(monitor, monitors):
    """Return cached/queried brightness for the exact requested Sway output."""
    known = {m["name"] for m in monitors}
    if monitor not in known or not DDC_STATUS.is_file() or DDC_STATUS.is_symlink():
        return {"target": monitor, "connector": "", "current": None, "max": None}

    env = os.environ.copy()
    env["AWTARCHY_OUTPUT_NAME"] = monitor
    try:
        result = subprocess.run(
            [str(DDC_STATUS), "status"], env=env, text=True,
            capture_output=True, timeout=8, check=True,
        )
        data = json.loads(result.stdout)
        percent = data.get("percentage")
        if type(percent) is not int or not 0 <= percent <= 100:
            raise ValueError("DDC brightness status unavailable")
        return {"target": monitor, "connector": monitor,
                "current": percent, "max": 100}
    except (OSError, ValueError, subprocess.CalledProcessError,
            subprocess.TimeoutExpired, json.JSONDecodeError):
        return {"target": monitor, "connector": "", "current": None, "max": None}


def status(args):
    panel = args[0] if len(args) > 0 else ""
    brightness = args[1] if len(args) > 1 else "Focused display"
    monitors = output_list()
    names = {m["name"] for m in monitors}
    if panel and panel not in names:
        raise ValueError("Unknown Sway panel monitor")
    target = brightness if brightness in names else next(
        (m["name"] for m in monitors if m["focused"]), "")
    brightness_data = brightness_status(target, monitors)
    position, enabled, auto_hide = "top", True, False
    if panel:
        position = manager("getpos", panel)
        enabled = manager("getenabled", panel) == "true"
        auto_hide = manager("getautohide", panel) == "true"
    mode = "reset"
    state = Path(os.environ.get("XDG_RUNTIME_DIR",
                os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache")))) / "awtarchy-sway-submap"
    if state.is_file() and not state.is_symlink():
        raw = state.read_text(encoding="utf-8").strip()
        mode = raw if raw in ("noalt", "mouse", "vm") else "reset"
    print(json.dumps({
        "monitors": monitors,
        "brightness": brightness_data,
        "bar": {"monitor": panel, "position": position,
                "enabled": enabled, "auto_hide": auto_hide},
        "night_light": {"temperature": None, "identity": "unsupported",
                        "enabled": False, "schedule_enabled": False,
                        "schedule_start": "20:00", "schedule_end": "07:00",
                        "schedule_temperature": None, "schedule_next_day": False},
        "vibrance": {"value": None, "enabled": False},
        "submap": mode,
        "sched_ext": {"running": "off", "mode": "", "enabled": False,
                      "last_selected": "", "restore_enabled": False,
                      "available": False, "authorized": False, "schedulers": []}
    }, separators=(",", ":")))

def action(args):
    if not args:
        raise ValueError("Expected Quick Settings action")
    name, rest = args[0], args[1:]
    dispatch = {
        "bar-enabled": ("setenabled", ("true", "false")),
        "bar-auto-hide": ("setautohide", ("true", "false")),
        "bar-position": ("setpos", ("top", "bottom", "left", "right")),
    }
    if name in dispatch:
        if len(rest) != 2:
            raise ValueError("Expected monitor and value")
        mon, value = rest
        if not re.fullmatch(r"[A-Za-z0-9._-]{1,64}", mon):
            raise ValueError("Invalid monitor name")
        if value not in dispatch[name][1]:
            raise ValueError("Invalid bar setting")
        if mon not in {m["name"] for m in output_list()}:
            raise ValueError("Unknown Sway monitor")
        manager(dispatch[name][0], mon, value)
        return
    if name == "brightness-percent":
        if len(rest) != 2:
            raise ValueError("Expected monitor and brightness percentage")
        mon, percent = rest
        if mon not in {m["name"] for m in output_list()}:
            raise ValueError("Unknown Sway monitor")
        if not re.fullmatch(r"(?:100|[0-9]|[1-9][0-9])", percent):
            raise ValueError("Brightness percentage must be 0-100")
        if not DDC_CONTROL.is_file() or DDC_CONTROL.is_symlink():
            raise RuntimeError("Awtarchy DDC controller unavailable")
        command([str(DDC_CONTROL), "--monitor", mon, "set-percent", percent])
        return
    if name == "wallpaper" and not rest:
        command(["awtwall"])
        return
    raise RuntimeError(f"Sway setting '{name}' is not supported; nothing was changed")

def main():
    if os.environ.get("XDG_CURRENT_DESKTOP") != "sway" or not os.environ.get("WAYLAND_DISPLAY"):
        raise ValueError("Not in a Sway session")
    if not sys.argv[1:]:
        raise ValueError("Expected --status-json or --action")
    mode, args = sys.argv[1], sys.argv[2:]
    if mode == "--status-json":
        status(args)
    elif mode == "--action":
        action(args)
    elif mode in ("--restore-scheduler", "--authorize-scheduler-stdin"):
        raise RuntimeError("Sway sched-ext integration has not been verified")
    else:
        raise ValueError(f"Unknown Quick Settings command: {mode}")

if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, ValueError, OSError, TypeError, KeyError, subprocess.TimeoutExpired,
            json.JSONDecodeError) as error:
        print(f"Sway Quick Settings: {error}", file=sys.stderr)
        sys.exit(1)
