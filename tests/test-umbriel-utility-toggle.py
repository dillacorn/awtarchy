#!/usr/bin/env python3
"""Native Umbriel utility behavior: close exact floats, preserve tiled apps."""
import importlib.util
import os
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
source = ROOT / "compositors/umbriel/toggle-utility.py"
spec = importlib.util.spec_from_file_location("awtarchy_umbriel_toggle", source)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

focused = [{"id": "DP-1:4", "output": "DP-1", "focused": True},
           {"id": "DP-3:4", "output": "DP-3", "focused": False}]

def window(identifier, workspace="DP-1:4", output="DP-1",
           identity="btop", title="btop", floating=True):
    return {"id": identifier, "workspace": workspace, "output": output,
            "app_id": identity, "title": title, "floating": floating}

local = [window("a")]
remote = [window("b", workspace="DP-3:4", output="DP-3")]
generic_foot = [window("c", identity="foot")]
assert mod.classify(local, focused, ("btop",), False) == (("a",), False)
assert mod.classify(remote, focused, ("btop",), False) == (("b",), True)
assert mod.classify(generic_foot, focused, ("btop",), False) == (("c",), False)
assert mod.classify([window("d", identity="firefox")],
                    focused, ("btop",), False) == ((), True)
tiled = [window("e", floating=False)]
assert mod.classify(tiled, focused, ("btop",), False) == ((), True)
assert mod.classify(tiled, focused, ("btop",), True) == ((), False)

assert mod.UTILITIES["btop"][1][0:5] == (
    "foot", "--app-id", "btop", "--title", "btop")
assert mod.UTILITIES["wiremix"][1][-5:] == (
    "wiremix", "-p", "auto", "-f", "30")

with patch.dict(os.environ, {"XDG_CURRENT_DESKTOP": "Umbriel",
                              "WAYLAND_DISPLAY": "wayland-1"}):
    with patch.object(mod, "query", side_effect=[local, focused]), \
         patch.object(mod.subprocess, "run") as ipc, \
         patch.object(mod.subprocess, "Popen") as process:
        mod.toggle("btop")
        ipc.assert_called_once()
        assert ipc.call_args.args[0] == ["umbriel", "msg", "window-close", "a"]
        process.assert_not_called()

    with patch.object(mod, "query", side_effect=[remote, focused]), \
         patch.object(mod.subprocess, "run") as ipc, \
         patch.object(mod.subprocess, "Popen") as process:
        mod.toggle("btop")
        ipc.assert_called_once()
        process.assert_called_once()
        assert process.call_args.args[0] == mod.UTILITIES["btop"][1]

    with patch.object(mod, "query", side_effect=[tiled, focused]), \
         patch.object(mod.subprocess, "run") as ipc, \
         patch.object(mod.subprocess, "Popen") as process:
        mod.toggle("default-apps")
        ipc.assert_not_called()
        process.assert_called_once()

print("PASS: Umbriel exact utility toggles, Foot title fallback and tiled preservation")
