#!/usr/bin/env python3
"""Sway IPC monitor information for the isolated Quickshell manager."""
import json
import subprocess
import sys

def get(type_name):
    p = subprocess.run(["swaymsg", "-r", "-t", type_name], check=True,
                       capture_output=True, text=True, timeout=5)
    data = json.loads(p.stdout)
    if not isinstance(data, list):
        raise ValueError("Unexpected Sway IPC data for " + type_name)
    return data

def monitors():
    result = []
    for item in get("get_outputs"):
        if not isinstance(item, dict):
            raise ValueError("Unexpected Sway output data")
        rect = item.get("rect") or {}
        mode = item.get("current_mode") or {}
        result.append({
            "name": str(item["name"]),
            "width": int(rect.get("width", mode.get("width", 0))),
            "height": int(rect.get("height", mode.get("height", 0))),
            "x": int(rect.get("x", 0)),
            "y": int(rect.get("y", 0)),
            "scale": float(item.get("scale", 1)),
            "refresh_rate": float(mode.get("refresh", 0)) / 1000,
            "focused": bool(item.get("focused", False)),
            "disabled": not bool(item.get("active", False))
        })
    return result

def active():
    values = get("get_workspaces")
    focused = next((w for w in values if w.get("focused")), None)
    if not focused:
        return {"name": "", "id": -1, "monitor": ""}
    return {
        "name": str(focused.get("name", "")),
        "id": int(focused.get("num", -1)),
        "monitor": str(focused.get("output", ""))
    }

def main():
    if len(sys.argv) != 2 or sys.argv[1] not in ("monitors", "activeworkspace"):
        raise ValueError("Usage: monitor-info.py monitors|activeworkspace")
    result = monitors() if sys.argv[1] == "monitors" else active()
    print(json.dumps(result, separators=(",", ":")))

if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError, subprocess.CalledProcessError,
            subprocess.TimeoutExpired, json.JSONDecodeError) as error:
        print("Sway monitor IPC: " + str(error), file=sys.stderr)
        sys.exit(1)
