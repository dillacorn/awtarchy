#!/usr/bin/env python3
"""KWin trial installation preserves both compositor profiles and user edits."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

SOURCE = Path(__file__).resolve().parents[1] / "trials/kwin/setup-trial.py"

with tempfile.TemporaryDirectory(prefix="kwin-install-test-") as temp:
    t = Path(temp)
    home = t / "home"
    home.mkdir(mode=0o700)
    (home / ".config/hypr").mkdir(parents=True)
    (home / ".config/sway").mkdir()
    (home / ".config/hypr/hyprland.lua").write_text("retain hypr\n")
    (home / ".config/sway/config").write_text("retain sway\n")
    env = dict(os.environ)
    env.update({"HOME": str(home),
                "XDG_DATA_HOME": str(home / ".local/share"),
                "XDG_STATE_HOME": str(home / ".local/state")})

    # CI can be run under root; only bypass this specific test copy.
    if os.geteuid() == 0:
        script = t / "setup-test.py"
        code = SOURCE.read_text().replace(
            "if os.geteuid() == 0:", "if False:")
        code = code.replace("source = Path(__file__).resolve().parent",
                            f"source = Path({str(SOURCE.parent)!r})")
        script.write_text(code)
    else:
        script = SOURCE

    def run(*args, ok=True):
        done = subprocess.run([sys.executable, str(script), *args],
                              env=env, capture_output=True, text=True, timeout=15)
        assert (done.returncode == 0) == ok, (
            args, done.returncode, done.stdout, done.stderr)
        return done

    staged = home / ".local/share/awtarchy-kwin-trial"
    shortcut = home / ".local/bin/kwin"
    manifest = home / ".local/state/awtarchy/kwin-trial-install.json"
    run("--plan")
    assert not staged.exists() and not shortcut.exists()
    run("--install")
    assert staged.joinpath("state-bridge.py").is_file()
    assert staged.joinpath("package/state-metadata.json").is_file()
    assert shortcut.is_file() and os.access(shortcut, os.X_OK)
    assert manifest.is_file()
    run("--install")
    assert (home / ".config/hypr/hyprland.lua").read_text() == "retain hypr\n"
    assert (home / ".config/sway/config").read_text() == "retain sway\n"

    # Customized shell survives both attempted reinstall and removal.
    changed = staged / "shell.qml"
    changed.write_text("custom ui\n")
    run("--install", ok=False)
    run("--remove")
    assert changed.read_text() == "custom ui\n"
    assert manifest.exists()
    assert not shortcut.exists()
    assert (home / ".config/sway/config").read_text() == "retain sway\n"

    # Do not claim ownership of a preexisting command.
    home2 = t / "home2"
    (home2 / ".local/bin").mkdir(parents=True)
    (home2 / ".local/bin/kwin").write_text("custom command\n")
    env.update({"HOME": str(home2),
                "XDG_DATA_HOME": str(home2 / ".local/share"),
                "XDG_STATE_HOME": str(home2 / ".local/state")})
    run("--plan", ok=False)
    run("--install", ok=False)
    assert (home2 / ".local/bin/kwin").read_text() == "custom command\n"

print("PASS: KWin trial install, collision checks, exact removal, desktop preservation")
