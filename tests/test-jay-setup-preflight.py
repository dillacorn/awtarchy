#!/usr/bin/env python3
"""Run Jay's real --check in an isolated fixture; prove it creates no files.

The source setup script is copied to a temporary repository fixture. Only the
Arch host gate and the two system destinations are redirected in that copy.
The test never invokes sudo or a package manager.
"""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]

with tempfile.TemporaryDirectory(prefix="awtarchy-jay-check.") as base:
    temp = Path(base)
    fixture = temp / "repository"
    trial = fixture / "trials/jay"
    shutil.copytree(repo / "trials/jay", trial)
    shell = fixture / "config/quickshell/awtarchy"
    shutil.copytree(repo / "config/quickshell/awtarchy", shell)
    hypr_script = fixture / "config/hypr/scripts/quickshell.sh"
    hypr_script.parent.mkdir(parents=True)
    shutil.copy2(repo / "config/hypr/scripts/quickshell.sh", hypr_script)

    setup = trial / "setup.sh"
    contents = setup.read_text(encoding="utf-8")
    old_arch = '[[ -f /etc/arch-release ]] || fail \'Arch/CachyOS required\''
    assert contents.count(old_arch) == 1
    contents = contents.replace(old_arch, '[[ -d /tmp ]] || fail \'Fixture missing\'')
    original_desktop = 'desktop="/usr/share/wayland-sessions/awtarchy-jay-trial.desktop"'
    original_portal = 'system_portal="/usr/share/xdg-desktop-portal/portals/jay.portal"'
    assert contents.count(original_desktop) == 1
    assert contents.count(original_portal) == 1
    contents = contents.replace(original_desktop, f'desktop="{temp}/system/ly.desktop"')
    contents = contents.replace(original_portal, f'system_portal="{temp}/system/jay.portal"')
    setup.write_text(contents, encoding="utf-8")

    fake_bin = temp / "bin"
    fake_bin.mkdir()
    for name in ("jay", "qs", "foot", "fuzzel", "mako", "swaylock",
                 "grim", "slurp", "wl-copy", "jq", "sudo"):
        program = fake_bin / name
        program.write_text("#!/bin/sh\\nprintf 'unexpected external invocation\\n' >&2\\nreturn 99\\n")
        program.chmod(0o755)

    config_home = temp / "user/.config"
    config_home.mkdir(parents=True)
    env = os.environ.copy()
    env["HOME"] = str(temp / "user")
    env["XDG_CONFIG_HOME"] = str(config_home)
    env["PATH"] = f"{fake_bin}:" + env.get("PATH", "")
    completed = subprocess.run(["bash", str(setup), "--check"], env=env,
                               capture_output=True, text=True, timeout=25)
    assert completed.returncode == 0, (
        f"Jay preflight failed: {completed.stdout}\\n{completed.stderr}"
    )
    assert "PASS: Jay trial static stage" in completed.stdout
    assert not (config_home / "jay").exists(), "--check wrote Jay config"
    assert not (config_home / "quickshell/awtarchy-jay").exists(), "--check wrote generated QML"
    assert not (temp / "system").exists(), "--check touched system target"
print("PASS: Jay --check leaves config, Quickshell, and Ly destinations unchanged")
