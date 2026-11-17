#!/usr/bin/env python3
"""Offline tests: update existing KWin trial or install after aborted pacman."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

SOURCE = Path(__file__).resolve().parents[1] / "trials/kwin"

with tempfile.TemporaryDirectory(prefix="kwin-update-test-") as temp:
    base = Path(temp)
    fixture = base / "src"
    shutil.copytree(SOURCE, fixture)
    if os.geteuid() == 0:
        setup = fixture / "setup-trial.py"
        setup.write_text(setup.read_text().replace(
            "if os.geteuid() == 0:", "if False:"))
    home = base / "home"
    home.mkdir(mode=0o700)
    env = dict(os.environ)
    env.update({"HOME": str(home),
                "XDG_DATA_HOME": str(home / ".local/share"),
                "XDG_STATE_HOME": str(home / ".local/state")})

    def run(*args, ok=True):
        proc = subprocess.run(
            [sys.executable, str(fixture / "setup-trial.py"), *args],
            env=env, text=True, capture_output=True, timeout=20)
        assert (proc.returncode == 0) == ok, (
            args, proc.returncode, proc.stdout, proc.stderr)
        return proc

    dest = home / ".local/share/awtarchy-kwin-trial"
    state = home / ".local/state/awtarchy"
    # The --update operation also handles a user whose earlier pacman
    # transaction aborted before any trial files were installed.
    run("--update")
    assert dest.joinpath("tty-smoke.sh").is_file()
    original = dest.joinpath("tty-smoke.sh").read_bytes()

    # A staged-but-not-customized installation can be safely refreshed.
    (fixture / "tty-smoke.sh").write_bytes(original + b"\n# Ly upgrade\n")
    proc = run("--update")
    assert "Updated 1 exact KWin trial file(s)" in proc.stdout
    assert dest.joinpath("tty-smoke.sh").read_bytes().endswith(b"# Ly upgrade\n")
    backup = list(state.glob("kwin-trial-upgrade-*"))
    assert len(backup) == 1
    assert backup[0].joinpath("000.original").read_bytes() == original
    manifest = json.loads(state.joinpath("kwin-trial-install.json").read_text())
    assert str(dest / "tty-smoke.sh") in manifest["files"]
    run("--update")
    assert len(list(state.glob("kwin-trial-upgrade-*"))) == 1

    # Never replace a user edit; fail before creating any additional backup.
    dest.joinpath("tty-smoke.sh").write_text("custom session\n")
    (fixture / "tty-smoke.sh").write_text("next update\n")
    run("--update", ok=False)
    assert dest.joinpath("tty-smoke.sh").read_text() == "custom session\n"
    assert len(list(state.glob("kwin-trial-upgrade-*"))) == 1

print("PASS: KWin trial update, fresh install, backups, modified-file refusal")
