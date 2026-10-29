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

# A newly selected app must not overwrite a different category that was
# temporarily uninstalled: keep the previously saved preference for later.
with tempfile.TemporaryDirectory(prefix="awtarchy-defaults-apply-") as tmp:
    with mock.patch.dict(os.environ, {"XDG_CONFIG_HOME": tmp}):
        installed = {"foot", "firefox", "pcmanfm-qt", "micro", "kitty"}
        with mock.patch.object(apps.shutil, "which",
                               side_effect=lambda app: app if app in installed else None):
            apps.set_default("terminal", "kitty")
            installed.remove("kitty")
            apps.set_default("browser", "firefox")
            assert apps.load() == {"terminal": "kitty", "browser": "firefox"}
            assert apps.effective("terminal", apps.load()) == "foot"
            try:
                apps.set_default("browser", "uninstalled-browser")
                raise AssertionError("Uninstalled application accepted")
            except ValueError:
                pass
            assert apps.load()["browser"] == "firefox"

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
        assert (19, "Up/Dn/Pg/Home/End/Wheel: Move") in visible
        assert (20, "Enter/Space/Right: Open  Left/B/Q/Esc: Back") in visible
        assert all(y < 18 for y, text in visible if "Browser " in text)

        # Drawing the main menu again restores the category view.
        apps.draw(screen, pending, {}, 1, 0, "main", "")
        visible = [(y, text) for y, x, text, attr in screen.rows]
        assert (1, "AWTARCHY DEFAULT APPLICATIONS") in visible
        assert any("Terminal" in text for y, text in visible)
        assert any("File Manager" in text for y, text in visible)
        assert not any("Browser 23" in text for y, text in visible)
        assert (19, "Up/Dn/Pg/Home/End/Wheel: Move") in visible
        assert (20, "Enter/Space/Right: Open  Left/B/Q/Esc: Back") in visible

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

# TUI keyboard/mouse tests emulate persistence, not merely staged changes.
class KeyboardScreen(FakeScreen):
    def __init__(self, keys):
        super().__init__()
        self.keys = iter(keys)

    def keypad(self, enabled):
        pass

    def getch(self):
        return next(self.keys)


installed_by_category = {
    "terminal": [("foot", "Foot"), ("kitty", "Kitty")],
    "browser": [("firefox", "Firefox"), ("chromium", "Chromium")],
    "file-manager": [("pcmanfm-qt", "PCManFM-Qt"), ("thunar", "Thunar")],
    "editor": [("micro", "Micro"), ("nvim", "Neovim")],
}


def run_navigation(keys, mouse_events=(), failing=False):
    screen = KeyboardScreen(keys)
    snapshots = []
    saved = {}
    writes = []
    events = iter(mouse_events)

    def read_state(path=None):
        return dict(saved)

    def persist(state, path=None):
        if failing:
            raise OSError("simulated write failure")
        saved.clear()
        saved.update(state)
        writes.append(dict(state))

    def capture(_screen, pending, _saved, cat, option, mode, notice,
                filter_text="", searching=False):
        snapshots.append((mode, cat, option, filter_text, searching,
                          dict(pending), notice))

    with mock.patch.object(apps, "load", side_effect=read_state), \
         mock.patch.object(apps, "save", side_effect=persist), \
         mock.patch.object(apps, "installed",
                           side_effect=lambda cat: installed_by_category[cat]), \
         mock.patch.object(apps, "draw", side_effect=capture), \
         mock.patch.object(apps, "setup_colors"), \
         mock.patch.object(apps, "setup_mouse"), \
         mock.patch.object(apps.curses, "mousemask"), \
         mock.patch.object(apps.curses, "curs_set"), \
         mock.patch.object(apps.curses, "noecho"), \
         mock.patch.object(apps.curses, "getmouse",
                           side_effect=lambda: next(events)):
        apps.tui(screen)
    return snapshots, writes, saved


def chosen(snapshots, category, value):
    return any(mode == "main" and state[category] == value
               for mode, _, _, _, _, state, _ in snapshots)


# Enter picks and persists immediately, returning to the category menu.
steps, writes, state = run_navigation([
    apps.curses.KEY_DOWN, 10, apps.curses.KEY_DOWN, 10, ord("b")])
assert any(row[0] == "choose" and row[1] == 1 for row in steps)
assert chosen(steps, "browser", "chromium")
assert writes == [{"browser": "chromium"}]
assert state["browser"] == "chromium"
assert any("saved" in row[6] for row in steps)

# Multiple category selections persist separately without any Save action.
steps, writes, state = run_navigation([
    apps.curses.KEY_DOWN, 10, apps.curses.KEY_DOWN, 10,
    apps.curses.KEY_HOME, 10, apps.curses.KEY_DOWN, 10, 27])
assert len(writes) == 2 and state == {
    "browser": "chromium", "terminal": "kitty"}
assert writes[0] == {"browser": "chromium"}
assert writes[1] == state

# The Tips-style search filters within the chooser. Selection saves on Enter.
steps, writes, state = run_navigation([
    apps.curses.KEY_DOWN, 10, ord("/"), *map(ord, "chrom"), 10, 10, 27])
assert any(row[0] == "choose" and row[3] == "chrom" for row in steps)
assert state == {"browser": "chromium"} and len(writes) == 1

# Mouse clicks select a category and immediately save the chosen application.
steps, writes, state = run_navigation(
    [apps.curses.KEY_MOUSE, apps.curses.KEY_MOUSE, 27],
    [(0, 4, 6, 0, apps.curses.BUTTON1_CLICKED),
     (0, 4, 5, 0, apps.curses.BUTTON1_CLICKED)])
assert chosen(steps, "browser", "chromium")
assert writes == [{"browser": "chromium"}]

# Space and Right both commit immediately, without requiring S or Enter.
for enter_key in (ord(" "), apps.curses.KEY_RIGHT):
    steps, writes, state = run_navigation([
        apps.curses.KEY_DOWN, enter_key,
        apps.curses.KEY_DOWN, enter_key, apps.curses.KEY_LEFT])
    assert chosen(steps, "browser", "chromium")
    assert writes == [{"browser": "chromium"}]

# Back in a chooser never writes. Esc, Q and B retain their navigation roles.
for back in (apps.curses.KEY_LEFT, ord("b"), ord("B"), ord("q"), 27):
    steps, writes, state = run_navigation([
        apps.curses.KEY_DOWN, apps.curses.KEY_RIGHT, back, ord("q")])
    assert not writes and not state
    assert any(mode == "main" for mode, *_ in steps)

# No S/save confirmation exists: S cannot trigger a write.
steps, writes, state = run_navigation([ord("s"), 27])
assert not writes and not state
assert all(row[0] != "review" for row in steps)

# Failure must leave the previous selected app in place and the chooser open.
steps, writes, state = run_navigation([
    apps.curses.KEY_DOWN, 10, apps.curses.KEY_DOWN, 10, 27, 27],
    failing=True)
assert not writes and not state
assert any(row[0] == "choose" and "Not changed:" in row[6] for row in steps)
assert not chosen(steps, "browser", "chromium")

# Search remains text input: b and Space do not accidentally select.
steps, writes, state = run_navigation([
    ord("/"), ord("b"), ord(" "), ord("q"), 10, ord("b")])
assert any(searching and query == "b q"
           for _, _, _, query, searching, _, _ in steps)
assert not writes and not state

# Left/Right inside a search cancel or finish typing, but never save.
steps, writes, state = run_navigation([
    ord("/"), ord("b"), ord(" "), apps.curses.KEY_LEFT,
    ord("/"), ord("e"), apps.curses.KEY_RIGHT, ord("b")])
assert any(searching and query == "b "
           for _, _, _, query, searching, _, _ in steps)
assert any(not searching and query == "e"
           for _, _, _, query, searching, _, _ in steps)
assert not writes

# Page navigation, search helper, and wheel support are retained.
assert apps.window_start(23, 24, 11) == 13
assert apps.window_start(3, 4, 11) == 0
assert apps.page_size(22, "choose") == 11
assert apps.page_size(22, "main") == 4
with mock.patch.object(apps, "installed",
                       return_value=[("firefox", "Firefox"),
                                     ("chromium", "Chromium")]):
    assert apps.menu_entries("choose", 1, "chrom") == [
        (1, "chromium", "Chromium")]
steps, writes, state = run_navigation([
    apps.curses.KEY_MOUSE, apps.curses.KEY_MOUSE,
    apps.curses.KEY_MOUSE, 10, 27],
    [(0, 1, 0, 0, apps.curses.BUTTON5_PRESSED),
     (0, 4, 6, 0, apps.curses.BUTTON1_CLICKED),
     (0, 1, 0, 0, apps.curses.BUTTON5_PRESSED)])
assert writes == [{"browser": "chromium"}]
assert state["browser"] == "chromium"

# UI contract: no pending selections or save/review screen.
code = SCRIPT.read_text(encoding="utf-8")
assert 'mode = "review"' not in code
assert 'mode == "review"' not in code
assert "Selection staged" not in code
assert 'Press S' not in code
assert "selection saves immediately" in code
assert 'set_default(category, app)' in code
assert 'execvp(selected, [selected, *args])' in code
assert "curses.wrapper(tui)" in code
assert (ROOT / "config/hypr/scripts/launch_handler.sh").exists()
assert (ROOT / "local/share/applications/awtarchy-default-applications.desktop").exists()

# Ensure the Python file compiles.
subprocess.run(["python3", "-m", "py_compile", str(SCRIPT)], check=True)
print("PASS: default applications save immediately on selection")
