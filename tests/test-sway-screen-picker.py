#!/usr/bin/env python3
"""Regression tests for the Sway portal chooser's exact-source protocol."""
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
TRIAL = ROOT / "trials/sway"
module_path = TRIAL / "portal-chooser.py"
spec = importlib.util.spec_from_file_location("awtarchy_portal", module_path)
chooser = importlib.util.module_from_spec(spec)
spec.loader.exec_module(chooser)

config = (TRIAL / "screencast-chooser.conf").read_text()
assert "chooser_type=dmenu" in config
assert "portal-chooser.py" in config
assert "chooser_cmd=fuzzel" not in config
assert "portal-chooser.py" in (TRIAL / "setup.sh").read_text()
assert '".config/sway/awtarchy-trial/portal-chooser.py"' in (
    TRIAL / "sync.py").read_text()
assert "ScreenSharePicker.qml" in (TRIAL / "render-quickshell.py").read_text()
qml = (TRIAL / "ScreenSharePicker.qml").read_text()
for text in ('WlrLayershell.layer: WlrLayer.Overlay',
             'WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive',
             'root.finish(-1)', 'root.finish(root.selectedIndex)',
             'Theme.popupBackground', 'requestFile.reload()'):
    assert text in qml, text

with tempfile.TemporaryDirectory(prefix="awtarchy-screen-picker-") as temporary:
    runtime = Path(temporary) / "runtime"
    runtime.mkdir(mode=0o700)
    env = dict(os.environ, XDG_RUNTIME_DIR=str(runtime),
               XDG_CURRENT_DESKTOP="sway", WAYLAND_DISPLAY="wayland-1")
    options = ["Monitor: DP-1", "Monitor: DP-3", "Window: 56 - OBS"]
    with patch.dict(os.environ, env):
        def selected(argv, **kwargs):
            assert argv[:7] == [
                "qs", "-c", "awtarchy-sway", "ipc", "call", "screenshare", "open"]
            _, data = chooser.validate_request(argv[7])
            assert data == options
            chooser.respond(argv[7], "1")
            return subprocess.CompletedProcess(argv, 0, stdout="true\n", stderr="")
        with patch.object(chooser.subprocess, "run", side_effect=selected), \
             patch("sys.stdout", new_callable=io.StringIO) as output:
            assert chooser.choose(io.StringIO("\n".join(options) + "\n")) == 0
            assert output.getvalue() == "Monitor: DP-3\n"
        assert not list(runtime.iterdir())

        def cancelled(argv, **kwargs):
            chooser.respond(argv[7], "-1")
            return subprocess.CompletedProcess(argv, 0, stdout="true\n", stderr="")
        with patch.object(chooser.subprocess, "run", side_effect=cancelled), \
             patch("sys.stdout", new_callable=io.StringIO) as output:
            assert chooser.choose(io.StringIO("\n".join(options))) == 0
            assert output.getvalue() == ""

        def failed(argv, **kwargs):
            return subprocess.CompletedProcess(argv, 1, stdout="", stderr="not ready")
        with patch.object(chooser.subprocess, "run", side_effect=failed), \
             patch("sys.stdout", new_callable=io.StringIO) as output:
            try:
                chooser.choose(io.StringIO("\n".join(options)))
            except ValueError:
                pass
            else:
                raise AssertionError("Missing Quickshell accepted a screen share")
            assert output.getvalue() == ""

        stage = Path(tempfile.mkdtemp(prefix=chooser.PREFIX, dir=runtime))
        request = stage / "request.json"
        request.write_text(json.dumps({"choices": options}))
        assert chooser.respond(request, "0") == 0
        try:
            chooser.respond(request, "1")
        except FileExistsError:
            pass
        else:
            raise AssertionError("Second response overwrote first selection")
        assert json.loads((stage / "reply.json").read_text()) == {"index": 0}
        try:
            chooser.respond(request, "9")
        except ValueError:
            pass
        else:
            raise AssertionError("Out-of-range index accepted")
        foreign = Path(temporary) / "foreign/request.json"
        foreign.parent.mkdir()
        foreign.write_text(json.dumps({"choices": options}))
        try:
            chooser.respond(foreign, "0")
        except ValueError:
            pass
        else:
            raise AssertionError("Foreign request path accepted")
        with patch("sys.stdout", new_callable=io.StringIO) as output:
            try:
                chooser.choose(io.StringIO("Monitor: DP-1\n" * 100))
            except ValueError:
                pass
            else:
                raise AssertionError("Unbounded list accepted")
            assert output.getvalue() == ""

print("PASS: Quickshell chooser selection, cancel, failure, bounds and path validation")
