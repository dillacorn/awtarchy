#!/usr/bin/env python3
"""Prove an approved Jay update reaches sync.py, never package removal."""
from pathlib import Path
import os
import pty
import select
import subprocess
import sys
import tempfile
import time

root = Path(__file__).resolve().parents[1]
manager = root / "local/share/awtarchy/awtarchy-compositor-manager.sh"

with tempfile.TemporaryDirectory(prefix="awtarchy-jay-update-dispatch.") as folder:
    tmp = Path(folder)
    home = tmp / "home"
    state = home / ".local/state/awtarchy"
    state.mkdir(parents=True)
    (state / "compositor-trial-source").write_text(str(root) + "\n")
    bins = tmp / "bin"
    bins.mkdir()
    calls = tmp / "calls.log"
    py = bins / "python3"
    py.write_text("#!/bin/bash\n"
                  f"printf 'SYNC %s\\n' \"$*\" >> '{calls}'\n"
                  "return 0 2>/dev/null || true\n")
    py.chmod(0o755)
    for name in ("pacman", "sudo", "aur-scan"):
        exe = bins / name
        exe.write_text("#!/bin/bash\n"
                       f"printf 'UNEXPECTED {name}: %s\\n' \"$*\" >> '{calls}'\n"
                       "return 99 2>/dev/null || true\n")
        exe.chmod(0o755)

    env = dict(os.environ, HOME=str(home), PATH=str(bins) + ":" + os.environ["PATH"],
               XDG_CURRENT_DESKTOP="Hyprland")
    pid, fd = pty.fork()
    if pid == 0:
        os.execvpe("bash", ["bash", str(manager), "update-jay", "apply", "no"], env)
    output = b""
    try:
        os.write(fd, b"update-jay\n")
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            ready, _, _ = select.select([fd], [], [], 0.2)
            if ready:
                try:
                    data = os.read(fd, 4096)
                except OSError:
                    break
                if not data:
                    break
                output += data
            if b"Personal compositor configs retained" in output:
                break
        waited, status = os.waitpid(pid, os.WNOHANG)
        if waited == 0:
            os.kill(pid, 9)
            os.waitpid(pid, 0)
            raise AssertionError("Jay approved update timed out: " + output.decode(errors="replace"))
        assert os.waitstatus_to_exitcode(status) == 0, output.decode(errors="replace")
    finally:
        os.close(fd)
    recorded = calls.read_text()
    assert "SYNC " in recorded, recorded
    assert "apply --repo " + str(root) in recorded, recorded
    assert "UNEXPECTED" not in recorded, recorded

print("PASS: approved Jay managed update dispatches to sync.py, not pacman")
