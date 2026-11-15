#!/usr/bin/env python3
"""Theme border colors are compositor-local and never require hyprctl."""
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
script = root / "trials/sway/theme-colors.sh"

with tempfile.TemporaryDirectory(prefix="sway-theme-colors-") as temp:
    base = Path(temp)
    config = base / "config"
    state = base / "state/awtarchy"
    fakebin = base / "bin"
    theme_dir = config / "hypr/themes"
    for folder in (state, fakebin, theme_dir):
        folder.mkdir(parents=True)
    (theme_dir / "test").write_text(
        'NEW_ACTIVE_BORDER="112233ff"\n'
        'NEW_INACTIVE_BORDER="445566ff"\n'
        'QS_BACKGROUND="#101010"\n'
        'QS_FOREGROUND="#eeeeee"\n'
        'QS_URGENT="#990000"\n')
    (theme_dir / "bad").write_text('NEW_ACTIVE_BORDER="notacolor"\n')
    log = base / "calls"
    fake_sway = fakebin / "swaymsg"
    fake_sway.write_text(
        '#!/usr/bin/env bash\n'
        'printf "%s\\n" "$*" >>"$AWTARCHY_TEST_SWAY_CALLS"\n'
        'printf \'[%s]\\n\' \'{"success":true}\'\n')
    fake_sway.chmod(0o755)
    fake_hypr = fakebin / "hyprctl"
    fake_hypr.write_text('#!/usr/bin/env bash\nfalse\n')
    fake_hypr.chmod(0o755)

    env = os.environ.copy()
    env.update({
        "PATH": str(fakebin) + os.pathsep + os.environ.get("PATH", ""),
        "XDG_CURRENT_DESKTOP": "sway",
        "SWAYSOCK": "/fake/sway.sock",
        "XDG_CONFIG_HOME": str(config),
        "XDG_STATE_HOME": str(base / "state"),
        "AWTARCHY_TEST_SWAY_CALLS": str(log),
    })
    def run(*args):
        return subprocess.run(["bash", str(script), *args],
                              env=env, capture_output=True, text=True, timeout=10)
    result = run("test")
    assert result.returncode == 0, result.stderr
    lines = log.read_text().splitlines()
    assert len(lines) == 4, lines
    assert lines[0] == (
        "-r -t command client.focused #112233ff #101010 #eeeeee #112233ff #112233ff"), lines
    assert lines[1].endswith(
        "client.focused_inactive #445566ff #101010 #eeeeee #445566ff #445566ff"), lines
    assert lines[2].endswith(
        "client.unfocused #445566ff #101010 #eeeeee #445566ff #445566ff"), lines
    assert lines[3].endswith(
        "client.urgent #990000 #990000 #eeeeee #990000 #990000"), lines

    (state / "active-theme-sway").write_text("test\n")
    assert run().returncode == 0
    assert len(log.read_text().splitlines()) == 8
    result = run("bad")
    assert result.returncode != 0
    assert len(log.read_text().splitlines()) == 8
    result = run("../escape")
    assert result.returncode != 0
    assert len(log.read_text().splitlines()) == 8
    env["XDG_CURRENT_DESKTOP"] = "Hyprland"
    assert run("test").returncode != 0
    assert len(log.read_text().splitlines()) == 8

print("PASS: Sway theme border palette and input validation, no Hyprland IPC")
