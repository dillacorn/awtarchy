#!/usr/bin/env python3
"""Awtarchy-owned default-app preferences and a small terminal selector.

Preferences live in ~/.config/awtarchy/default-applications.json, outside
the updater-managed tree. No global MIME associations are modified.
"""

from __future__ import annotations

import argparse
import curses
import json
import os
from pathlib import Path
import shutil
import stat
import sys
import tempfile

CATALOG = {
    "terminal": [
        ("foot", "Foot"),
        ("kitty", "Kitty"),
        ("alacritty", "Alacritty"),
        ("wezterm", "WezTerm"),
        ("konsole", "Konsole"),
        ("gnome-terminal", "GNOME Terminal"),
        ("xfce4-terminal", "Xfce Terminal"),
    ],
    "browser": [
        ("firefox", "Firefox"),
        ("librewolf", "LibreWolf"),
        ("chromium", "Chromium"),
        ("brave", "Brave"),
        ("brave-browser", "Brave Browser"),
        ("google-chrome-stable", "Google Chrome"),
        ("google-chrome", "Google Chrome"),
        ("vivaldi-stable", "Vivaldi"),
        ("vivaldi", "Vivaldi"),
        ("zen-browser", "Zen"),
        ("floorp", "Floorp"),
        ("falkon", "Falkon"),
    ],
    "file-manager": [
        ("pcmanfm-qt", "PCManFM-Qt"),
        ("thunar", "Thunar"),
        ("dolphin", "Dolphin"),
        ("nautilus", "GNOME Files"),
        ("nemo", "Nemo"),
        ("pcmanfm", "PCManFM"),
    ],
    "editor": [
        ("micro", "Micro"),
        ("nvim", "Neovim"),
        ("vim", "Vim"),
        ("nano", "Nano"),
        ("emacs", "Emacs"),
        ("helix", "Helix"),
        ("hx", "Helix"),
    ],
}
LABELS = {
    "terminal": "Terminal",
    "browser": "Web Browser",
    "file-manager": "File Manager",
    "editor": "Text Editor",
}
DEFAULTS = {
    "terminal": "foot",
    "browser": "firefox",
    "file-manager": "pcmanfm-qt",
    "editor": "micro",
}


def config_file() -> Path:
    base = os.environ.get("XDG_CONFIG_HOME")
    return (Path(base).expanduser() if base else Path.home() / ".config") / "awtarchy" / "default-applications.json"


def safe_state_path(path: Path) -> None:
    if path.parent.is_symlink() or path.is_symlink():
        raise ValueError("Refusing symlinked preferences path")
    if path.exists() and not path.is_file():
        raise ValueError("Preferences path is not a regular file")


def installed(category: str) -> list[tuple[str, str]]:
    return [(name, label) for name, label in CATALOG[category]
            if shutil.which(name) is not None]


def choices(category: str) -> list[str]:
    return [name for name, _ in installed(category)]


def load(path: Path | None = None) -> dict[str, str]:
    path = path or config_file()
    safe_state_path(path)
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return {}
    if not isinstance(data, dict):
        raise ValueError("Invalid preferences structure")
    return {key: value for key, value in data.items()
            if key in CATALOG and isinstance(value, str)
            and value in {item[0] for item in CATALOG[key]}}


def effective(category: str, saved: dict[str, str]) -> str:
    available = choices(category)
    current = saved.get(category, DEFAULTS[category])
    if current in available:
        return current
    if DEFAULTS[category] in available:
        return DEFAULTS[category]
    return available[0] if available else ""


def save(prefs: dict[str, str], path: Path | None = None) -> None:
    path = path or config_file()
    safe_state_path(path)
    for category, name in prefs.items():
        if category not in CATALOG or name not in choices(category):
            raise ValueError(f"Unavailable {category}: {name}")
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    safe_state_path(path)
    raw = (json.dumps(prefs, indent=2, sort_keys=True) + "\n").encode("utf-8")
    fd, tmp = tempfile.mkstemp(prefix=".default-applications-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as f:
            os.fchmod(f.fileno(), 0o600)
            f.write(raw)
            f.flush()
            os.fsync(f.fileno())
        safe_state_path(path)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def label(category: str, app: str) -> str:
    return next((name for executable, name in CATALOG[category]
                 if executable == app), app)


def launch(category: str, args: list[str]) -> None:
    if category not in CATALOG:
        raise ValueError(f"Unknown category: {category}")
    selected = effective(category, load())
    if not selected:
        raise ValueError(f"No supported {LABELS[category]} is installed")
    os.execvp(selected, [selected, *args])


def status() -> dict[str, object]:
    prefs = load()
    return {
        "categories": [
            {
                "id": key,
                "label": LABELS[key],
                "selected": effective(key, prefs),
                "saved": prefs.get(key, ""),
                "missing": bool(prefs.get(key) and prefs[key] not in choices(key)),
                "choices": [
                    {"id": app, "label": display}
                    for app, display in installed(key)
                ],
            }
            for key in CATALOG
        ]
    }


def put(stdscr: curses.window, y: int, x: int, value: str,
        width: int, attr: int = 0) -> None:
    if width < 1:
        return
    try:
        stdscr.addnstr(y, x, value, width, attr)
    except curses.error:
        pass


def draw(stdscr: curses.window, pending: dict[str, str], saved: dict[str, str],
         category_index: int, option_index: int, mode: str, notice: str) -> None:
    stdscr.erase()
    h, w = stdscr.getmaxyx()
    if h < 14 or w < 35:
        put(stdscr, 1, 2, "Resize Default Applications", max(w - 3, 1))
        stdscr.refresh()
        return
    width = w - 4
    put(stdscr, 1, 2, "AWTARCHY DEFAULT APPLICATIONS", width, curses.A_BOLD)
    stdscr.hline(2, 2, curses.ACS_HLINE, width)
    keys = list(CATALOG)
    for idx, category in enumerate(keys):
        y = 4 + idx * 2
        app = pending.get(category, "")
        is_changed = app != effective(category, saved)
        marker = "> " if idx == category_index else "  "
        text = f"{marker}{LABELS[category]:<15} {label(category, app) if app else '(unavailable)'}"
        if is_changed:
            text += " *"
        put(stdscr, y, 2, text, width,
            curses.A_REVERSE if idx == category_index and mode == "main" else 0)
    y = 4 + len(keys) * 2 + 1
    if mode == "choose":
        category = keys[category_index]
        options = installed(category)
        put(stdscr, y, 2, f"Choose {LABELS[category]}:", width, curses.A_BOLD)
        for i, (_, app_label) in enumerate(options[:max(0, h - y - 4)]):
            put(stdscr, y + 1 + i, 4, ("> " if i == option_index else "  ") + app_label,
                width - 2, curses.A_REVERSE if i == option_index else 0)
        help_text = "Enter: Choose   Esc: Back"
    elif mode == "review":
        put(stdscr, y, 2, "Apply Awtarchy launcher defaults?", width, curses.A_BOLD)
        put(stdscr, y + 1, 2, "Existing MIME/XDG associations remain unchanged.", width)
        help_text = "Enter: Apply   Esc: Cancel"
    else:
        put(stdscr, y, 2, notice, width, curses.A_DIM)
        help_text = "Enter: Choose   S: Review/Save   Esc: Close"
    put(stdscr, h - 2, 2, help_text, width, curses.A_DIM)
    stdscr.refresh()


def tui(stdscr: curses.window) -> None:
    curses.curs_set(0)
    curses.noecho()
    stdscr.keypad(True)
    saved = load()
    pending = {category: effective(category, saved) for category in CATALOG}
    keys = list(CATALOG)
    category_index = 0
    option_index = 0
    mode = "main"
    notice = ""
    while True:
        draw(stdscr, pending, saved, category_index, option_index, mode, notice)
        key = stdscr.getch()
        if key in (27,):
            if mode == "main":
                return
            mode = "main"
            continue
        if mode == "review":
            if key in (10, 13, curses.KEY_ENTER):
                try:
                    save({category: app for category, app in pending.items() if app})
                    saved = load()
                    notice = "Saved. New launcher shortcuts use these defaults."
                except (OSError, ValueError) as exc:
                    notice = f"Not saved: {exc}"
                mode = "main"
            continue
        if mode == "choose":
            category = keys[category_index]
            apps = installed(category)
            if key in (curses.KEY_UP, ord("k")):
                option_index = max(0, option_index - 1)
            elif key in (curses.KEY_DOWN, ord("j")):
                option_index = min(len(apps) - 1, option_index + 1)
            elif key in (10, 13, curses.KEY_ENTER) and apps:
                pending[category] = apps[option_index][0]
                mode = "main"
            continue
        if key in (curses.KEY_UP, ord("k")):
            category_index = (category_index - 1) % len(keys)
        elif key in (curses.KEY_DOWN, ord("j")):
            category_index = (category_index + 1) % len(keys)
        elif key in (10, 13, curses.KEY_ENTER):
            options = installed(keys[category_index])
            if not options:
                notice = "No supported installed apps found for this category."
            else:
                option_index = next(
                    (i for i, (name, _) in enumerate(options)
                     if name == pending[keys[category_index]]), 0
                )
                mode = "choose"
        elif key in (ord("s"), ord("S")):
            if any(pending[k] != effective(k, saved) for k in CATALOG):
                mode = "review"
            else:
                notice = "No changes to save."


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    get = sub.add_parser("get")
    get.add_argument("category", choices=list(CATALOG))
    choose = sub.add_parser("set")
    choose.add_argument("category", choices=list(CATALOG))
    choose.add_argument("app")
    launch_command = sub.add_parser("launch")
    launch_command.add_argument("category", choices=list(CATALOG))
    launch_command.add_argument("arguments", nargs=argparse.REMAINDER)
    sub.add_parser("status")
    sub.add_parser("tui")
    args = parser.parse_args()
    try:
        if args.action == "get":
            print(effective(args.category, load()))
        elif args.action == "set":
            saved = load()
            if args.app not in choices(args.category):
                raise ValueError(f"{args.app} is not an installed supported {args.category}")
            saved[args.category] = args.app
            save(saved)
            print(f"{LABELS[args.category]}: {label(args.category, args.app)}")
        elif args.action == "launch":
            launch(args.category, args.arguments)
        elif args.action == "status":
            print(json.dumps(status(), separators=(",", ":")))
        elif args.action == "tui":
            curses.wrapper(tui)
    except (OSError, ValueError) as exc:
        print(f"default applications: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
