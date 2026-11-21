#!/usr/bin/env python3
"""Native Umbriel utility behavior: close exact floats, preserve tiled apps."""
import importlib.util
import os
from pathlib import Path
import subprocess
from types import SimpleNamespace
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
assert mod.UTILITIES["btop"][2] is True
assert mod.UTILITIES["wiremix"][2] is True
assert mod.UTILITIES["displays"] == (
    ("wdisplays", "network.cycles.wdisplays"), ("wdisplays",), True)
assert mod.classify(tiled, focused, ("btop",), True) == ((), False)
assert mod.matches_identity(window("wd", identity="network.cycles.wdisplays"),
                            {"wdisplays", "network.cycles.wdisplays"})
wallpicker = mod.UTILITIES["wallpicker"][1]
assert wallpicker[:4] == ("foot", "--app-id", "wallpicker", "bash")
assert wallpicker[-2:] == (str(mod.CONFIG / "umbriel/awtarchy/awtwall.sh"), "--resume")

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
         patch.object(mod.subprocess, "Popen") as process, \
         patch.object(mod, "ensure_new_floating") as verify:
        mod.toggle("btop")
        ipc.assert_called_once()
        process.assert_called_once()
        verify.assert_called_once()
        assert process.call_args.args[0] == mod.UTILITIES["btop"][1]

    with patch.object(mod, "query", side_effect=[tiled, focused]), \
         patch.object(mod.subprocess, "run") as ipc, \
         patch.object(mod.subprocess, "Popen") as process:
        mod.toggle("default-apps")
        ipc.assert_not_called()
        process.assert_called_once()

# A new utility window is converted by its exact fresh ID; existing tiled
# windows are excluded and never passed to the compositor floating action.
with patch.object(mod, "query", side_effect=[
         [window("created", floating=False)],
         [window("created", floating=True)]]), \
     patch.object(mod.subprocess, "run") as ipc, \
     patch.object(mod.time, "sleep") as delay:
    # Upstream Umbriel prints *nothing* when an action succeeds.
    ipc.return_value = SimpleNamespace(stdout="", returncode=0)
    mod.ensure_new_floating([], ("btop",))
    ipc.assert_called_once()
    assert ipc.call_args.args[0] == [
        "umbriel", "msg", "window-toggle-floating", "created"]
    assert ipc.call_args.kwargs["check"] is True
    assert delay.call_count == 1

# A new window that already floats needs no toggle.
with patch.object(mod, "query", return_value=[window("new", floating=True)]), \
     patch.object(mod.subprocess, "run") as ipc, \
     patch.object(mod.time, "sleep") as delay:
    mod.ensure_new_floating([], ("btop",))
    ipc.assert_not_called()
    delay.assert_not_called()

# Do not change an existing tiled window even when its app ID matches.
with patch.object(mod, "query", return_value=[window("old", floating=False)]), \
     patch.object(mod.subprocess, "run") as ipc, \
     patch.object(mod.time, "sleep") as delay:
    try:
        mod.ensure_new_floating([window("old", floating=False)], ("btop",))
    except RuntimeError:
        pass
    else:
        raise AssertionError("Unexpected conversion of an existing tiled window")
    ipc.assert_not_called()
    assert delay.call_count == 60

# An actual action failure is never reported as a successful float.
def rejected_action(argv, **kwargs):
    raise subprocess.CalledProcessError(1, argv, stderr="no such window")

with patch.object(mod, "query", return_value=[window("new", floating=False)]), \
     patch.object(mod.subprocess, "run", side_effect=rejected_action) as ipc, \
     patch.object(mod.time, "sleep") as delay:
    try:
        mod.ensure_new_floating([], ("btop",))
    except subprocess.CalledProcessError:
        pass
    else:
        raise AssertionError("Rejected Umbriel action reported as success")
    ipc.assert_called_once()
    delay.assert_not_called()

print("PASS: Umbriel exact utility toggles, newly floated utility verification, and tiled preservation")
