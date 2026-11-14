#!/usr/bin/env python3
"""Login sound parity: exact MP3, Sway session entry, independent mute state."""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PREFS = ROOT / "config/hypr/scripts/screenshot_sound.sh"
HYPR = ROOT / "config/hypr/scripts/quickshell_ready_sound.sh"
SWAY = ROOT / "trials/sway/login-sound.sh"
SOUND = ROOT / "config/hypr/sounds/awtarchy-login.mp3"
SESSION = (ROOT / "trials/sway/session.sh").read_text()
CONFIG = (ROOT / "trials/sway/config").read_text()
SETUP = (ROOT / "trials/sway/setup.sh").read_text()
SYNC = (ROOT / "trials/sway/sync.py").read_text()
QML = (ROOT / "config/quickshell/awtarchy/ScreenshotSoundSettings.qml").read_text()

assert SOUND.is_file() and SOUND.stat().st_size > 100
assert 'bash "$trial/login-sound.sh"' in SESSION
assert "exec bash $trial/session.sh" in CONFIG
assert "exec_always bash $trial/session.sh" not in CONFIG
assert "config/hypr/sounds/awtarchy-login.mp3" in SETUP
assert "config/hypr/sounds/awtarchy-login.mp3" in SYNC
assert 'onClicked: root.change("login")' in QML
assert 'onClicked: root.change("enabled")' in QML
assert 'is-enabled login' in HYPR.read_text()
assert 'is-enabled login' in SWAY.read_text()

expected = hashlib.sha256(SOUND.read_bytes()).hexdigest()

with tempfile.TemporaryDirectory(prefix="awtarchy-login-sound-") as base:
    root = Path(base)
    home = root / "home"
    home.mkdir()
    config = home / ".config"
    trial = config / "sway/awtarchy-trial"
    trial.mkdir(parents=True)
    run_dir = root / "runtime"
    run_dir.mkdir()
    bin_dir = root / "bin"
    bin_dir.mkdir()
    events = root / "events"
    events.touch()

    shutil.copy2(SOUND, trial / "awtarchy-login.mp3")
    shutil.copy2(PREFS, trial / "screenshot_sound.sh")
    shutil.copy2(SWAY, trial / "login-sound.sh")
    assert hashlib.sha256((trial / "awtarchy-login.mp3").read_bytes()).hexdigest() == expected

    (bin_dir / "qs").write_text(
        "#!/bin/sh\n[ \"$1 $2 $3 $4 $5\" = '-c awtarchy ipc call control' ] || :\n"
        "printf ''\n")
    (bin_dir / "wpctl").write_text(
        "#!/bin/sh\nprintf 'node.name = \"test-audio-sink\"\\n'\n")
    (bin_dir / "systemctl").write_text("#!/bin/sh\nfalse\n")
    (bin_dir / "pw-play").write_text(r"""#!/usr/bin/env python3
import hashlib
import os
from pathlib import Path
import sys
import time
sound = Path(sys.argv[-1])
if not sound.is_file():
    sys.exit(2)
if os.environ.get("AUDIO_DELAY"):
    time.sleep(float(os.environ["AUDIO_DELAY"]))
with open(os.environ["EVENTS"], "a") as f:
    f.write(hashlib.sha256(sound.read_bytes()).hexdigest() + "\n")
""")
    for path in bin_dir.iterdir():
        path.chmod(0o755)

    env = dict(os.environ,
        HOME=str(home), XDG_CONFIG_HOME=str(config),
        XDG_STATE_HOME=str(root / "state"),
        XDG_RUNTIME_DIR=str(run_dir),
        WAYLAND_DISPLAY="wayland-test",
        SWAYSOCK="/run/user/test-sway.sock",
        XDG_CURRENT_DESKTOP="sway",
        LOGIN_SOUND_WAIT_SECS="1",
        SOUND_FILE=str(SOUND),
        LOGIN_SOUND_PREFS=str(PREFS),
        WAIT_SHELL_SECS="1",
        NETWORK_WAIT_SECS="0",
        REFRESH_DETECT_WINDOW_SECS="0",
        WAIT_AUDIO_SECS="2",
        SHELL_POLL_SECS="0.01",
        SCRIPT_LOCK_FILE=str(run_dir / "hypr-ready-sound.lock"),
        USB_REFRESH_LOCK_FILE=str(root / "inactive-refresh"),
        SUBMAP_STATE_HELPER=str(root / "no-submap-helper"),
        QUICKSHELL_MANAGER=str(root / "no-manager"),
        EVENTS=str(events),
        PATH=str(bin_dir) + os.pathsep + os.environ.get("PATH", ""))

    def setpref(key, value):
        subprocess.run(["bash", str(PREFS), "set", key, value],
                       env=env, check=True, timeout=3)

    def launch(path, **overrides):
        return subprocess.run(["bash", str(path)], env=dict(env, **overrides),
                              capture_output=True, text=True, timeout=5)

    def count():
        return len(events.read_text().splitlines())

    # Both compositors must respect the same login mute immediately.
    setpref("login", "false")
    assert launch(SWAY).returncode == 0
    assert launch(HYPR).returncode == 0
    assert count() == 0

    # Master screenshot mute is not a master login mute.
    setpref("login", "true")
    setpref("enabled", "false")
    assert launch(SWAY).returncode == 0
    assert count() == 1
    assert launch(HYPR).returncode == 0
    assert count() == 2
    assert events.read_text().splitlines() == [expected, expected]

    # On repeated simultaneous startup attempts the Sway lock prevents
    # playing the iconic MP3 twice, without preventing compositor startup.
    events.write_text("")
    delayed = dict(env, AUDIO_DELAY="0.4")
    first = subprocess.Popen(["bash", str(SWAY)], env=delayed,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    second = subprocess.Popen(["bash", str(SWAY)], env=delayed,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    for process in (first, second):
        stdout, stderr = process.communicate(timeout=5)
        assert process.returncode == 0, (stdout, stderr)
    assert events.read_text().splitlines() == [expected]

    # Sway must be a no-op outside its own session.
    events.write_text("")
    assert launch(SWAY, XDG_CURRENT_DESKTOP="Hyprland").returncode == 0
    assert count() == 0

print("PASS: Exact Awtarchy login MP3 in Sway and Hyprland, shared mute, "
      "once per login, and screenshot mute independence")
