#!/usr/bin/env python3
"""Read actual Umbriel workspace/window snapshots, not Sway or Hyprland IPC."""
import json
import subprocess
import sys


def query(name):
    p = subprocess.run(["umbriel", name, "--json"], check=True,
                       capture_output=True, text=True, timeout=6)
    result = json.loads(p.stdout)
    if isinstance(result, dict):
        result = result.get("ok", result.get(name))
    if not isinstance(result, list):
        raise ValueError("Invalid Umbriel " + name + " response")
    return result


def collect(workspaces=None, windows=None):
    # Preserve the standalone diagnostic; the live IPC subscriber supplies
    # coherent snapshots directly without spawning separate Umbriel CLIs.
    if workspaces is None:
        workspaces = query("workspaces")
    if windows is None:
        windows = query("windows")
    full = {}
    for workspace in workspaces:
        if not isinstance(workspace, dict):
            continue
        index = workspace.get("index")
        output = workspace.get("output", "")
        identity = workspace.get("id", "")
        if (type(index) is not int or not 1 <= index <= 10
                or type(identity) not in (str, int) or not str(identity)
                or not isinstance(output, str) or not output):
            continue
        key = (str(identity), output)
        full[key] = {
            "id": index, "name": str(workspace.get("name", index)),
            "monitor": output, "active": bool(workspace.get("active")),
            "focused": bool(workspace.get("focused")),
            "urgent": bool(workspace.get("urgent")),
            "fullscreen": False, "clients": []
        }
    for window in windows:
        if not isinstance(window, dict):
            continue
        identity = window.get("workspace", "")
        output = window.get("output", "")
        key = (str(identity), output)
        if key not in full:
            continue
        full[key]["fullscreen"] |= bool(window.get("fullscreen"))
        full[key]["clients"].append({
            "title": str(window.get("title", "")),
            "app_id": str(window.get("app_id", "")),
            # Umbriel's window.active is the globally activated toplevel.
            # Its window.focused is remembered per workspace, including
            # inactive workspaces, so it is not a reliable activation flag.
            "focused": bool(window.get("active")) and full[key]["focused"],
            "urgent": bool(window.get("urgent")),
        })
    return sorted(full.values(), key=lambda x: (x["monitor"], x["id"]))


if __name__ == "__main__":
    try:
        print(json.dumps(collect(), separators=(",", ":")))
    except (ValueError, OSError, KeyError, TypeError, subprocess.CalledProcessError,
            subprocess.TimeoutExpired, json.JSONDecodeError) as exc:
        print("Umbriel workspace IPC: " + str(exc), file=sys.stderr)
        sys.exit(1)
