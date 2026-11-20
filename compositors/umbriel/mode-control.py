#!/usr/bin/env python3
"""Native Umbriel noalt/mouse/vm submaps with verified IPC and bar state."""
from __future__ import annotations

import json
import os
import shutil
from pathlib import Path
import subprocess
import sys
import tempfile

MODES = {"default", "noalt", "mouse", "vm"}


def active() -> str:
    result = subprocess.run(["umbriel", "submap", "--json"], check=True,
                            capture_output=True, text=True, timeout=5)
    value = json.loads(result.stdout)
    if isinstance(value, dict):
        if "err" in value:
            raise ValueError(str(value["err"]))
        value = value.get("ok")
    mode = "default" if value is None else value
    if not isinstance(mode, str) or mode not in MODES:
        raise ValueError("Unexpected native Umbriel submap: " + repr(mode))
    return mode


def state_file() -> Path:
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    if not runtime:
        raise ValueError("XDG_RUNTIME_DIR unavailable")
    directory = Path(runtime)
    st = directory.stat()
    if (not directory.is_dir() or directory.is_symlink()
            or st.st_uid != os.getuid() or st.st_mode & 0o077):
        raise ValueError("Unsafe XDG_RUNTIME_DIR")
    return directory / "awtarchy-umbriel-submap"


def publish(mode: str):
    target = state_file()
    if (target.is_symlink() or target.exists()
            and (not target.is_file() or target.stat().st_uid != os.getuid())):
        raise ValueError("Unsafe existing submap state")
    fd, path = tempfile.mkstemp(prefix=".awtarchy-submap-", dir=target.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as out:
            os.fchmod(out.fileno(), 0o600)
            out.write(mode if mode != "default" else "")
            out.flush()
            os.fsync(out.fileno())
        os.replace(path, target)
    finally:
        if os.path.lexists(path):
            os.unlink(path)


def command(action: str, name: str | None = None):
    if (os.environ.get("XDG_CURRENT_DESKTOP", "").casefold() != "umbriel"
            or not os.environ.get("WAYLAND_DISPLAY")):
        raise ValueError("Active Umbriel session required")
    current = active()
    if action in ("status", "sync"):
        publish(current)
        print(current)
        return
    if action == "toggle" and name not in MODES - {"default"}:
        raise ValueError("Unknown target submap")
    if action not in ("toggle", "reset"):
        raise ValueError("Usage: mode-control.py status|sync|reset|toggle noalt|mouse|vm")
    target = name if action == "toggle" and current != name else "default"
    if current != target:
        if current != "default":
            subprocess.run(["umbriel", "msg", "submap", "reset"],
                           check=True, capture_output=True, text=True, timeout=5)
            if active() != "default":
                raise ValueError("Umbriel did not clear the previous submap")
        if target != "default":
            subprocess.run(["umbriel", "msg", "submap", target],
                           check=True, capture_output=True, text=True, timeout=5)
    actual = active()
    publish(actual)
    if actual != target:
        raise ValueError("Umbriel rejected submap: expected " + target + ", got " + actual)
    if actual != current and shutil.which("notify-send"):
        subprocess.Popen(["notify-send", "-a", "Awtarchy", "-t", "900",
                          "Umbriel input mode: " + actual], stdin=subprocess.DEVNULL,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True)


if __name__ == "__main__":
    try:
        argv = sys.argv[1:]
        if argv in (["status"], ["sync"], ["reset"]):
            command(argv[0])
        elif len(argv) == 2 and argv[0] == "toggle":
            command(argv[0], argv[1])
        else:
            raise ValueError("Usage: mode-control.py status|sync|reset|toggle noalt|mouse|vm")
    except (ValueError, OSError, subprocess.CalledProcessError,
            subprocess.TimeoutExpired, json.JSONDecodeError) as exc:
        print("Awtarchy Umbriel submap: " + str(exc), file=sys.stderr)
        sys.exit(1)
