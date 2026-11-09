#!/usr/bin/env python3
"""Position Awtarchy's Mango floating shell windows using native mmsg IPC.

The Hyprland positioning backend is never invoked. Target the exact Mango
client ID after verifying its title and Quickshell process identity.
"""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time

WINDOWS = {
    "launcher": ("Awtarchy Application Search", "launcher_sizes", 420, 582, 420, 360, "launcher"),
    "clipboard": ("Awtarchy Clipboard History", "clipboard_views", 880, 760, 480, 360, "centered"),
    "notifications": ("Awtarchy Notification Center", "notification_views", 520, 760, 360, 360, "notification"),
    "quick-settings": ("Awtarchy Quick Settings", "quick_settings_views", 860, 850, 520, 460, "centered"),
    "network": ("Awtarchy Network", "network_views", 520, 600, 360, 360, "corner"),
    "bluetooth": ("Awtarchy Bluetooth", "bluetooth_views", 500, 600, 360, 360, "corner"),
    "battery": ("Awtarchy Battery", "battery_views", 560, 560, 420, 360, "corner"),
}
EDGES = {"center", "top", "bottom", "left", "right", "clamp",
         "top-center", "bottom-center", "left-center", "right-center"}
CONFIG_HOME = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config")))
CACHE_HOME = Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache")))
RUNTIME_HOME = Path(os.environ.get("XDG_RUNTIME_DIR", str(CACHE_HOME / "awtarchy-runtime")))
STATE = CACHE_HOME / "awtarchy/quickshell-state.json"
PREPARED = RUNTIME_HOME / "awtarchy-quickshell/flyout-targets"


def cmd(*args):
    result = subprocess.run(("mmsg", *args), capture_output=True, text=True,
                            check=True, timeout=2)
    raw = result.stdout.strip()
    try:
        obj = json.loads(raw)
    except ValueError:
        return raw
    if isinstance(obj, dict) and obj.get("error"):
        raise RuntimeError("Mango IPC rejected action: " + str(obj["error"]))
    return obj


def query(kind):
    result = cmd("get", kind)
    if not isinstance(result, dict):
        raise RuntimeError("Invalid Mango IPC response")
    return result


def positive_int(value, default=0):
    try:
        num = int(value)
        if num >= 0:
            return num
    except (ValueError, TypeError, OverflowError):
        pass
    return default


def state():
    try:
        obj = json.loads(STATE.read_text(encoding="utf-8"))
        return obj if isinstance(obj, dict) else {}
    except (OSError, ValueError):
        return {}


def prepared_target(surface):
    path = PREPARED / surface
    try:
        if path.is_symlink():
            return None
        monitor, placement = path.read_text(encoding="utf-8").strip().split("\t", 1)
        if re.fullmatch(r"[A-Za-z0-9._:-]+", monitor) and placement in EDGES:
            return monitor, placement
    except (OSError, ValueError):
        pass
    return None


def prepare(args):
    if len(args) != 9:
        raise ValueError("prepare requires surface monitor placement width height bar anchor screen_w screen_h")
    surface, monitor, placement, width, height, bar, anchor, sw, sh = args
    if surface not in WINDOWS or not re.fullmatch(r"[A-Za-z0-9._:-]+", monitor):
        raise ValueError("unsupported surface or monitor")
    if placement not in EDGES or placement == "clamp":
        raise ValueError("unsupported preparation placement")
    for value in (width, height, bar, sw, sh):
        if not value.isdecimal() or (int(value) <= 0 and value in (width, height, sw, sh)):
            raise ValueError("invalid preparation dimension")
    int(anchor)
    PREPARED.mkdir(mode=0o700, parents=True, exist_ok=True)
    if PREPARED.is_symlink():
        raise ValueError("unsafe prepared target path")
    target = PREPARED / surface
    if target.is_symlink():
        raise ValueError("unsafe prepared target file")
    fd, path = tempfile.mkstemp(prefix=f"{surface}.", dir=PREPARED, text=True)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(monitor + "\t" + placement + "\n")
        os.replace(path, target)
    finally:
        if os.path.lexists(path):
            os.unlink(path)


def quickshell_pid(pid):
    if not isinstance(pid, int) or pid <= 0:
        return False
    try:
        exe = os.readlink(f"/proc/{pid}/exe").removesuffix(" (deleted)")
        return os.path.basename(exe) == "quickshell"
    except OSError:
        return False


def find_client(title, monitor):
    for _ in range(60):
        clients = query("all-clients").get("clients", [])
        if not isinstance(clients, list):
            raise RuntimeError("Malformed Mango clients")
        candidates = [c for c in clients
                      if c.get("title") == title and quickshell_pid(c.get("pid"))
                      and isinstance(c.get("id"), int) and c.get("id") > 0]
        for c in reversed(candidates):
            if c.get("monitor") == monitor:
                return c
        if candidates:
            return candidates[-1]
        time.sleep(0.025)
    raise RuntimeError("Expected Quickshell window not mapped: " + title)


def find_monitor(name):
    monitors = query("all-monitors").get("monitors", [])
    for mon in monitors:
        if mon.get("name") == name:
            try:
                values = [int(mon.get(k, 0)) for k in ("x", "y", "width", "height")]
            except (TypeError, ValueError):
                raise RuntimeError("Mango monitor geometry is malformed") from None
            if values[2] <= 0 or values[3] <= 0:
                raise RuntimeError("Monitor has invalid geometry")
            return tuple(values)
    raise RuntimeError("Mango output not found: " + name)


def saved_dims(surface, monitor, mw, mh, obj, clamp):
    _, key, default_w, default_h, min_w, min_h, _ = WINDOWS[surface]
    factor = min(mw / 1920, mh / 1080)
    width = round(default_w * factor)
    height = round(default_h * factor)
    view = obj.get(key, {})
    view = view.get(monitor, {}) if isinstance(view, dict) else {}
    if isinstance(view, dict):
        saved = view.get("saved") is True and positive_int(view.get("save_version")) >= 2
        if surface == "launcher":
            saved = saved or view.get("locked") is True
        if saved:
            sx = positive_int(view.get("width"))
            sy = positive_int(view.get("height"))
            if 1 <= sx <= 16384 and 1 <= sy <= 16384:
                width, height = sx, sy
    return max(min(min_w, mw-20), min(mw-20, width)), max(min(min_h, mh-20), min(mh-20, height))


def launcher_edge_from_state(monitor, placement, obj):
    """Ignore a stale edge after the visible per-monitor bar moved."""
    if placement == "center":
        return placement
    monitors = obj.get("monitors", {})
    bar = monitors.get(monitor, {}) if isinstance(monitors, dict) else {}
    edge = bar.get("position") if isinstance(bar, dict) else None
    if edge not in ("top", "bottom", "left", "right"):
        return placement
    # Preserve whether the caller asked for the Apps-button corner or the
    # keyboard shortcut's centered-along-edge launcher.
    return edge + ("-center" if placement.endswith("-center") else "")


def reposition(surface, monitor, placement, action, requested_w=None, requested_h=None, anchor="-1"):
    if surface not in WINDOWS or placement not in EDGES:
        raise ValueError("unknown surface or placement")
    if action not in {"spawn", "resize", "resize-compact", "clamp"}:
        raise ValueError("unknown positioning action")
    obj = state()
    if action == "spawn":
        override = prepared_target(surface)
        # Preparation can be left behind after a bar move or a different
        # monitor's launcher open. Never let that stale value override a
        # newer explicit target. Other flyouts retain their matching prepare.
        if override and override[0] == monitor and override[1] == placement:
            monitor, placement = override
        if surface == "launcher":
            placement = launcher_edge_from_state(monitor, placement, obj)

    title, _, _, _, min_w, min_h, layout = WINDOWS[surface]
    mx, my, mw, mh = find_monitor(monitor)
    client = find_client(title, monitor)
    cid = client["id"]
    win_w = positive_int(client.get("width"), 1)
    win_h = positive_int(client.get("height"), 1)
    if action == "spawn":
        win_w, win_h = saved_dims(surface, monitor, mw, mh, obj, action)
    elif action in {"resize", "resize-compact"}:
        win_w = positive_int(requested_w, -1)
        win_h = positive_int(requested_h, -1)
        if win_w < 1 or win_h < 1:
            raise ValueError("resize requires positive integer dimensions")
    if action != "clamp":
        if action == "resize-compact" and surface == "quick-settings":
            min_h = 180
        win_w = max(min(min_w, mw-20), min(mw-20, win_w))
        win_h = max(min(min_h, mh-20), min(mh-20, win_h))

    monitors_state = obj.get("monitors", {})
    if not isinstance(monitors_state, dict):
        monitors_state = {}
    bar = monitors_state.get(monitor, {})
    bs = positive_int(bar.get("bar_size")) if isinstance(bar, dict) else 0
    horizontal = bs if 20 <= bs <= 80 else 28
    vertical = bs if 20 <= bs <= 80 else 36
    cx = mx + (mw - win_w) // 2
    cy = my + (mh - win_h) // 2
    x, y = cx, cy
    if action == "clamp":
        x = int(client.get("x", mx))
        y = int(client.get("y", my))
    elif layout == "launcher":
        if placement in ("top", "top-center"):
            x, y = (mx if placement == "top" else cx), my + horizontal
        elif placement in ("bottom", "bottom-center"):
            x, y = (mx if placement == "bottom" else cx), my + mh - horizontal - win_h
        elif placement in ("left", "left-center"):
            x, y = mx + vertical, (my if placement == "left" else cy)
        elif placement in ("right", "right-center"):
            x, y = mx + mw - vertical - win_w, (my if placement == "right" else cy)
    elif placement != "center":
        if layout == "corner":
            if placement in ("top", "bottom"):
                x = mx + mw - win_w - 8
            else:
                y = my + mh - win_h - 8
        elif layout == "notification":
            coordinate = int(float(anchor)) if re.fullmatch(r"-?\d+(?:\.\d+)?", anchor) else -1
            if placement in ("top", "bottom"):
                x = mx + ((coordinate if coordinate >= 0 else mw-40) - win_w)
            else:
                y = my + ((coordinate if coordinate >= 0 else mh-40) - win_h)
        if placement == "top":
            y = my + horizontal
        elif placement == "bottom":
            y = my + mh - horizontal - win_h
        elif placement == "left":
            x = mx + vertical
        elif placement == "right":
            x = mx + mw - vertical - win_w
    x = max(mx, min(mx + mw - win_w, x))
    y = max(my, min(my + mh - win_h, y))

    # Do not accidentally move a different application bearing the same title.
    if client.get("monitor") != monitor:
        cmd("dispatch", f"tagmon,{monitor},1", f"client,{cid}")
    if not client.get("is_floating"):
        cmd("dispatch", "togglefloating", f"client,{cid}")
    if action != "clamp":
        cmd("dispatch", f"resizewin,{win_w},{win_h}", f"client,{cid}")
    cmd("dispatch", f"movewin,{x},{y}", f"client,{cid}")


def main(argv):
    if not argv:
        raise ValueError("command missing: launcher|flyout|prepare")
    mode, *rest = argv
    if mode == "prepare":
        prepare(rest)
    elif mode == "launcher" and len(rest) == 2:
        monitor, placement = rest
        reposition("launcher", monitor, placement, "clamp" if placement == "clamp" else "spawn")
    elif mode == "flyout" and 3 <= len(rest) <= 7:
        surface, monitor, placement, *tail = rest
        action = tail[0] if len(tail) >= 1 else "spawn"
        width = tail[1] if len(tail) >= 2 else None
        height = tail[2] if len(tail) >= 3 else None
        anchor = tail[3] if len(tail) >= 4 else "-1"
        reposition(surface, monitor, placement, action, width, height, anchor)
    else:
        raise ValueError("invalid command arguments")


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError,
            subprocess.TimeoutExpired) as error:
        print(f"mango-position: {error}", file=sys.stderr)
        sys.exit(1)
