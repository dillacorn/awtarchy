#!/usr/bin/env python3
"""Exercise the portable Jay Quick Settings backend with fake compositor state."""
from pathlib import Path
import json
import os
import shutil
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
backend = root / "trials/jay/quicksettings.py"
compile(backend.read_bytes(), str(backend), "exec")

with tempfile.TemporaryDirectory(prefix="awtarchy-jay-settings.") as tmp:
    base = Path(tmp)
    config = base / ".config"
    trial = config / "jay/awtarchy-trial"
    trial.mkdir(parents=True)
    calls = trial / "calls.log"

    fake_info = trial / "monitor-info.py"
    fake_info.write_text(
        'import json\n'
        'print(json.dumps([dict(name="DP-3", disabled=False, focused=True,'
        'width=1920,height=1080,refresh_rate=239.963)]))\n'
    )
    fake_manager = trial / "quickshell.sh"
    fake_manager.write_text(
        '#!/usr/bin/env bash\n'
        'case "$1" in\n'
        'getpos) printf "top\\n" ;;\n'
        'getenabled) printf "true\\n" ;;\n'
        'getautohide) printf "false\\n" ;;\n'
        f'setenabled|setautohide|setpos) printf "%s %s %s\\n" "$1" "$2" "$3" >> "{calls}" ;;\n'
        '*) return 2 ;;\n'
        'esac\n'
    )
    runtime = base / "runtime"
    runtime.mkdir()
    env = os.environ.copy()
    env.update(HOME=str(base), XDG_CONFIG_HOME=str(config), XDG_RUNTIME_DIR=str(runtime),
               XDG_CURRENT_DESKTOP="jay", WAYLAND_DISPLAY="wayland-9")

    def run(*args):
        return subprocess.run([sys.executable, str(backend), *args],
                              env=env, capture_output=True, text=True, timeout=5)

    status = run("--status-json", "DP-3", "Focused display")
    assert status.returncode == 0, status.stderr
    data = json.loads(status.stdout)
    assert data["monitors"][0]["refresh_rate"] == 239.963
    assert data["bar"]["monitor"] == "DP-3"
    assert data["bar"]["enabled"] and not data["bar"]["auto_hide"]
    assert not data["vibrance"]["enabled"]
    assert data["night_light"]["identity"] == "unsupported"
    assert data["sched_ext"]["available"] is False
    good = run("--action", "bar-enabled", "DP-3", "false")
    assert good.returncode == 0, good.stderr
    assert calls.read_text().strip() == "setenabled DP-3 false"

    before = calls.read_text()
    for operation in (
        ("--action", "vibrance", "toggle"),
        ("--action", "night-light", "toggle"),
        ("--action", "submap", "noalt"),
        ("--action", "bar-enabled", "BOGUS", "true"),
        ("--action", "bar-position", "DP-3", "diagonal"),
        ("--action", "scheduler-start", "scx_lavd"),
        ("--restore-scheduler",),
    ):
        attempt = run(*operation)
        assert attempt.returncode != 0, operation
        assert calls.read_text() == before, f"Unsupported action changed state: {operation}"

    out_of_session = dict(env, XDG_CURRENT_DESKTOP="Hyprland")
    blocked = subprocess.run([sys.executable, str(backend), "--status-json"],
                             env=out_of_session, capture_output=True, text=True)
    assert blocked.returncode != 0

print("PASS: Jay Quick Settings reports real monitor/bar state and rejects unported actions")
