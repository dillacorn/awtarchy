#!/usr/bin/env python3
"""Offline Umbriel resize policy and real AF_UNIX IPC round-trip contracts."""
from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import socket
import tempfile
import threading
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "compositors/umbriel/resize.py"
spec = importlib.util.spec_from_file_location("awtarchy_umbriel_resize", SCRIPT)
resize = importlib.util.module_from_spec(spec)
spec.loader.exec_module(resize)


def tile(name, x, y, w, h, *, workspace="w1", output="DP-1", floating=False):
    return dict(id=name, x=x, y=y, w=w, h=h, workspace=workspace,
                output=output, floating=floating, visible=True,
                minimized=False, tab_hidden=False, pinned=False, fullscreen=False)


left = tile("left", 0, 0, 497, 700)
right = tile("right", 503, 0, 497, 700)
pair = [left, right]
# A direction refers to the *physical divider*, not how the focused tile
# will change its fraction. Swapping focus must NOT reverse that movement.
assert resize.plan("left", left, pair, "dwindle") == (
    "window-modify-width-right", -0.03)
assert resize.plan("left", right, pair, "dwindle") == (
    "window-modify-width-left", 0.03)
assert resize.plan("right", left, pair, "dwindle") == (
    "window-modify-width-right", 0.03)
assert resize.plan("right", right, pair, "dwindle") == (
    "window-modify-width-left", -0.03)

top = tile("top", 0, 0, 1000, 300)
bottom = tile("bottom", 0, 306, 1000, 394)
vertical = [top, bottom]
assert resize.plan("up", top, vertical, "dwindle") == (
    "window-modify-height-down", -0.03)
assert resize.plan("up", bottom, vertical, "dwindle") == (
    "window-modify-height-up", 0.03)
assert resize.plan("down", top, vertical, "dwindle") == (
    "window-modify-height-down", 0.03)
assert resize.plan("down", bottom, vertical, "dwindle") == (
    "window-modify-height-up", -0.03)
assert resize.plan("h", right, pair, "dwindle") == resize.plan(
    "left", right, pair, "dwindle")
assert resize.plan("k", bottom, vertical, "dwindle") == resize.plan(
    "up", bottom, vertical, "dwindle")

middle = tile("middle", 503, 0, 497, 700)
other_right = tile("far-right", 1006, 0, 497, 700)
triple = [left, middle, other_right]
assert resize.plan("left", middle, triple, "dwindle") == (
    "window-modify-width-left", 0.03)
assert resize.plan("right", middle, triple, "dwindle") == (
    "window-modify-width-right", 0.03)

# Never resize across workspace/output boundaries or a floating window.
assert resize.plan("left", left, [left], "dwindle") is None
assert resize.plan("left", left, [left, dict(right, workspace="w2")],
                   "dwindle") is None
assert resize.plan("left", left, [left, dict(right, output="DP-3")],
                   "dwindle") is None
assert resize.plan("left", left, [left, dict(right, floating=True)],
                   "dwindle") is None
assert resize.plan("left", left, [left, dict(right, visible=False)],
                   "dwindle") is None
assert resize.plan("left", left, [left, dict(right, tab_hidden=True)],
                   "dwindle") is None
assert resize.plan("left", left, [left, dict(right, x=502, y=701)],
                   "dwindle") is None
assert resize.plan("left", left, [left, dict(right, x=560)],
                   "dwindle") is None
assert resize.plan("left", left, [left, dict(right, w=-100)],
                   "dwindle") is None
assert resize.plan("right", dict(left, fullscreen=True), pair,
                   "dwindle") is None

# The older native commands remain correct for floats and non-Dwindle layouts.
assert resize.plan("left", dict(right, floating=True), pair, "dwindle") == (
    "window-modify-primary-extent", -0.03)
assert resize.plan("right", dict(right, floating=True), pair, "dwindle") == (
    "window-modify-primary-extent", 0.03)
assert resize.plan("up", dict(bottom, floating=True), vertical, "dwindle") == (
    "window-modify-secondary-extent", -0.03)
assert resize.plan("right", right, pair, "scrolling") == (
    "window-modify-primary-extent", 0.03)
assert resize.plan("down", bottom, vertical, "master") == (
    "window-modify-secondary-extent", 0.03)
assert resize.plan("right", dict(right, w=0), pair, "dwindle") is None


def exercise_socket(*, change_focus=False, preview=False):
    with tempfile.TemporaryDirectory(prefix="umbriel-resize-test-") as tmp:
        path = Path(tmp) / "umbriel-test.sock"
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server.bind(str(path))
        server.listen(1)
        sent = []
        # Umbriel's upstream IPC closes each ordinary connection after a reply.
        replies = {
            "focused-window": [left, dict(right) if change_focus else left],
            "workspaces": [[{"id": "w1", "output": "DP-1",
                            "layout": "dwindle", "active": True}]],
            "windows": [pair],
            "action": [None],
        }
        expected_count = 3 if preview else (4 if change_focus else 5)

        def serve():
            for _ in range(expected_count):
                client, _ = server.accept()
                with client:
                    data = bytearray()
                    while b"\n" not in data:
                        data.extend(client.recv(65536))
                    command = json.loads(data.split(b"\n", 1)[0])
                    sent.append(command)
                    response = {"ok": replies[command["cmd"]].pop(0)}
                    client.sendall((json.dumps(response) + "\n").encode())

        worker = threading.Thread(target=serve, daemon=True)
        worker.start()
        environment = {
            "XDG_CURRENT_DESKTOP": "umbriel",
            "XDG_RUNTIME_DIR": tmp,
            "WAYLAND_DISPLAY": "wayland-1",
            "UMBRIEL_SOCKET": str(path),
        }
        with patch.dict(os.environ, environment), contextlib.redirect_stdout(io.StringIO()) as captured:
            assert resize.main(["--plan", "left"] if preview else ["left"]) == 0
        worker.join(timeout=3)
        assert not worker.is_alive(), "IPC requests were not completed"
        assert len(sent) == expected_count, sent
        if preview:
            result = json.loads(captured.getvalue())
            assert result["action"] == ["window-modify-width-right", -0.03]
            assert not any(q["cmd"] == "action" for q in sent)
        elif change_focus:
            assert not any(q["cmd"] == "action" for q in sent)
        else:
            assert sent[-1] == {"cmd": "action",
                                "action": "window-modify-width-right",
                                "delta": -0.03}
        server.close()


exercise_socket()
exercise_socket(change_focus=True)
exercise_socket(preview=True)
print("PASS: Umbriel physical divider resize, focus guard and IPC")
