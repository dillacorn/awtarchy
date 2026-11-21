#!/usr/bin/env python3
"""Cycle application windows on the active Sway workspace across floating/tiling.

Sway's native 'focus next' only cycles within the current container group.
The explicit leaf order below includes both tiling and floating trees so a
floating toplevel does not trap Alt+Tab away from the windows behind it.
No application is launched, closed, moved, tiled, or unfullscreened.
"""
import json
import os
import subprocess
import sys


def ipc(*args):
    result = subprocess.run(
        ["swaymsg", "-r", *args], capture_output=True, text=True, timeout=5
    )
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or "Sway IPC failed")
    return json.loads(result.stdout)


def find_workspace(node, workspace_id, name, output):
    if not isinstance(node, dict):
        return None
    if node.get("type") == "workspace":
        if workspace_id is not None and node.get("id") == workspace_id:
            return node
        if workspace_id is None and node.get("name") == name and output:
            return node
    for child in node.get("nodes", []) + node.get("floating_nodes", []):
        found = find_workspace(child, workspace_id, name, output)
        if found is not None:
            return found
    return None


def toplevels(node):
    """Return ordered real application leaves, not structural split containers."""
    result = []
    if not isinstance(node, dict):
        return result
    children = node.get("nodes", []) + node.get("floating_nodes", [])
    for child in children:
        result.extend(toplevels(child))
    if not children and node.get("type") in ("con", "floating_con"):
        props = node.get("window_properties") or {}
        if (node.get("app_id") or props.get("class") or node.get("window")):
            if isinstance(node.get("id"), int):
                result.append(node)
    return result


def choice(tree, workspaces, direction):
    active = next((w for w in workspaces if w.get("focused") is True), None)
    if not active:
        raise ValueError("No focused Sway workspace")
    ws = find_workspace(tree, active.get("id"), active.get("name"),
                        active.get("output"))
    if ws is None:
        raise ValueError("Focused Sway workspace absent from tree")
    windows = toplevels(ws)
    if len(windows) < 2:
        return None
    if not toplevels({"floating_nodes": ws.get("floating_nodes", [])}):
        # Preserve native focus next/prev for tiled-only workspaces;
        # custom cycling is needed only across the distinct floating tree.
        return "native"
    focused = next((i for i, c in enumerate(windows) if c.get("focused")), -1)
    increment = 1 if direction == "next" else -1
    return windows[(focused + increment) % len(windows)]["id"]


def main():
    if (len(sys.argv) != 2 or sys.argv[1] not in ("next", "prev")):
        raise ValueError("Usage: focus-cycle.py next|prev")
    if os.environ.get("XDG_CURRENT_DESKTOP") != "sway" or not os.environ.get("SWAYSOCK"):
        raise ValueError("An active Sway session is required")
    selected = choice(ipc("-t", "get_tree"), ipc("-t", "get_workspaces"), sys.argv[1])
    if selected is None:
        return
    instruction = (f"focus {sys.argv[1]}" if selected == "native"
                   else f"[con_id={selected}] focus")
    response = ipc("-t", "command", instruction)
    if not isinstance(response, list) or not response or not all(
        item.get("success") is True for item in response if isinstance(item, dict)
    ):
        raise RuntimeError("Sway refused focused-window change")


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, ValueError, KeyError, TypeError,
            json.JSONDecodeError, subprocess.TimeoutExpired) as error:
        print("Sway focus cycle: " + str(error), file=sys.stderr)
        sys.exit(1)
