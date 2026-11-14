#!/usr/bin/env python3
"""Screenshot sound preferences: shared state, per-shortcut muting and PCM identity."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "config/hypr/scripts/screenshot_sound.sh"
SWAY_SETUP = ROOT / "trials/sway/setup.sh"
SWAY_SYNC = ROOT / "trials/sway/sync.py"
HYPR_AREA = ROOT / "config/hypr/scripts/screenshot_area.sh"
HYPR_FULL = ROOT / "config/hypr/scripts/screenshot_fullscreen.sh"
EXPECTED_HASH = "baaa25535f97d7d3d870c0f7daa1d59d7e225b42cc6bb8945f5a87285bfa692c"

assert "screenshot_sound.sh" in SWAY_SETUP.read_text()
assert "screenshot_sound.sh" in SWAY_SYNC.read_text()
assert "play satty 9>&-" in HYPR_AREA.read_text()
assert "play satty 9>&-" in HYPR_FULL.read_text()
assert "ScreenshotSoundSettings" in (
    ROOT / "config/quickshell/awtarchy/QuickSettings.qml").read_text()
assert (ROOT / "config/quickshell/awtarchy/ScreenshotSoundSettings.qml").is_file()

with tempfile.TemporaryDirectory(prefix="screenshot-sound-contract-") as temp:
    root = Path(temp)
    home = root / "home"
    home.mkdir()
    state = root / "state"
    tools = root / "bin"
    tools.mkdir()
    events = root / "events"
    events.touch()
    pw_mock = tools / "pw-play"
    pw_mock.write_text(r"""#!/usr/bin/env bash
set -euo pipefail
[[ "$*" == "--raw --format=s16 --rate=48000 --channels=1 --volume=0.80 --latency=20ms -" ]] || exit 9
hash="$(python3 -c 'import hashlib,sys; data=sys.stdin.buffer.read(); print(len(data), hashlib.sha256(data).hexdigest())')"
printf '%s\n' "$hash" >>"$EVENTS"
""")
    pw_mock.chmod(0o755)
    env = dict(os.environ, HOME=str(home), XDG_STATE_HOME=str(state),
               PATH=str(tools) + os.pathsep + os.environ.get("PATH", ""),
               EVENTS=str(events))

    def run(*args, check=True):
        return subprocess.run(["bash", str(HELPER), *args], env=env, text=True,
                              capture_output=True, timeout=6, check=check)

    def config():
        return json.loads(run("get").stdout)

    def count():
        return len(events.read_text().splitlines())

    def expect_sound(mode, enabled=True):
        before = count()
        result = run("play", mode)
        assert result.returncode == 0
        for _ in range(80):
            if count() > before:
                break
            time.sleep(0.05)
        assert count() == before + int(enabled), (mode, enabled, events.read_text())
        if enabled:
            assert events.read_text().splitlines()[-1] == "17280 " + EXPECTED_HASH

    # Absent state defaults on and never creates a state file during capture.
    assert config() == dict(enabled=True, direct=True, satty=True, print=True)
    assert not state.exists()
    expect_sound("direct")
    expect_sound("satty")
    expect_sound("print")
    assert not state.exists()

    run("set", "satty", "false")
    assert config()["satty"] is False
    assert config()["direct"] is True
    assert config()["print"] is True
    cfg_file = state / "awtarchy" / "screenshot-sound.conf"
    assert cfg_file.is_file()
    assert cfg_file.stat().st_mode & 0o777 == 0o600
    expect_sound("satty", False)
    expect_sound("print")
    expect_sound("direct")

    run("set", "print", "false")
    expect_sound("print", False)
    expect_sound("direct")
    run("set", "enabled", "false")
    for mode in ("direct", "satty", "print"):
        expect_sound(mode, False)
    run("set", "enabled", "true")
    assert config() == dict(enabled=True, direct=True, satty=False, print=False)
    expect_sound("direct")
    expect_sound("satty", False)
    expect_sound("print", False)

    # Reject malformed settings commands and avoid changing saved state.
    before = cfg_file.read_bytes()
    for args in [("set", "direct", "yes"), ("set", "unexpected", "true"),
                 ("play", "unknown"), ("get", "extra")]:
        assert run(*args, check=False).returncode != 0
        assert cfg_file.read_bytes() == before

    # No symlink following: reject linked settings instead of mutating targets.
    cfg_file.unlink()
    other = root / "unrelated"
    other.write_text("private\n")
    cfg_file.symlink_to(other)
    assert run("set", "enabled", "false", check=False).returncode != 0
    assert other.read_text() == "private\n"
    assert run("get", check=False).returncode != 0
    expect_sound("direct", False)

print("PASS: Shared screenshot sound state, full mute, per-shortcut mute, "
      "exact selected audio, no-save-on-get, and linked-state rejection")
