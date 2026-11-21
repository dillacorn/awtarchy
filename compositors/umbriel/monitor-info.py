#!/usr/bin/env python3
"""Umbriel CLI output adapter for the isolated Awtarchy Quickshell manager."""
import json
import subprocess
import sys


def query(kind):
    result = subprocess.run(["umbriel", kind, "--json"], check=True,
                            capture_output=True, text=True, timeout=6)
    value = json.loads(result.stdout)
    if isinstance(value, dict):
        value = value.get("ok", value.get(kind))
    if not isinstance(value, list):
        raise ValueError("Expected Umbriel " + kind + " array")
    return value


def monitors():
    result = []
    for item in query("outputs"):
        logical = item.get("logical_size") or {}
        pos = item.get("position") or {}
        current = next((mode for mode in item.get("modes", []) if mode.get("current")), {})
        result.append({
            "name": str(item.get("name", "")),
            "width": int(logical.get("width", 0)),
            "height": int(logical.get("height", 0)),
            "x": int(pos.get("x", 0)),
            "y": int(pos.get("y", 0)),
            "scale": float(item.get("scale", 1)),
            "refresh_rate": float(current.get("refresh_mhz", 0)) / 1000,
            "focused": bool(item.get("focused")),
            "disabled": not bool(item.get("enabled"))
        })
    return result


def active():
    focused = next((w for w in query("workspaces") if w.get("focused")), None)
    if not focused:
        return {"name": "", "id": -1, "monitor": ""}
    return {
        "name": str(focused.get("name", "")),
        "id": int(focused.get("index", -1)),
        "monitor": str(focused.get("output", ""))
    }


if __name__ == "__main__":
    try:
        if len(sys.argv) != 2 or sys.argv[1] not in ("monitors", "activeworkspace"):
            raise ValueError("Usage: monitor-info.py monitors|activeworkspace")
        print(json.dumps(monitors() if sys.argv[1] == "monitors" else active(),
                         separators=(",", ":")))
    except (ValueError, OSError, KeyError, TypeError, subprocess.CalledProcessError,
            subprocess.TimeoutExpired, json.JSONDecodeError) as exc:
        print("Umbriel monitor IPC: " + str(exc), file=sys.stderr)
        sys.exit(1)
