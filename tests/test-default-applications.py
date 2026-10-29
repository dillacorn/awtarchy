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
assert "setup_colors(stdscr)" in SCRIPT.read_text()
assert "setup_mouse()" in SCRIPT.read_text()
assert "page_size(height: int, mode: str)" in SCRIPT.read_text()
assert "menu_entries(mode: str, category_index: int," in SCRIPT.read_text()
assert "size = { 540, 460 }" in LUA
assert 'label: "apps"' in QUICKSETTINGS
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

# The category chooser occupies its own page, never overlapping the main
# categories. The selected entry must stay visible with a full-height list.
class FakeScreen:
    def __init__(self, h=22, w=56):
        self.h, self.w = h, w
        self.rows = []
        self.color = None

    def erase(self):
        self.rows = []

    def getmaxyx(self):
        return self.h, self.w

    def addnstr(self, y, x, text, width, attr=0):
        self.rows.append((y, x, str(text)[:width], attr))

    def hline(self, *args):
        pass

    def bkgd(self, text, attr):
        self.color = (text, attr)

    def refresh(self):
        pass


pending = apps.DEFAULTS.copy()
screen = FakeScreen()
options = [(f"browser{i}", f"Browser {i}") for i in range(24)]
with mock.patch.object(apps.curses, "ACS_HLINE", ord("-"), create=True):
    with mock.patch.object(apps, "installed", return_value=options):
        apps.draw(screen, pending, {}, 1, 23, "choose", "")
        visible = [(y, text) for y, x, text, attr in screen.rows]
        assert (1, "DEFAULT WEB BROWSER") in visible
        assert any("Browser 23" in text and 4 <= y <= 17 for y, text in visible)
        assert not any("Browser 0" in text for y, text in visible)
        assert not any("PCManFM-Qt" in text for y, text in visible)
        assert (16, "Choice 24/24") in visible
        assert (19, "Up/Dn/Wheel Move  Enter/Click Open") in visible
        assert (20, "Pg/Home/End /Find c Clear Esc/q Back") in visible
        assert all(y < 18 for y, text in visible if "Browser " in text)

        # Drawing the main menu again restores the category view.
        apps.draw(screen, pending, {}, 1, 0, "main", "")
        visible = [(y, text) for y, x, text, attr in screen.rows]
        assert (1, "AWTARCHY DEFAULT APPLICATIONS") in visible
        assert any("Terminal" in text for y, text in visible)
        assert any("File Manager" in text for y, text in visible)
        assert not any("Browser 23" in text for y, text in visible)
        assert (19, "Up/Dn/Wheel Move  Enter/Click Open") in visible
        assert (20, "Pg/Home/End /Find c Clear Esc/q Back") in visible

        # A too-small viewport displays the resize prompt instead of clipping.
        small = FakeScreen(15, 34)
        apps.draw(small, pending, {}, 1, 0, "main", "")
        assert any("Resize Default Applications" in text
                   for y, x, text, attr in small.rows)

# Curses must use the terminal's actual colors, not an opaque black backdrop.
with mock.patch.object(apps.curses, "has_colors", return_value=True), \
     mock.patch.object(apps.curses, "start_color") as start_color, \
     mock.patch.object(apps.curses, "use_default_colors") as use_defaults, \
     mock.patch.object(apps.curses, "init_pair") as init_pair, \
     mock.patch.object(apps.curses, "color_pair", return_value=17):
    apps.setup_colors(screen)
    start_color.assert_called_once_with()
    use_defaults.assert_called_once_with()
    init_pair.assert_called_once_with(1, -1, -1)
    assert screen.color == (" ", 17)

# Enter opens a focused choice page; Enter on an application returns to the
# category page with a pending change. Esc exits without persisting it.
class KeyboardScreen(FakeScreen):
    def __init__(self, keys):
        super().__init__()
        self.keys = iter(keys)

    def keypad(self, enabled):
        pass

    def getch(self):
        return next(self.keys)


keyboard = KeyboardScreen([apps.curses.KEY_DOWN, 10,
                           apps.curses.KEY_DOWN, 10, 27])
renders = []
installed_by_category = {
    "terminal": [("foot", "Foot")],
    "browser": [("firefox", "Firefox"), ("chromium", "Chromium")],
    "file-manager": [("pcmanfm-qt", "PCManFM-Qt")],
    "editor": [("micro", "Micro")],
}


def record_draw(_screen, pending, _saved, category_idx, option_idx, mode, _notice,
                _filter_text="", _searching=False):
    renders.append((mode, category_idx, dict(pending)))


with mock.patch.object(apps, "load", return_value={}), \
     mock.patch.object(apps, "installed",
                       side_effect=lambda category: installed_by_category[category]), \
     mock.patch.object(apps, "draw", side_effect=record_draw), \
     mock.patch.object(apps, "setup_colors"), \
     mock.patch.object(apps, "setup_mouse"), \
     mock.patch.object(apps.curses, "mousemask"), \
     mock.patch.object(apps.curses, "curs_set"), \
     mock.patch.object(apps.curses, "noecho"), \
     mock.patch.object(apps, "save") as save_preferences:
    apps.tui(keyboard)
    save_preferences.assert_not_called()
assert any(mode == "choose" and category_idx == 1 for mode, category_idx, _ in renders)
assert any(mode == "main" and prefs["browser"] == "chromium"
           for mode, _, prefs in renders)

# Tips-style paging, indexed filtering, and wheel/click targeting.
assert apps.window_start(23, 24, 11) == 13
assert apps.window_start(3, 4, 11) == 0
assert apps.page_size(22, "choose") == 11
assert apps.page_size(22, "main") == 4
with mock.patch.object(apps, "installed",
                       return_value=[("firefox", "Firefox"),
                                     ("chromium", "Chromium")]):
    assert apps.menu_entries("choose", 1, "chrom") == [
        (1, "chromium", "Chromium")]
    assert apps.current_position([(1, "chromium", "Chromium")], 1) == 0


def run_navigation(keys, mouse_events=()):
    screen = KeyboardScreen(keys)
    snapshots = []

    def capture(_screen, pending, _saved, cat, option, mode,
                _notice, filter_text="", searching=False):
        snapshots.append((mode, cat, option, filter_text, searching,
                          dict(pending)))

    events = iter(mouse_events)
    with mock.patch.object(apps, "load", return_value={}), \
         mock.patch.object(apps, "installed",
                           side_effect=lambda cat: installed_by_category[cat]), \
         mock.patch.object(apps, "draw", side_effect=capture), \
         mock.patch.object(apps, "setup_colors"), \
         mock.patch.object(apps, "setup_mouse"), \
         mock.patch.object(apps.curses, "mousemask"), \
         mock.patch.object(apps.curses, "curs_set"), \
         mock.patch.object(apps.curses, "noecho"), \
         mock.patch.object(apps.curses, "getmouse",
                           side_effect=lambda: next(events)), \
         mock.patch.object(apps, "save") as do_save:
        apps.tui(screen)
        do_save.assert_not_called()
    return snapshots


search_steps = run_navigation([
    apps.curses.KEY_DOWN, 10, ord("/"),
    *map(ord, "chrom"), 10, 10, 27])
assert any(mode == "choose" and query == "chrom"
           for mode, _, _, query, _, _ in search_steps)
assert any(mode == "main" and state["browser"] == "chromium"
           for mode, _, _, _, _, state in search_steps)

# Clicking a category opens its own choices page; clicking an app returns.
clicked = run_navigation(
    [apps.curses.KEY_MOUSE, apps.curses.KEY_MOUSE, 27],
    [(0, 4, 6, 0, apps.curses.BUTTON1_CLICKED),
     (0, 4, 5, 0, apps.curses.BUTTON1_CLICKED)])
assert any(mode == "choose" and cat == 1 for mode, cat, _, _, _, _ in clicked)
assert any(mode == "main" and state["browser"] == "chromium"
           for mode, _, _, _, _, state in clicked)

# Mouse wheel changes the focused row, not the application preference.
wheel = run_navigation(
    [apps.curses.KEY_MOUSE, apps.curses.KEY_MOUSE,
     apps.curses.KEY_MOUSE, 10, 27],
    [(0, 1, 0, 0, apps.curses.BUTTON5_PRESSED),
     (0, 4, 6, 0, apps.curses.BUTTON1_CLICKED),
     (0, 1, 0, 0, apps.curses.BUTTON5_PRESSED)])
assert any(mode == "main" and cat == 1 for mode, cat, _, _, _, _ in wheel)
assert any(mode == "main" and state["browser"] == "chromium"
           for mode, _, _, _, _, state in wheel)

# PgUp/PgDn/Home/End are available on both screens and q acts like Esc.
page = run_navigation([
    apps.curses.KEY_END, 10, ord("q"),
    apps.curses.KEY_HOME, 10, 27, 27])
assert any(mode == "choose" and cat == 3 for mode, cat, _, _, _, _ in page)
assert any(mode == "choose" and cat == 0 for mode, cat, _, _, _, _ in page)

# Search cancellation restores the prior menu filter, and c clears it.
search_back = run_navigation([
    ord("/"), *map(ord, "browser"), 27, ord("/"),
    *map(ord, "editor"), 10, ord("c"), 27])
assert any(mode == "main" and query == "browser" and searching
           for mode, _, _, query, searching, _ in search_back)
assert any(mode == "main" and query == "" and not searching
           for mode, _, _, query, searching, _ in search_back)

# UI contract: the selected entry and save confirmation both exist.
code = SCRIPT.read_text(encoding="utf-8")
assert 'mode = "review"' in code
assert 'mode == "choose"' in code
assert "MIME and XDG settings are unchanged." in code
assert 'execvp(selected, [selected, *args])' in code
assert "curses.wrapper(tui)" in code
assert (ROOT / "config/hypr/scripts/launch_handler.sh").exists()
assert (ROOT / "local/share/applications/awtarchy-default-applications.desktop").exists()

# Ensure the Python file compiles, and the CLI prints machine-readable status.
subprocess.run(["python3", "-m", "py_compile", str(SCRIPT)], check=True)
print("PASS: default app discovery, saved state, launcher safety and UI contracts")
