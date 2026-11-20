#!/usr/bin/env python3
"""Umbriel-native global floating preference; only new windows are affected."""
from __future__ import annotations

import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import tomllib

OFF = b"# Umbriel global floating: disabled. Managed by Awtarchy.\n"
ON = (b"# Umbriel global floating: enabled. Managed by Awtarchy.\n"
      b"[[window_rule]]\nmatch.app_id = \"^.*$\"\ndefault_floating = true\n")


def files():
    config = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    if not runtime:
        raise ValueError("XDG_RUNTIME_DIR required")
    root = Path(runtime)
    if (root.is_symlink() or not root.is_dir()
            or root.stat().st_uid != os.getuid() or root.stat().st_mode & 0o077):
        raise ValueError("Unsafe XDG_RUNTIME_DIR")
    return (config / "umbriel/awtarchy-trial/floating-rules.toml",
            root / "awtarchy-umbriel-floating-windows-state",
            root / "awtarchy-umbriel-floating-windows.lock")


def current(path: Path):
    if path.is_symlink() or not path.is_file() or path.stat().st_uid != os.getuid():
        raise ValueError("Unowned or unavailable Umbriel floating config")
    data = path.read_bytes()
    if data == ON:
        return "enabled"
    if data == OFF:
        return "disabled"
    raise ValueError("Customized global floating rules preserved; refusing to overwrite")


def atomic_write(path: Path, payload: bytes):
    parent = path.parent
    if (parent.is_symlink() or not parent.is_dir()
            or parent.stat().st_uid != os.getuid()
            or path.is_symlink() or (path.exists()
                and (not path.is_file() or path.stat().st_uid != os.getuid()))):
        raise ValueError("Unsafe floating preference destination")
    fd, tmp = tempfile.mkstemp(dir=parent, prefix=".awtarchy-floating-")
    try:
        with os.fdopen(fd, "wb") as stream:
            os.fchmod(stream.fileno(), 0o600)
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(tmp, path)
    finally:
        if os.path.lexists(tmp):
            os.unlink(tmp)


def run(args):
    if (os.environ.get("XDG_CURRENT_DESKTOP", "").casefold() != "umbriel"
            or not os.environ.get("WAYLAND_DISPLAY") or os.geteuid() == 0):
        raise ValueError("An unprivileged Umbriel session is required")
    file, state, lock = files()
    if args == ["status"]:
        print(current(file))
        return
    if len(args) != 2 or args[0] != "set" or args[1] not in ("on", "off"):
        raise ValueError("Usage: floating-windows.py status|set on|off")
    fd = os.open(lock, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        previous = current(file)
        target = "enabled" if args[1] == "on" else "disabled"
        if previous != target:
            atomic_write(file, ON if target == "enabled" else OFF)
            try:
                validate = subprocess.run(["umbriel", "config", "validate"],
                                          capture_output=True, text=True,
                                          timeout=12, check=True)
                result = subprocess.run(["umbriel", "msg", "config-reload"],
                                        capture_output=True, text=True,
                                        timeout=12, check=True)
                reply = json.loads(result.stdout)
                if not isinstance(reply, dict) or "err" in reply or "ok" not in reply:
                    raise ValueError("Umbriel refused floating rule reload")
            except (OSError, ValueError, subprocess.TimeoutExpired,
                    subprocess.CalledProcessError, json.JSONDecodeError):
                atomic_write(file, ON if previous == "enabled" else OFF)
                subprocess.run(["umbriel", "msg", "config-reload"],
                               capture_output=True, text=True, timeout=12)
                raise
        atomic_write(state, (target + "\n").encode())
        print(target)
    finally:
        os.close(fd)


if __name__ == "__main__":
    try:
        run(sys.argv[1:])
    except (OSError, ValueError, subprocess.CalledProcessError,
            subprocess.TimeoutExpired, json.JSONDecodeError) as error:
        print("Umbriel floating mode: " + str(error), file=sys.stderr)
        sys.exit(1)
