#!/usr/bin/env python3
"""TTY Sway launcher contract, tested without a real compositor or display manager."""
import os
from pathlib import Path
import pty
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
LAUNCHER = ROOT / "compositors/sway/tty-launch.sh"
assert LAUNCHER.is_file()
assert subprocess.run(["bash", "-n", str(LAUNCHER)], check=False).returncode == 0
body = LAUNCHER.read_text(encoding="utf-8")
assert body.count("/usr/local/bin/awtarchy-sway-session") == 1
assert body.count("/usr/bin/sway") == 1
assert "XDG_SESSION_TYPE" in body
assert '[[ $# -eq 0' in body

with tempfile.TemporaryDirectory(prefix="sway-tty-contract-") as tmp:
    root = Path(tmp)
    native = root / "native-sway"
    session = root / "awtarchy-sway-session"
    native.write_text('#!/usr/bin/env bash\nprintf "native:%s\\n" "$*"\n')
    session.write_text('#!/usr/bin/env bash\nprintf "awtarchy-session\\n"\n')
    native.chmod(0o755)
    session.chmod(0o755)
    # Substitute fixture paths only in this test copy. Never modify native Sway.
    fixture = root / "sway"
    fixture.write_text(body.replace(
        "/usr/local/bin/awtarchy-sway-session", str(session)
    ).replace("/usr/bin/sway", str(native)))
    fixture.chmod(0o755)
    env = dict(os.environ)
    env.update(XDG_SESSION_TYPE="tty", WAYLAND_DISPLAY="", DISPLAY="",
               SSH_CONNECTION="", SSH_TTY="")

    def run_tty(*arguments, environment=None):
        master, slave = pty.openpty()
        try:
            result = subprocess.run(
                [str(fixture), *arguments], env=environment or env,
                stdin=slave, stdout=slave, stderr=slave, timeout=10)
            os.close(slave)
            slave = -1
            output = bytearray()
            while True:
                try:
                    chunk = os.read(master, 65536)
                except OSError:
                    break  # Linux pty end-of-stream raises EIO.
                if not chunk:
                    break
                output.extend(chunk)
            return result.returncode, output.decode(errors="replace")
        finally:
            if slave >= 0:
                os.close(slave)
            os.close(master)

    code, text = run_tty()
    assert code == 0 and "awtarchy-session" in text, (code, text)
    code, text = run_tty("-C", "-c", "/tmp/native-sway-config")
    assert code == 0 and "native:-C -c /tmp/native-sway-config" in text
    code, text = run_tty(environment=dict(env, WAYLAND_DISPLAY="wayland-1"))
    assert code == 0 and "native:" in text and "awtarchy-session" not in text
    code, text = run_tty(environment=dict(env, SSH_CONNECTION="remote"))
    assert code == 0 and "native:" in text
    code, text = run_tty(environment=dict(env, XDG_SESSION_TYPE="wayland"))
    assert code == 0 and "native:" in text
    notty = subprocess.run([str(fixture)], env=env, capture_output=True,
                            text=True, timeout=10)
    assert notty.returncode == 0 and "native:" in notty.stdout
    session.unlink()
    code, text = run_tty()
    assert code == 127 and "missing or unsafe" in text

print("PASS: sway TTY command, native CLI, non-TTY fallback and missing session")
