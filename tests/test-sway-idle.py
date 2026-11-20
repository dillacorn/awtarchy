#!/usr/bin/env python3
"""Sway idle policy: no session leak, no duplicate daemon, guarded lock/power."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
TRIAL = ROOT / "compositors/sway"
config = (TRIAL / "swayidle.conf").read_text()
manager_source = (TRIAL / "idle-manager.py").read_text()
script = TRIAL / "idle-action.sh"
for text in ("timeout 180", "timeout 240", "timeout 540", "before-sleep", "after-resume"):
    assert text in config
assert "swaylock" not in config
assert "pidfd_open" in manager_source and "pidfd_send_signal" in manager_source
assert "exec_always python3 $trial/idle-manager.py start" in (TRIAL / "config").read_text()
assert "idle-manager.py" in (TRIAL / "setup.sh").read_text()
assert '".config/sway/awtarchy-trial/idle-manager.py"' in (TRIAL / "sync.py").read_text()

with tempfile.TemporaryDirectory(prefix="awtarchy-idle-test-") as tmp:
    home = Path(tmp)
    output = home / "events"
    output.touch()
    lock = home / "lock.sh"
    inhibitor = home / "inhibitor.sh"
    obs = home / "obs.sh"
    sway = home / "swaymsg"
    systemctl = home / "systemctl"
    lock.write_text('#!/usr/bin/env bash\n'
                    'printf "lock %s\\n" "$*" >> "$AWTARCHY_TEST_EVENTS"\n'
                    '[[ "$AWTARCHY_TEST_LOCK_FAIL" != 1 ]]\n')
    inhibitor.write_text('#!/usr/bin/env bash\n'
                         '[[ "$AWTARCHY_TEST_INHIBITOR" == 1 ]]\n')
    obs.write_text('#!/usr/bin/env bash\n'
                   '[[ "$AWTARCHY_TEST_OBS" == 1 ]]\n')
    sway.write_text('#!/usr/bin/env bash\n'
                    'printf "sway %s\\n" "$*" >> "$AWTARCHY_TEST_EVENTS"\n'
                    'printf \'[{"success":true}]\\n\'\n')
    systemctl.write_text('#!/usr/bin/env bash\n'
                         'printf "systemctl %s\\n" "$*" >> "$AWTARCHY_TEST_EVENTS"\n')
    for item in (lock, inhibitor, obs, sway, systemctl):
        item.chmod(0o755)
    env = dict(os.environ, XDG_CURRENT_DESKTOP="sway",
               SWAYSOCK=str(home / "sway.sock"), WAYLAND_DISPLAY="wayland-1",
               AWTARCHY_SWAY_LOCK_SCRIPT=str(lock),
               AWTARCHY_SWAY_INHIBITOR_SCRIPT=str(inhibitor),
               AWTARCHY_SWAY_OBS_SCRIPT=str(obs),
               AWTARCHY_SWAY_SWAYMSG=str(sway),
               AWTARCHY_SWAY_SYSTEMCTL=str(systemctl),
               AWTARCHY_TEST_EVENTS=str(output), AWTARCHY_TEST_LOCK_FAIL="0",
               AWTARCHY_TEST_INHIBITOR="0", AWTARCHY_TEST_OBS="0")
    def call(action, **switches):
        output.write_text("")
        return subprocess.run(["bash", str(script), action],
                              env=dict(env, **switches), capture_output=True,
                              text=True, timeout=5)

    result = call("dpms-off")
    assert result.returncode == 0, result.stderr
    assert output.read_text().splitlines() == [
        "lock lock", "sway -r -t command output * power off"]
    result = call("suspend")
    assert result.returncode == 0, result.stderr
    assert output.read_text().splitlines() == [
        "lock lock", "systemctl --no-block suspend"]
    result = call("dpms-off", AWTARCHY_TEST_LOCK_FAIL="1")
    assert result.returncode != 0
    assert output.read_text().splitlines() == ["lock lock"]
    result = call("suspend", AWTARCHY_TEST_LOCK_FAIL="1")
    assert result.returncode != 0
    assert output.read_text().splitlines() == ["lock lock"]
    for key in ("AWTARCHY_TEST_INHIBITOR", "AWTARCHY_TEST_OBS"):
        for action in ("dpms-off", "suspend"):
            result = call(action, **{key: "1"})
            assert result.returncode == 0
            assert output.read_text() == "", key
    result = call("pre-sleep", AWTARCHY_TEST_INHIBITOR="1")
    assert result.returncode == 0
    assert output.read_text() == "lock lock\n"
    result = call("resume", AWTARCHY_TEST_INHIBITOR="1")
    assert result.returncode == 0
    assert output.read_text() == "sway -r -t command output * power on\n"

    spec = importlib.util.spec_from_file_location("sway_idle_manager",
                                                 TRIAL / "idle-manager.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    trial = home / "config/sway/awtarchy-trial"
    trial.mkdir(parents=True)
    (trial / "config").write_text("Sway trial\n")
    (trial / "swayidle.conf").write_text(config)
    runtime = home / "runtime"
    runtime.mkdir(mode=0o700)
    env2 = dict(env, XDG_CONFIG_HOME=str(home / "config"),
                XDG_RUNTIME_DIR=str(runtime),
                XDG_CACHE_HOME=str(home / "cache"))
    with patch.object(module, "TRIAL", trial), \
         patch.object(module, "CONFIG", trial / "swayidle.conf"), \
         patch.object(module.subprocess, "run",
                      return_value=SimpleNamespace(returncode=0,
                          stdout=json.dumps({"loaded_config_file_name":
                                             str(trial / "config")}))), \
         patch.object(module.shutil, "which", return_value="/usr/bin/swayidle"), \
         patch.object(module, "start_marker", return_value=("S", "123")), \
         patch.object(module, "verified",
                      side_effect=lambda info, *args:
                          isinstance(info, dict) and info.get("start") == "123"), \
         patch.object(module, "stop_exact") as stop, \
         patch.object(module.time, "sleep"), \
         patch.dict(os.environ, env2):
        child = SimpleNamespace(pid=21132, poll=lambda: None,
                                terminate=lambda: None)
        with patch.object(module.subprocess, "Popen", return_value=child) as spawn:
            assert module.main("start") == 0
            assert spawn.call_count == 1
            assert module.main("start") == 0
            assert spawn.call_count == 1, "Duplicate swayidle spawned"
            assert module.main("status") == 0
            (trial / "swayidle.conf").write_text(config + "\n# altered\n")
            assert module.main("start") == 0
            assert spawn.call_count == 2
            assert stop.call_count == 1
        with patch.dict(os.environ, {"XDG_CURRENT_DESKTOP": "Hyprland"}):
            try:
                module.session_identity()
            except ValueError:
                pass
            else:
                raise AssertionError("Hyprland session allowed to start Sway idle")

print("PASS: Sway idle lock, DPMS, guarded suspend, inhibitors and managed daemon")
