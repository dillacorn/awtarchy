#!/usr/bin/env python3
"""Test secure Sway Quickshell locking without starting a real compositor.

This exercises only a disposable manager stub in a temporary config home.
It verifies power transitions delegate to the existing lock manager, which
waits for WlSessionLock.secure; it does not prove live lock security.
"""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
LOCK = ROOT / "trials/sway/lock.sh"
SOURCE_LOCK = ROOT / "config/quickshell/awtarchy-lock/shell.qml"
AUTH = ROOT / "config/quickshell/awtarchy-lock/LockAuth.qml"

assert "WlSessionLock {" in SOURCE_LOCK.read_text()
assert "return sessionLock.secure" in SOURCE_LOCK.read_text()
assert "PamContext {" in AUTH.read_text()
assert "password.conf" in AUTH.read_text()
manager_source = (ROOT / "trials/sway/lock-manager.sh").read_text()
upstream_manager = (ROOT / "config/hypr/scripts/awtarchy_lock.sh").read_text()
capture_source = (ROOT / "trials/sway/lock-capture.sh").read_text()
assert manager_source.replace('CAPTURE_HELPER="${SCRIPT_DIR}/lock-capture.sh"',
    'CAPTURE_HELPER="${SCRIPT_DIR}/quickshell_lockscreen_capture.sh"').splitlines()[3:] == (
        upstream_manager.splitlines()[2:]), (
    "Sway manager must retain the same secure lock/power semantics as Hyprland")
assert "wait_secure 5 || return $?" in manager_source, (
    "Power manager must not sleep before compositor confirms WlSessionLock.secure")
assert 'CAPTURE_HELPER="${SCRIPT_DIR}/lock-capture.sh"' in manager_source
assert "swaymsg -r -t get_outputs" in capture_source
assert "hyprctl" not in capture_source
assert "stage-promote-clean)" in capture_source
assert "stage-complete)" in capture_source
assert "consume-prepared)" in capture_source

with tempfile.TemporaryDirectory(prefix="sway-lock-test-") as t:
    home = Path(t)
    config = home / "config"
    manager = config / "sway/awtarchy-trial/lock-manager.sh"
    manager.parent.mkdir(parents=True)
    bin_path = home / "bin"
    bin_path.mkdir()
    log = home / "lock-log"
    manager.write_text(
        "#!/usr/bin/env bash\n"
        "printf 'manager:%s\\n' \"$*\" >>\"$AWTARCHY_LOCK_TEST_LOG\"\n"
        "case \"$1\" in\n"
        "  status) printf 'secure\\n' ;;\n"
        "  wait-secure) [[ \"${AWTARCHY_LOCK_TEST_FAIL_WAIT:-0}\" != 1 ]] ;;\n"
        "  lock|suspend|hibernate) true ;;\n"
        "  *) false ;;\n"
        "esac\n"
    )
    manager.chmod(0o755)
    fallback = bin_path / "swaylock"
    fallback.write_text("#!/usr/bin/env bash\nprintf 'swaylock:%s\\n' \"$*\" >>\"$AWTARCHY_LOCK_TEST_LOG\"\n")
    fallback.chmod(0o755)
    env = os.environ.copy()
    env.update({
        "HOME": str(home),
        "XDG_CONFIG_HOME": str(config),
        "XDG_CURRENT_DESKTOP": "sway",
        "WAYLAND_DISPLAY": "wayland-test",
        "SWAYSOCK": str(home / "sway-test.sock"),
        "PATH": str(bin_path) + os.pathsep + env.get("PATH", ""),
        "AWTARCHY_LOCK_TEST_LOG": str(log),
    })

    def run(action, *args, environment=None):
        return subprocess.run(
            ["bash", str(LOCK), action, *args],
            capture_output=True, text=True, timeout=8,
            env=environment or env,
        )

    assert run("lock").returncode == 0
    assert log.read_text().splitlines() == [
        "manager:lock", "manager:wait-secure 5",
    ]
    log.write_text("")
    assert run("lock-prepared").returncode == 0
    assert log.read_text().splitlines() == [
        "manager:lock", "manager:wait-secure 5",
    ]
    log.write_text("")
    assert run("suspend").returncode == 0
    assert run("hibernate").returncode == 0
    assert log.read_text().splitlines() == [
        "manager:suspend", "manager:hibernate",
    ]
    log.write_text("")
    assert run("status").stdout.strip() == "secure"
    assert run("wait-secure", "7").returncode == 0
    assert log.read_text().splitlines() == [
        "manager:status", "manager:wait-secure 7",
    ]

    failed_wait = env.copy()
    failed_wait["AWTARCHY_LOCK_TEST_FAIL_WAIT"] = "1"
    log.write_text("")
    assert run("lock", environment=failed_wait).returncode != 0
    assert log.read_text().splitlines() == [
        "manager:lock", "manager:wait-secure 5",
    ], "Do not report success or spawn swaylock over a pending Quickshell lock"

    # The fallback can only be used for an explicit lock request.
    manager.unlink()
    log.write_text("")
    assert run("lock").returncode == 0
    assert log.read_text().splitlines() == ["swaylock:-f -c 10151c"]
    log.write_text("")
    assert run("suspend").returncode != 0
    assert run("hibernate").returncode != 0
    assert not log.exists() or log.read_text() == ""
    assert run("wait-secure").returncode != 0

    # Never run a real lock outside an active Sway session.
    invalid = env.copy()
    invalid["XDG_CURRENT_DESKTOP"] = "Hyprland"
    assert run("lock", environment=invalid).returncode != 0

print("PASS: Sway uses secure Quickshell lock manager; fallback cannot authorize suspend")
