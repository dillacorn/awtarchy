#!/usr/bin/env python3
"""Read-only Sway workspace membership from its authoritative IPC tree.

Unlike ext-foreign-toplevel, Sway get_tree includes hidden workspaces.
Never assign a window to whichever workspace happens to be active.
"""
import json
import subprocess
import sys


def ipc(message):
    result = subprocess.run(
        ["swaymsg", "-r", "-t", message], check=True, capture_output=True,
        text=True, timeout=5
    )
    return json.loads(result.stdout)


def walk(node):
    if not isinstance(node, dict):
        return
    yield node
    for key in ("nodes", "floating_nodes"):
        for child in node.get(key) or ():
            yield from walk(child)


def clients_for(workspace):
    found = []
    for node in walk(workspace):
        if node is workspace:
            continue
        if node.get("type") != "con":
            continue
        props = node.get("window_properties") or {}
        app_id = str(node.get("app_id") or props.get("class") or "")
        if not app_id and node.get("window") is None:
            continue
        title = str(node.get("name") or "")
        # Shell utility toplevels must never make an otherwise empty user
        # workspace appear occupied in the bar.
        if title in (
            "Awtarchy Application Search", "Awtarchy Clipboard History",
            "Awtarchy Notification Center", "Awtarchy Quick Settings",
            "Awtarchy Network", "Awtarchy Bluetooth", "Awtarchy Battery",
        ):
            continue
        found.append({
            "id": node.get("id"),
            "title": title,
            "app_id": app_id,
            "urgent": bool(node.get("urgent", False)),
            "fullscreen": bool(node.get("fullscreen_mode", 0)),
            "focused": bool(node.get("focused", False)),
        })
    return found


def collect(tree, workspaces):
    if not isinstance(tree, dict) or not isinstance(workspaces, list):
        raise ValueError("Sway IPC returned unexpected workspace/tree types")
    nodes = {str(item.get("name")): item for item in walk(tree)
             if item.get("type") == "workspace" and isinstance(item.get("name"), str)}
    records = []
    for item in workspaces:
        number = item.get("num")
        if not isinstance(number, int) or isinstance(number, bool) or not 1 <= number <= 10:
            continue
        title = str(item.get("name", ""))
        tree_node = nodes.get(title)
        clients = clients_for(tree_node) if tree_node is not None else []
        records.append({
            "id": number,
            "name": title,
            "monitor": str(item.get("output") or ""),
            "active": bool(item.get("visible", False)),
            "focused": bool(item.get("focused", False)),
            "urgent": bool(item.get("urgent", False)) or any(w["urgent"] for w in clients),
            "fullscreen": any(w["fullscreen"] for w in clients),
            "clients": clients,
        })
    return sorted(records, key=lambda w: (w["id"], w["monitor"]))


def main():
    if len(sys.argv) != 1:
        raise ValueError("No arguments accepted")
    print(json.dumps(collect(ipc("get_tree"), ipc("get_workspaces")),
                     separators=(",", ":")))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError,
            subprocess.TimeoutExpired, json.JSONDecodeError) as error:
        print("Sway workspace IPC: " + str(error), file=sys.stderr)
        sys.exit(1)
