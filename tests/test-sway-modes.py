#!/usr/bin/env python3
"""Regression coverage for native Sway modes and compositor-confirmed UI state."""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
TRIAL = ROOT / "trials/sway"
config = (TRIAL / "config").read_text()
blocks = {}
for name in ("noalt", "mouse", "vm"):
    prefix = 'mode "' + name + '" {\n'
    assert config.count(prefix) == 1, name
    blocks[name] = config.split(prefix, 1)[1].split('\n}', 1)[0]
    for key, target in (("n", "noalt"), ("m", "mouse"), ("v", "vm")):
        assert (f"bindsym --inhibited Mod4+Mod1+{key} exec bash "
                f"$trial/mode-control.sh toggle {target}") in blocks[name]
assert "Mod4+2 workspace number 2" in blocks["noalt"]
assert "Mod1+Tab exec python3 $trial/focus-cycle.py next" in blocks["noalt"]
assert "Mod4+Mod1+2 workspace number 2" in blocks["vm"]
assert "Mod4+Mod1+Shift+2 move container to workspace number 2" in blocks["vm"]
assert "button1" not in blocks["mouse"]
assert 'exec_always bash $trial/mode-state.sh sync' in config
render = (TRIAL / "render-quickshell.py").read_text()
assert "'/sway/awtarchy-trial/mode-control.sh'" in render
assert '[bar.mouseSubmapScript, "toggle", "mouse"]' in render
with tempfile.TemporaryDirectory(prefix="sway-modes-") as tmp:
    home = Path(tmp)
    runtime = home / "runtime"
    runtime.mkdir(mode=0o700)
    binpath = home / "bin"
    binpath.mkdir()
    installed = home / ".config/sway/awtarchy-trial"
    installed.mkdir(parents=True)
    (installed / "mode-state.sh").write_text((TRIAL / "mode-state.sh").read_text())
    mock = binpath / "swaymsg"
    mock.write_text("""#!/usr/bin/env python3
import json, os, pathlib, sys
p = pathlib.Path(os.environ["MOCK_MODE_FILE"])
args = sys.argv[1:]
if args == ["-r", "-t", "get_binding_state"]:
    print(json.dumps({"name": p.read_text().strip()}))
elif args[:3] == ["-r", "-t", "command"]:
    name = args[3].removeprefix('mode "').removesuffix('"')
    if os.environ.get("MOCK_REJECT") == "1":
        print('[{"success": false}]')
    else:
        p.write_text(name)
        print('[{"success": true}]')
else:
    sys.exit(3)
""")
    mock.chmod(0o755)
    state = home / "fake-mode"
    state.write_text("default")
    env = dict(os.environ, HOME=str(home), XDG_RUNTIME_DIR=str(runtime),
               XDG_CURRENT_DESKTOP="sway", WAYLAND_DISPLAY="wayland-1",
               SWAYSOCK=str(home / "socket"), MOCK_MODE_FILE=str(state),
               PATH=str(binpath) + os.pathsep + os.environ["PATH"])
    def call(*args, reject=False):
        return subprocess.run(["bash", str(TRIAL / "mode-control.sh"), *args],
                              env=dict(env, MOCK_REJECT="1" if reject else "0"),
                              capture_output=True, text=True, timeout=6)
    for name in ("noalt", "mouse", "vm"):
        result = call("toggle", name)
        assert result.returncode == 0, result.stderr
        assert state.read_text() == name
        assert (runtime / "awtarchy-sway-submap").read_text().strip() == name
    assert call("toggle", "vm").returncode == 0
    assert state.read_text() == "default"
    assert call("toggle", "mouse").returncode == 0
    assert call("reset").returncode == 0
    assert state.read_text() == "default"
    assert (runtime / "awtarchy-sway-submap").read_text() == ""
    assert call("toggle", "noalt", reject=True).returncode != 0
    assert state.read_text() == "default"
    state.write_text("custom-user-mode")
    assert call("toggle", "vm").returncode != 0
    assert state.read_text() == "custom-user-mode"
    state.write_text("noalt")
    result = subprocess.run(["bash", str(installed / "mode-state.sh"), "sync"],
                            env=env, capture_output=True, text=True, timeout=5)
    assert result.returncode == 0, result.stderr
    assert (runtime / "awtarchy-sway-submap").read_text().strip() == "noalt"
print("PASS: Sway native modes, safe toggle and accurate submap state")
