#!/usr/bin/env python3
"""Umbriel TTY launcher forwards normal CLI/IPC and uses native session only on a true TTY."""
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
launcher = root / "compositors/umbriel/tty-launch.sh"
body = launcher.read_text(encoding="utf-8")
subprocess.run(["bash", "-n", str(launcher)], check=True)
for fragment in (
    '[[ $# -eq 0 && -t 0 && -t 1 &&',
    '-z "${WAYLAND_DISPLAY:-}"',
    '-z "${SSH_CONNECTION:-}"',
    '"${XDG_SESSION_TYPE:-tty}" == tty',
    'session=/usr/bin/start-umbriel',
    'exec "$session"',
    'exec /usr/bin/umbriel "$@"',
):
    assert fragment in body, fragment
assert "awtarchy-trial" not in body
sync = (root / "compositors/umbriel/sync.py").read_text(encoding="utf-8")
assert 'home / ".local/bin/umbriel"' in sync
assert 'src / "tty-launch.sh"' in sync
print("PASS: Umbriel TTY launcher preserves native commands and is managed")
