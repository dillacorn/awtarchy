#!/usr/bin/env python3
"""Umbriel keyboard resize: move the shared Dwindle divider in key direction.

The native primary/secondary extent controls change the *focused fraction*,
which reverses the divider's screen direction when focus crosses a split.
Dwindle's edge actions move a specific boundary instead. Query real geometry
and use an internal edge only; never guess a screen-facing or foreign edge.
Other layouts and floating windows retain native extent behavior.
"""
from __future__ import annotations

import fcntl
import json
import os
from pathlib import Path
import socket
import stat
import sys

STEP = 0.03
MAX_GAP = 48
ALIASES = {"h": "left", "j": "down", "k": "up", "l": "right"}
AXES = {
    "left": ("x", "w", "y", "h", "right"),
    "right": ("x", "w", "y", "h", "left"),
    "up": ("y", "h", "x", "w", "down"),
    "down": ("y", "h", "x", "w", "up"),
}


def rectangle(entry):
    keys = ("x", "y", "w", "h")
    if not isinstance(entry, dict) or not all(
        type(entry.get(k)) is int for k in keys
    ):
        return None
    x, y, w, h = (entry[k] for k in keys)
    return (x, y, w, h) if w > 0 and h > 0 else None


def neighboring_edges(focused, windows):
    """Return only boundaries backed by nearby visible tiles on this workspace."""
    box = rectangle(focused)
    if box is None:
        return set()
    x, y, w, h = box
    found = set()
    for other in windows:
        if (not isinstance(other, dict)
                or other.get("id") == focused.get("id")
                or other.get("workspace") != focused.get("workspace")
                or other.get("output") != focused.get("output")
                or other.get("floating") is not False
                or other.get("visible") is not True
                or other.get("minimized") is True
                or other.get("tab_hidden") is True
                or other.get("pinned") is True
                or other.get("fullscreen") is True):
            continue
        peer = rectangle(other)
        if peer is None:
            continue
        ox, oy, ow, oh = peer
        vertical_overlap = max(0, min(y + h, oy + oh) - max(y, oy))
        horizontal_overlap = max(0, min(x + w, ox + ow) - max(x, ox))
        # Require a substantial shared edge, not an incidental corner.
        if vertical_overlap >= max(12, min(h, oh) // 4):
            if 0 <= x - (ox + ow) <= MAX_GAP:
                found.add("left")
            if 0 <= ox - (x + w) <= MAX_GAP:
                found.add("right")
        if horizontal_overlap >= max(12, min(w, ow) // 4):
            if 0 <= y - (oy + oh) <= MAX_GAP:
                found.add("up")
            if 0 <= oy - (y + h) <= MAX_GAP:
                found.add("down")
    return found


def plan(direction, focused, windows, layout):
    """Return (native action, signed fraction) or None when no safe split."""
    direction = ALIASES.get(direction, direction)
    if direction not in AXES or rectangle(focused) is None:
        return None
    if focused.get("fullscreen") is True:
        return None
    horizontal = direction in ("left", "right")
    if focused.get("floating") is True or layout != "dwindle":
        action = ("window-modify-primary-extent" if horizontal else
                  "window-modify-secondary-extent")
        return action, (-STEP if direction in ("left", "up") else STEP)
    found = neighboring_edges(focused, windows)
    opposite = AXES[direction][4]
    edge = direction if direction in found else opposite if opposite in found else None
    if edge is None:
        return None
    action = {
        "left": "window-modify-width-left",
        "right": "window-modify-width-right",
        "up": "window-modify-height-up",
        "down": "window-modify-height-down",
    }[edge]
    # Upstream: positive delta grows the named edge *outward*. On a
    # right/bottom edge that moves the divider right/down; on left/top
    # it moves the divider left/up. Invert on the opposite edge.
    positive = (edge == direction)
    return action, STEP if positive else -STEP


def socket_path():
    raw = os.environ.get("UMBRIEL_SOCKET")
    if not raw:
        runtime = os.environ.get("XDG_RUNTIME_DIR", "")
        display = os.environ.get("WAYLAND_DISPLAY", "")
        if not runtime or not display or "/" in display:
            raise ValueError("Umbriel runtime socket unavailable")
        raw = str(Path(runtime) / ("umbriel-" + display + ".sock"))
    path = Path(raw)
    if not path.is_absolute() or path.is_symlink():
        raise ValueError("Unsafe Umbriel IPC path")
    mode = path.stat()
    if mode.st_uid != os.geteuid() or not stat.S_ISSOCK(mode.st_mode):
        raise ValueError("Umbriel IPC socket is not owned by this user")
    return str(path)


def ipc(path, request):
    payload = (json.dumps(request, separators=(",", ":")) + "\n").encode()
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as conn:
        conn.settimeout(0.6)
        conn.connect(path)
        conn.sendall(payload)
        result = bytearray()
        while b"\n" not in result:
            chunk = conn.recv(65536)
            if not chunk:
                raise ValueError("Umbriel IPC returned no complete reply")
            result.extend(chunk)
            if len(result) > 1024 * 1024:
                raise ValueError("Umbriel IPC reply too large")
    response = json.loads(result.split(b"\n", 1)[0])
    if not isinstance(response, dict) or "err" in response or "ok" not in response:
        raise ValueError("Umbriel IPC rejected " + str(request.get("cmd")))
    return response["ok"]


def main(args):
    if len(args) not in (1, 2):
        raise ValueError("Usage: resize.py [--plan] left|right|up|down")
    preview = args[0] == "--plan" if len(args) == 2 else False
    direction = args[-1].lower()
    if direction not in (*AXES, *ALIASES):
        raise ValueError("Unknown resize direction")
    desktop = os.environ.get("XDG_CURRENT_DESKTOP", "").lower()
    if "umbriel" not in desktop.split(":"):
        raise ValueError("This helper only runs inside Umbriel")
    runtime = Path(os.environ.get("XDG_RUNTIME_DIR", ""))
    if not runtime.is_absolute() or not runtime.is_dir() or runtime.stat().st_uid != os.geteuid():
        raise ValueError("Unsafe Umbriel runtime directory")
    fd = os.open(runtime / "awtarchy-umbriel-resize.lock",
                 os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid() or info.st_nlink != 1:
            raise ValueError("Unsafe resize lock")
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return 0  # Skip repeats while a prior key press is still resolving.
        path = socket_path()
        focused = ipc(path, {"cmd": "focused-window"})
        if not isinstance(focused, dict) or not focused.get("id"):
            return 0
        workspaces = ipc(path, {"cmd": "workspaces"})
        if not isinstance(workspaces, list):
            raise ValueError("Invalid Umbriel workspace reply")
        workspace = next((w for w in workspaces if isinstance(w, dict)
                          and w.get("id") == focused.get("workspace")
                          and w.get("output") == focused.get("output")
                          and w.get("active") is True), None)
        if workspace is None:
            return 0
        windows = ipc(path, {"cmd": "windows"})
        if not isinstance(windows, list):
            raise ValueError("Invalid Umbriel window reply")
        result = plan(direction, focused, windows, workspace.get("layout"))
        if preview:
            print(json.dumps({"focused": focused["id"], "direction": direction,
                              "layout": workspace.get("layout"), "action": result}))
            return 0
        if result is None:
            return 0
        # Do not resize a different window if focus changed while IPC was read.
        current = ipc(path, {"cmd": "focused-window"})
        if not isinstance(current, dict) or current.get("id") != focused["id"]:
            return 0
        action, delta = result
        ipc(path, {"cmd": "action", "action": action, "delta": delta})
        return 0
    finally:
        os.close(fd)


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print("Umbriel resize: " + str(exc), file=sys.stderr)
        sys.exit(1)
