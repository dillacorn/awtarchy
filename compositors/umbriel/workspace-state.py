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
    # Native Umbriel positions are per-output and change after workspace
    # transfers. Awtarchy's global 1-10 identifiers must come from the stable
    # explicit workspace name instead of "index". Keep old fixture compatibility
    # only when the IPC source lacks the native "named" field entirely.
    has_named_metadata = any(isinstance(ws, dict) and "named" in ws
                             for ws in workspaces)
    full = {}
    seen_numbers = set()
    for workspace in workspaces:
        if not isinstance(workspace, dict):
            continue
        index = workspace.get("index")
        output = workspace.get("output", "")
        identity = workspace.get("id", "")
        name = workspace.get("name")
        if has_named_metadata:
            if (workspace.get("named") is not True or
                    type(name) is not str or
                    not name.isascii() or not name.isdecimal()):
                continue
            number = int(name)
        else:
            number = index
        if (type(number) is not int or not 1 <= number <= 10
                or type(identity) not in (str, int) or not str(identity)
                or not isinstance(output, str) or not output):
            continue
        key = (str(identity), output)
        if number in seen_numbers and has_named_metadata:
            raise ValueError("Duplicate globally numbered Umbriel workspace " +
                             str(number))
        seen_numbers.add(number)
        full[key] = {
            "id": number, "name": str(name or number),
            "named": workspace.get("named") is True,
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
