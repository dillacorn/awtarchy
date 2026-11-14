#!/usr/bin/env python3
"""Sway utility toggles must match the Hyprland floating-only contract."""
import importlib.util
from pathlib import Path
from unittest.mock import patch
import os

root = Path(__file__).resolve().parents[1]
source = root / "trials/sway/toggle-utility.py"
spec = importlib.util.spec_from_file_location("sway_toggle_utility", source)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

def window(identity, number, *, floating=True, tiled=False):
    value = {"type": "con", "id": number, "app_id": identity, "nodes": [],
             "floating_nodes": [], "floating": "user_on" if floating and not tiled else "auto_off"}
    return value

def ws(name, nodes=(), floating_nodes=()):
    return {"type": "workspace", "name": name, "nodes": list(nodes),
            "floating_nodes": list(floating_nodes)}

focused = [{"name": "1", "focused": True}, {"name": "2", "focused": False}]
floating_here = {"type": "root", "nodes": [ws("1", floating_nodes=[window("maccel", 12)]), ws("2")]}
assert module.classify(floating_here, focused, ("maccel",), False) == ((12,), False)
floating_remote = {"type": "root", "nodes": [ws("1"), ws("2", floating_nodes=[
    window("maccel", 20), window("maccel", 21)])]}
assert module.classify(floating_remote, focused, ("maccel",), False) == ((20, 21), True)
tiled_here = {"type": "root", "nodes": [ws("1", nodes=[window("maccel", 31, tiled=True)])]}
assert module.classify(tiled_here, focused, ("maccel",), False) == ((), True)
assert module.classify(tiled_here, focused, ("maccel",), True) == ((), False)
assert module.classify(tiled_here, focused, ("Wiremix",), False) == ((), True)
hidden_scratchpad = {"type": "root", "nodes": [ws("1"), ws("__i3_scratch", floating_nodes=[
    window("maccel", 999)])]}
assert module.classify(hidden_scratchpad, focused, ("maccel",), False) == ((), True)
title_only = {"type": "root", "nodes": [ws("1", floating_nodes=[
    {"id": 100, "type": "con", "app_id": "Firefox", "name": "maccel"}])]}
assert module.classify(title_only, focused, ("maccel",), False) == ((), True)

with patch.dict(os.environ, {"XDG_CURRENT_DESKTOP": "sway", "SWAYSOCK": "/test/sway.sock"}):
    with patch.object(module, "ipc", side_effect=[floating_here, focused, [{"success": True}]]) as ipc, \
         patch.object(module.subprocess, "Popen") as launch:
        module.toggle("maccel")
        launch.assert_not_called()
        assert ipc.call_args_list[-1].args == ("-t", "command", "[con_id=12 floating] kill")
    with patch.object(module, "ipc", side_effect=[floating_remote, focused,
                                                    [{"success": True}], [{"success": True}]]), \
         patch.object(module.subprocess, "Popen") as launch:
        module.toggle("maccel")
        assert launch.call_count == 1
        assert launch.call_args.args[0] == module.UTILITIES["maccel"][1]
    with patch.object(module, "ipc", side_effect=[tiled_here, focused]), \
         patch.object(module.subprocess, "Popen") as launch:
        module.toggle("default-apps")
        launch.assert_called_once()  # no matching default-apps tile
    default_app_tiled = {"type": "root", "nodes": [ws("1", nodes=[
        window("awtarchy-default-apps", 71, tiled=True)])]}
    with patch.object(module, "ipc", side_effect=[default_app_tiled, focused]), \
         patch.object(module.subprocess, "Popen") as launch:
        module.toggle("default-apps")
        launch.assert_not_called()
try:
    module.classify(floating_here, [{"name": "1", "focused": False}], ("maccel",), False)
except ValueError:
    pass
else:
    raise AssertionError("Unknown focus must fail closed")

print("PASS: Sway utility toggles close local floats, relocate remote floats, preserve tiled apps")
