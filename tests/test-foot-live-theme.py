#!/usr/bin/env python3
"""Regression tests for live Foot OSC palette delivery and PTY isolation."""
import importlib.util
import os
from pathlib import Path
import pty
import tempfile
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "config/hypr/scripts/foot_theme_live.py"
spec = importlib.util.spec_from_file_location("awtarchy_foot_live", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

palette = module.read_palette(ROOT / "config/foot/foot.ini")
assert len(palette) == 18
assert palette["background"] == "1f1f1f"
payload = module.osc_palette(palette)
assert payload.count(b"\x1b]4;") == 16
assert b"\x1b]10;#e5e1d8\x1b\\" in payload
assert b"\x1b]11;#1f1f1f\x1b\\" in payload
assert b"\x1b]4;0;#000000\x1b\\" in payload
assert b"\x1b]4;15;#ffffff\x1b\\" in payload

with tempfile.TemporaryDirectory() as temp:
    root = Path(temp) / "proc"
    root.mkdir()
    program = Path(temp) / "foot"
    program.write_bytes(b"\0")
    owner = os.getuid()
    master, slave = pty.openpty()
    tty = os.ttyname(slave)

    def process(pid, binary, child_ids=(), app_id=b"--app-id=example", signature=b"test-session"):
        item = root / str(pid)
        (item / "task" / str(pid)).mkdir(parents=True)
        (item / "fd").mkdir()
        (item / "exe").symlink_to(binary)
        (item / "status").write_text(f"Name:\tfixture\nUid:\t{owner}\t{owner}\t{owner}\t{owner}\n")
        (item / "cmdline").write_bytes(b"foot\0" + app_id + b"\0")
        (item / "environ").write_bytes(b"HYPRLAND_INSTANCE_SIGNATURE=" + signature + b"\0")
        (item / "task" / str(pid) / "children").write_text(
            " ".join(str(x) for x in child_ids)
        )
        return item

    try:
        current = process(100001, program, (100002,))
        shell = process(100002, "/bin/sh")
        (shell / "fd" / "0").symlink_to(tty)
        # Non-Foot parents never gain permission to inject color codes.
        random_process = process(100003, "/bin/sh", (100004,))
        other_child = process(100004, "/bin/sh")
        (other_child / "fd" / "0").symlink_to("/dev/pts/9999999")
        # An isolated PolicyKit Foot request must never be recolored.
        auth = process(100005, program, (100006,), b"--app-id=awtarchy-polkit-agent")
        auth_child = process(100006, "/bin/sh")
        (auth_child / "fd" / "0").symlink_to(tty)
        # A terminal owned by another Hyprland session is not selected.
        other_session = process(100007, program, (100008,), signature=b"other-session")
        other_session_child = process(100008, "/bin/sh")
        (other_session_child / "fd" / "0").symlink_to(tty)
        result = module.foot_ttys(
            proc_root=root,
            uid=owner,
            executables=(str(program),),
            session="test-session",
        )
        assert result == {tty}, result
        # Check the actual PTY output path without requiring a Wayland server.
        with mock.patch.object(module, "foot_ttys", return_value={tty}):
            assert module.broadcast(palette) == 1
        received = os.read(master, 4096)
        assert received == payload, (received, payload)
    finally:
        os.close(master)
        os.close(slave)

print("PASS: Foot live OSC colors, PTY targeting, session and PolicyKit isolation")
