#!/usr/bin/env python3
"""Regression test for Alt+Tab across tiled/floating Sway windows."""
import importlib.util
from pathlib import Path
from unittest.mock import patch
import os

root = Path(__file__).resolve().parents[1]
source = root / "compositors/sway/focus-cycle.py"
spec = importlib.util.spec_from_file_location("sway_focus_cycle", source)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def leaf(identifier, identity, *, focused=False, xwayland=False):
    return {
        "type": "con", "id": identifier, "name": identity,
        "app_id": None if xwayland else identity,
        "window_properties": {"class": identity} if xwayland else {},
        "focused": focused, "nodes": [], "floating_nodes": [],
    }


def workspace(tiles, floating):
    return {
        "type": "workspace", "id": 42, "name": "2",
        "nodes": tiles, "floating_nodes": floating,
    }


def tree(tiles, floating):
    return {"type": "root", "nodes": [
        {"type": "output", "name": "DP-1", "nodes": [
            workspace(tiles, floating)
        ], "floating_nodes": []},
        {"type": "output", "name": "DP-3", "nodes": [
            {"type": "workspace", "id": 56, "name": "3",
             "nodes": [leaf(88, "vesktop")], "floating_nodes": []}
        ], "floating_nodes": []}
    ]}


focus = [{"id": 42, "name": "2", "output": "DP-1", "focused": True},
         {"id": 56, "name": "3", "output": "DP-3", "focused": False}]

# Floating focus cycles back to the tiled application below it.
floating = tree([leaf(11, "firefox")], [leaf(21, "protonup", focused=True)])
assert module.choice(floating, focus, "next") == 11
assert module.choice(floating, focus, "prev") == 11

# Tiled focus cycles onto a floating dialog; include nested split containers
# and native or XWayland toplevels, never unrelated workspaces.
nested = tree([
    {"type": "con", "id": 100, "nodes": [
        leaf(11, "firefox", focused=True), leaf(12, "foot")
    ], "floating_nodes": []}
], [leaf(21, "pupgui2", xwayland=True)])
assert module.choice(nested, focus, "next") == 12
assert module.choice(nested, focus, "prev") == 21
nested["nodes"][0]["nodes"][0]["nodes"][0]["nodes"][0]["focused"] = False
nested["nodes"][0]["nodes"][0]["nodes"][0]["nodes"][1]["focused"] = True
assert module.choice(nested, focus, "next") == 21

# Preserve Sway's own focus next/prev for tiling-only workspaces.
tiled_only = tree([leaf(11, "firefox", focused=True), leaf(12, "foot")], [])
assert module.choice(tiled_only, focus, "next") == "native"
assert module.choice(tiled_only, focus, "prev") == "native"
with patch.dict(os.environ, {"XDG_CURRENT_DESKTOP": "sway",
                             "SWAYSOCK": "/tmp/fake-sway"}), \
     patch.object(module, "ipc", side_effect=[
         tiled_only, focus, [{"success": True}]
     ]) as ipc, patch.object(module.sys, "argv", ["focus-cycle.py", "next"]):
    module.main()
    assert ipc.call_args.args == ("-t", "command", "focus next")

assert module.choice(tree([leaf(1, "only")], []), focus, "next") is None
assert module.choice(tree([], []), focus, "prev") is None
try:
    module.choice(tree([], []), [{"name": "2", "focused": False}], "next")
except ValueError:
    pass
else:
    raise AssertionError("No focused workspace should fail closed")

# Only the exact active workspace's numeric window ID may receive focus.
with patch.dict(os.environ, {"XDG_CURRENT_DESKTOP": "sway",
                             "SWAYSOCK": "/tmp/fake-sway"}), \
     patch.object(module, "ipc", side_effect=[
         nested, focus, [{"success": True}]
     ]) as ipc, patch.object(module.sys, "argv", ["focus-cycle.py", "next"]):
    module.main()
    assert ipc.call_args.args == ("-t", "command", "[con_id=21] focus")
print("PASS: Alt+Tab cycles across actual tiled and floating toplevels on focused workspace")
