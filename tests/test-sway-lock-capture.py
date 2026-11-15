#!/usr/bin/env python3
"""Mocked Sway lockscreen capture lifecycle with private temp files."""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "trials/sway/lock-capture.sh"
UPSTREAM = ROOT / "config/hypr/scripts/quickshell_lockscreen_capture.sh"

source = HELPER.read_text()
assert "swaymsg -r -t get_outputs" in source
assert "hyprctl" not in source
assert "swaymsg" not in UPSTREAM.read_text(), (
    "Hyprland capture implementation must remain unchanged")

with tempfile.TemporaryDirectory(prefix="sway-lock-capture-") as t:
    root = Path(t)
    runtime = root / "runtime"
    runtime.mkdir(mode=0o700)
    bin_path = root / "bin"
    bin_path.mkdir()
    swaymsg = bin_path / "swaymsg"
    swaymsg.write_text(
        "#!/usr/bin/env bash\n"
        "printf '%s\\n' '[{\"name\":\"DP-1\",\"active\":true},"
        "{\"name\":\"DP-3\",\"active\":true},"
        "{\"name\":\"HDMI-A-1\",\"active\":false}]'\n"
    )
    swaymsg.chmod(0o755)
    grim = bin_path / "grim"
    grim.write_text(
        "#!/usr/bin/env bash\n"
        "[[ \"$1\" == -l && \"$2\" == 1 && \"$3\" == -o ]] || false\n"
        "printf 'mock PNG %s\\n' \"$4\" > \"$5\"\n"
    )
    grim.chmod(0o755)
    env = os.environ.copy()
    env.update({
        "XDG_RUNTIME_DIR": str(runtime),
        "XDG_CURRENT_DESKTOP": "sway",
        "PATH": str(bin_path) + os.pathsep + env.get("PATH", ""),
    })

    def run(*arguments):
        return subprocess.run(
            ["bash", str(HELPER), *arguments], env=env,
            capture_output=True, text=True, timeout=10,
        )

    direct = run("prepare")
    assert direct.returncode == 0, direct.stderr
    capture = Path(direct.stdout.strip())
    assert capture.is_dir() and capture.parent == runtime / "awtarchy-lock-transition"
    for output in ("DP-1", "DP-3"):
        assert (capture / (output + ".png")).is_file()
        assert (capture / (output + ".transition.png")).is_file()
    assert not (capture / "HDMI-A-1.png").exists()
    assert run("cleanup", str(capture)).returncode == 0
    assert not capture.exists()

    stage = run("stage-begin")
    assert stage.returncode == 0, stage.stderr
    pending = Path(stage.stdout.strip())
    for output in ("DP-1", "DP-3"):
        assert (pending / (output + ".transition.png")).is_file()
    assert run("stage-complete", str(pending)).returncode == 0
    consume = run("consume-prepared")
    assert consume.returncode == 0, consume.stderr
    assert consume.stdout.strip() == str(pending)
    assert run("cleanup", str(pending)).returncode == 0
    assert not pending.exists()

    assert run("cleanup", str(root)).returncode != 0, (
        "Never remove arbitrary directories")

print("PASS: Sway secure lock captures active outputs and cleans private frames")
