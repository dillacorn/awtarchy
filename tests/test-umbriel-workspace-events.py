#!/usr/bin/env python3
"""Offline native Umbriel workspace IPC regression: independent outputs and live events."""
from __future__ import annotations

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
print("PASS: Umbriel workspace events, per-output active state and deduplication")
