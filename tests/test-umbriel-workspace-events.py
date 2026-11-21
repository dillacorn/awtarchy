#!/usr/bin/env python3
"""Offline native Umbriel workspace IPC regression: independent outputs and live events."""
from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import select
import socket
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "compositors/umbriel/workspace-events.py"


def receive_line(process: subprocess.Popen, timeout: float = 4.0):
    readable, _, _ = select.select([process.stdout], [], [], timeout)
    if not readable:
        raise AssertionError("Umbriel event subscription produced no state within timeout")
    line = process.stdout.readline()
    if not line:
        raise AssertionError("Umbriel subscription exited: " + str(process.poll()))
    return json.loads(line)


def send(sock, family, data):
    sock.sendall((json.dumps({"event": family, "data": data}) + "\n").encode())


def state_key(entries):
    return {(w["monitor"], w["id"]): w for w in entries}


with tempfile.TemporaryDirectory(prefix="umbriel-workspace-events-") as temp:
    path = Path(temp) / "ipc.sock"
    with socket.socket(socket.AF_UNIX) as server:
        server.bind(str(path))
        server.listen(1)
        server.settimeout(5)
        env = dict(os.environ,
                   XDG_CURRENT_DESKTOP="Umbriel",
                   XDG_RUNTIME_DIR=temp,
                   WAYLAND_DISPLAY="wayland-test",
                   UMBRIEL_SOCKET=str(path))
        process = subprocess.Popen(
            [sys.executable, str(SOURCE)], env=env,
            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, bufsize=1)
        try:
            with server.accept()[0] as peer:
                peer.settimeout(4)
                subscription = peer.recv(2048).decode()
                assert json.loads(subscription) == {
                    "cmd": "subscribe", "events": ["workspaces", "windows"]}

                original = [
                    {"id": "ws-dp1-1", "name": "1", "index": 1,
                     "output": "DP-1", "active": True, "focused": True},
                    {"id": "ws-dp1-3", "name": "3", "index": 3,
                     "output": "DP-1", "active": False, "focused": False},
                    {"id": "ws-dp3-1", "name": "1", "index": 1,
                     "output": "DP-3", "active": True, "focused": False},
                    {"id": "ws-dp3-3", "name": "3", "index": 3,
                     "output": "DP-3", "active": False, "focused": False},
                ]
                send(peer, "workspaces", original)
                send(peer, "windows", [])
                first = state_key(receive_line(process))
                assert first[("DP-1", 1)]["active"] is True
                assert first[("DP-3", 1)]["active"] is True
                assert first[("DP-3", 1)]["focused"] is False
                assert first[("DP-1", 3)]["active"] is False

                changed = [dict(row) for row in original]
                changed[0]["active"] = False
                changed[0]["focused"] = False
                changed[1]["active"] = True
                changed[1]["focused"] = True
                send(peer, "workspaces", changed)
                second = state_key(receive_line(process))
                assert second[("DP-1", 1)]["active"] is False
                assert second[("DP-1", 3)]["active"] is True
                assert second[("DP-1", 3)]["focused"] is True
                assert second[("DP-3", 1)]["active"] is True
                # Selecting Alt+3 with pointer preference on the other monitor
                # changes only DP-3's active workspace, not DP-1's own #3.
                third_workspace = [dict(row) for row in changed]
                for row in third_workspace:
                    if row["output"] == "DP-3":
                        row["active"] = row["index"] == 3
                        row["focused"] = row["index"] == 3
                    else:
                        row["focused"] = False
                send(peer, "workspaces", third_workspace)
                third = state_key(receive_line(process))
                assert third[("DP-1", 3)]["active"] is True
                assert third[("DP-1", 3)]["focused"] is False
                assert third[("DP-3", 1)]["active"] is False
                assert third[("DP-3", 3)]["active"] is True
                assert third[("DP-3", 3)]["focused"] is True
                # Redundant socket notifications must not rebuild QML models.
                send(peer, "windows", [])
                available, _, _ = select.select([process.stdout], [], [], 0.20)
                assert not available, "Unchanged window snapshot emitted a duplicate state"
        finally:
            process.terminate()
            try:
                process.communicate(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
                process.communicate(timeout=3)
# Native named workspaces represent one global identity across all outputs.
# A transferred workspace can change output AND positional index, including
# an index above 10, without changing its globally numbered name.
spec = importlib.util.spec_from_file_location(
    "awtarchy_umbriel_native_workspaces",
    ROOT / "compositors/umbriel/workspace-state.py")
adapter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(adapter)

named = [
    {"id": f"DP-1:stable-{num}", "name": str(num), "named": True,
     "index": num, "output": "DP-1",
     "active": num == 1, "focused": num == 1}
    for num in range(1, 11)
]
# Umbriel's secondary dynamic output still has a LOCAL position 1. It is not
# another global workspace 1 and must not render as that number in the bar.
anonymous_secondary = {"id": "DP-3:local-1", "name": "1", "named": False,
                       "index": 1, "output": "DP-3", "active": True, "focused": False}
original = adapter.collect(named + [anonymous_secondary], [])
assert len(original) == 10
assert all(row["monitor"] == "DP-1" for row in original)
assert {(row["id"], row["name"]) for row in original} == {
    (i, str(i)) for i in range(1, 11)}
after_move = [dict(row) for row in named]
after_move[0]["focused"] = False
after_move[1].update({"output": "DP-3", "index": 4, "active": True,
                      "focused": True})
moved = adapter.collect(after_move + [anonymous_secondary], [])
by_number = {row["id"]: row for row in moved}
assert len(moved) == len(by_number) == 10
assert by_number[1]["monitor"] == "DP-1"
assert by_number[2]["monitor"] == "DP-3"
assert by_number[2]["name"] == "2"
assert by_number[2]["focused"] is True
assert by_number[2]["id"] == 2  # NOT destination output-local index 4
after_move[1].update({"output": "DP-1", "index": 11,
                      "active": True, "focused": True})
moved_back = adapter.collect(after_move + [anonymous_secondary], [])
assert next(w for w in moved_back if w["id"] == 2)["monitor"] == "DP-1"
assert next(w for w in moved_back if w["id"] == 2)["name"] == "2"
print("PASS: Umbriel workspace events, per-output active state and global named identity")
