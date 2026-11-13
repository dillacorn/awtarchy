#!/usr/bin/env python3
"""Sway equivalent of Hyprland's floating-only launch_handler.sh.

Only exact, known application identities are managed. Tiled windows are never
closed; the two explicitly protected utilities are not duplicated when tiled.
"""
import json
import os
from pathlib import Path
import subprocess
import sys

CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config")))
HYPR_SCRIPTS = CONFIG / "hypr/scripts"

# Identity, executable argv and whether a manually tiled instance blocks launch.
UTILITIES = {
    "btop": (("btop",), ("foot", "--app-id", "btop", "btop"), False),
    "maccel": (("maccel",), ("foot", "--app-id", "maccel", "maccel", "tui"), False),
    "wiremix": (("Wiremix",), ("foot", "--app-id", "Wiremix", "wiremix"), False),
    "default-apps": (
        ("awtarchy-default-apps",),
        ("foot", "--app-id", "awtarchy-default-apps", "--title",
         "awtarchy-default-apps", "python3", str(HYPR_SCRIPTS / "default_applications.py"), "tui"),
        True),
    "hyprmoncfg": (
        ("hyprmoncfg",),
        (str(HYPR_SCRIPTS / "default_terminal.sh"), "--class", "hyprmoncfg",
         "--", "hyprmoncfg"), True),
    "smtty": (
        ("smtty",), (str(HYPR_SCRIPTS / "default_terminal.sh"),
                    "--class", "smtty", "--", "smtty"), False),
    "smtty-O": (
        ("smtty-O",), (str(HYPR_SCRIPTS / "default_terminal.sh"),
                      "--class", "smtty-O", "--hold", "--", "smtty", "-O"), False),
    "wallpicker": (
        ("wallpicker",), ("foot", "--app-id", "wallpicker", "awtwall", "--resume"), False),
    "pavucontrol": (
        ("pavucontrol", "org.pulseaudio.pavucontrol"), ("pavucontrol",), False),
    "pulsemixer": (
        ("Pulsemixer",), ("foot", "--app-id", "Pulsemixer", "pulsemixer"), False),
    "awtarchy-tips-tui": (
        ("awtarchy-tips-tui",), ("foot", "--app-id", "awtarchy-tips-tui",
                               str(HYPR_SCRIPTS / "awtarchy-tips-tui.sh")), False),
}

def ipc(*argv):
    result = subprocess.run(
        ["swaymsg", "-r", *argv], capture_output=True, text=True, timeout=5,
        check=True)
    return json.loads(result.stdout)

def walk(node, workspace=None, floating=False):
    if not isinstance(node, dict):
        return
    if node.get("type") == "workspace":
        workspace = str(node.get("name") or "")
        if workspace == "__i3_scratch":
            return
    floating = floating or node.get("type") == "floating_con" or (
        node.get("floating") in ("auto_on", "user_on"))
    if isinstance(node.get("id"), int) and (
            node.get("app_id") or (node.get("window_properties") or {}).get("class")):
        yield node, workspace, floating
    for child in node.get("nodes", []):
        yield from walk(child, workspace, floating)
    for child in node.get("floating_nodes", []):
        yield from walk(child, workspace, True)

def classify(tree, workspaces, identities, protect_tiled):
    focused = next((str(w.get("name") or "") for w in workspaces
                    if w.get("focused") is True), None)
    if not focused:
        raise ValueError("Sway did not report a focused workspace")
    identities = {name.casefold() for name in identities}
    local, remote = [], []
    tiled = False
    for node, workspace, floating in walk(tree):
        names = (node.get("app_id"), (node.get("window_properties") or {}).get("class"))
        if not any(isinstance(name, str) and name.casefold() in identities for name in names):
            continue
        if not floating:
            tiled = True
            continue
        if workspace == focused:
            local.append(node["id"])
        elif workspace:
            remote.append(node["id"])
    if protect_tiled and tiled:
        return (), False
    if local:
        return (local[-1],), False
    return tuple(remote), True

def toggle(name):
    if name not in UTILITIES:
        raise ValueError("Unknown Sway utility: " + name)
    if os.environ.get("XDG_CURRENT_DESKTOP", "").casefold() != "sway" or not os.environ.get("SWAYSOCK"):
        raise ValueError("An active Sway session is required")
    identities, argv, protect = UTILITIES[name]
    targets, should_launch = classify(ipc("-t", "get_tree"), ipc("-t", "get_workspaces"),
                                      identities, protect)
    for con_id in targets:
        result = ipc("-t", "command", f"[con_id={con_id}] kill")
        if not isinstance(result, list) or not result or not all(
                isinstance(row, dict) and row.get("success") is True for row in result):
            raise RuntimeError(f"Sway refused to close utility container {con_id}")
    if should_launch:
        subprocess.Popen(argv, stdin=subprocess.DEVNULL,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True)

if __name__ == "__main__":
    try:
        if len(sys.argv) != 2:
            raise ValueError("Usage: toggle-utility.py UTILITY")
        toggle(sys.argv[1])
    except (OSError, RuntimeError, ValueError, KeyError, subprocess.CalledProcessError,
            subprocess.TimeoutExpired, json.JSONDecodeError) as error:
        print("Awtarchy Sway utility toggle: " + str(error), file=sys.stderr)
        sys.exit(1)
