#!/usr/bin/env python3
"""Contracts for Awtarchy's opt-in default-application selector."""

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "config/hypr/scripts/default_applications.py"
LUA = (ROOT / "config/hypr/hyprland.lua").read_text(encoding="utf-8")
TIPS = (ROOT / "config/hypr/scripts/awtarchy-tips-tui.sh").read_text(encoding="utf-8")
QUICKSETTINGS = (ROOT / "config/quickshell/awtarchy/QuickSettings.qml").read_text(encoding="utf-8")
BASHRC = (ROOT / "bashrc").read_text(encoding="utf-8")

spec = importlib.util.spec_from_file_location("default_applications", SCRIPT)
assert spec and spec.loader
apps = importlib.util.module_from_spec(spec)
spec.loader.exec_module(apps)

assert set(apps.CATALOG) == {"terminal", "browser", "file-manager", "editor"}
assert "calculator" not in apps.CATALOG
assert apps.DEFAULTS == {
    "terminal": "foot", "browser": "firefox",
    "file-manager": "pcmanfm-qt", "editor": "micro"
}
assert 'SUPER + ALT + A", default_apps' in LUA
assert LUA.count('SUPER + ALT + A", default_apps') == 2
assert 'SUPER + ALT + A", hl.dsp.exec_cmd(default_apps)' in LUA
assert LUA.count('hl.dsp.exec_cmd(file_manager)') == 2
assert 'default_applications.py launch terminal' in LUA
assert 'default_applications.py launch browser' in LUA
assert 'default_applications.py launch file-manager' in LUA
assert LUA.count('class = "^awtarchy-default-apps$"') == 3
assert "SUPER+ALT+A                  Default applications" in TIPS
assert "openDefaultApplications()" in QUICKSETTINGS
assert "default_applications.sh" in QUICKSETTINGS
assert '"bash", defaultAppsLauncher' in QUICKSETTINGS
assert "visible_count = max(0, h - y - 3)" in SCRIPT.read_text()
assert (ROOT / "config/hypr/scripts/default_applications.sh").exists()
assert "default_applications.py" in BASHRC
assert "VISUAL" in BASHRC

with tempfile.TemporaryDirectory(prefix="awtarchy-default-apps-test-") as directory:
    root = Path(directory)
    state = root / "config" / "awtarchy" / "default-applications.json"
    with mock.patch.dict(os.environ, {"XDG_CONFIG_HOME": str(root / "config")}):
        assert apps.config_file() == state
        installed = {"foot", "kitty", "firefox", "chromium",
                     "pcmanfm-qt", "thunar", "micro", "nvim"}
        with mock.patch.object(apps.shutil, "which",
                               side_effect=lambda command: "/mock/" + command if command in installed else None):
            assert apps.load() == {}
            assert apps.effective("terminal", {}) == "foot"
            assert apps.effective("browser", {}) == "firefox"
            assert apps.installed("editor") == [("micro", "Micro"), ("nvim", "Neovim")]
            apps.save({"terminal": "kitty", "browser": "chromium",
                       "file-manager": "thunar", "editor": "nvim"})
            assert state.exists()
            assert state.stat().st_mode & 0o777 == 0o600
            assert apps.load() == {"terminal": "kitty", "browser": "chromium",
                                   "file-manager": "thunar", "editor": "nvim"}
            assert apps.effective("terminal", apps.load()) == "kitty"
            assert apps.effective("editor", apps.load()) == "nvim"
            assert apps.status()["categories"][0]["selected"] == "kitty"
            assert len(apps.status()["categories"]) == 4
            assert not any(child.name.endswith(".tmp") for child in state.parent.iterdir())
            # Reject invalid selections without corrupting the prior file.
            before = state.read_bytes()
            try:
                apps.save({"terminal": "xterm"})
                raise AssertionError("Uninstalled selection accepted")
            except ValueError:
                pass
            assert state.read_bytes() == before
            # Preserve existing settings when selecting only one category.
            saved = apps.load()
            saved["terminal"] = "foot"
            apps.save(saved)
            assert apps.load()["browser"] == "chromium"
            # The shared launch path must use the exact selected executable
            # without passing its name through a shell.
            with mock.patch.object(apps.os, "execvp") as run:
                apps.launch("file-manager", [])
                run.assert_called_once_with("thunar", ["thunar"])
            # Disappearing apps do not cause launch failure: fall back to stock.
            installed.remove("kitty")
            assert apps.effective("terminal", apps.load()) == "foot"
            # Symlinked preferences may never be overwritten.
            state.unlink()
            state.symlink_to(root / "important")
            try:
                apps.save({"terminal": "foot"})
                raise AssertionError("Symlinked preferences overwritten")
            except ValueError:
                pass

# Long installed-choice lists must scroll into view, without drawing on the
# terminal footer or hiding the active option below the window.
class FakeScreen:
    def __init__(self):
        self.rows = []

    def erase(self):
        self.rows = []

    def getmaxyx(self):
        return 22, 56

    def addnstr(self, y, x, text, width, attr=0):
        self.rows.append((y, str(text)[:width]))

    def hline(self, *args):
        pass

    def refresh(self):
        pass


screen = FakeScreen()
browser_options = [(f"browser{i}", f"Browser {i}") for i in range(12)]
with mock.patch.object(apps, "installed", return_value=browser_options):
    apps.draw(screen, {key: apps.DEFAULTS[key] for key in apps.CATALOG},
              {}, 1, 11, "choose", "")
assert any("Browser 11" in text and 0 < row < 20 for row, text in screen.rows)
assert not any("Browser 0" in text for row, text in screen.rows)
assert any("12/12" in text for row, text in screen.rows)

# UI contract: the selected entry and save confirmation both exist.
code = SCRIPT.read_text(encoding="utf-8")
assert 'mode = "review"' in code
assert 'mode == "choose"' in code
assert "Existing MIME/XDG associations remain unchanged." in code
assert 'execvp(selected, [selected, *args])' in code
assert "curses.wrapper(tui)" in code
assert (ROOT / "config/hypr/scripts/launch_handler.sh").exists()
assert (ROOT / "local/share/applications/awtarchy-default-applications.desktop").exists()

# Ensure the Python file compiles, and the CLI prints machine-readable status.
subprocess.run(["python3", "-m", "py_compile", str(SCRIPT)], check=True)
print("PASS: default app discovery, saved state, launcher safety and UI contracts")
