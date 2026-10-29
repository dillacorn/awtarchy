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


def menu_entries(mode: str, category_index: int,
                 query: str) -> list[tuple[int, str, str]]:
    """Indices retain their identity while filtering, like Awtarchy Tips."""
    if mode == "choose":
        category = list(CATALOG)[category_index]
        items = installed(category)
    else:
        items = [(key, LABELS[key]) for key in CATALOG]
    needle = query.casefold()
    return [(i, app, display) for i, (app, display) in enumerate(items)
            if needle in display.casefold() or needle in app.casefold()]


def current_position(entries: list[tuple[int, str, str]],
                     original_index: int) -> int:
    return next((i for i, (index, _, _) in enumerate(entries)
                 if index == original_index), 0)


def window_start(position: int, total: int, capacity: int) -> int:
    """Keep the highlighted item visible and centered, as Awtarchy Tips does."""
    if total <= capacity:
        return 0
    return max(0, min(position - capacity // 2, total - capacity))


def page_size(height: int, mode: str) -> int:
    return max(1, height - 11) if mode == "choose" else len(CATALOG)


def draw(stdscr: curses.window, pending: dict[str, str], saved: dict[str, str],
         category_index: int, option_index: int, mode: str, notice: str,
         filter_text: str = "", searching: bool = False) -> None:
    """Use Foot's colors and display one menu at a time."""
    stdscr.erase()
    h, w = stdscr.getmaxyx()
    if h < 17 or w < 40:
        put(stdscr, 1, 2, "Resize Default Applications", max(w - 3, 1))
        stdscr.refresh()
        return

    width = w - 4
    categories = list(CATALOG)
    category = categories[category_index]
    title = ("DEFAULT " + LABELS[category].upper() if mode == "choose"
             else "REVIEW DEFAULT APPLICATIONS" if mode == "review"
             else "AWTARCHY DEFAULT APPLICATIONS")
    put(stdscr, 1, 2, title, width, curses.A_BOLD)
    try:
        stdscr.hline(2, 2, curses.ACS_HLINE, width)
    except curses.error:
        pass

    if mode == "review":
        changed = [(key, pending.get(key, "")) for key in categories
                   if pending.get(key, "") != effective(key, saved)]
        for i, (key, app) in enumerate(changed[:max(0, h - 9)]):
            put(stdscr, 4 + i, 2, f"{LABELS[key]}: {label(key, app)}", width)
        put(stdscr, h - 6, 2, "Apply these launcher preferences?",
            width, curses.A_BOLD)
        put(stdscr, h - 5, 2, "MIME and XDG settings are unchanged.",
            width, curses.A_DIM)
        put(stdscr, h - 2, 2, "Enter: Save   Left/B/Q/Esc: Back", width, curses.A_DIM)
        stdscr.refresh()
        return

    entries = menu_entries(mode, category_index, filter_text)
    selected_index = option_index if mode == "choose" else category_index
    position = current_position(entries, selected_index)
    if mode == "choose":
        capacity = page_size(h, mode)
        first = window_start(position, len(entries), capacity)
        for offset, (_, app, display) in enumerate(entries[first:first + capacity]):
            idx = first + offset
            selected = "  (current)" if app == pending.get(category, "") else ""
            put(stdscr, 4 + offset, 2,
                ("> " if idx == position else "  ") + display + selected,
                width, curses.A_REVERSE if idx == position else 0)
        if not entries:
            put(stdscr, 4, 2, "No matches. Press / to search or c to clear.", width)
        put(stdscr, h - 6, 2,
            f"Choice {position + 1}/{len(entries)}" if entries else "No matching apps",
            width, curses.A_DIM)
    else:
        for idx, (original_idx, app, display) in enumerate(entries):
            y = 4 + idx * 2
            selected = pending.get(app, "")
            changed = selected != effective(app, saved)
            row = (("> " if idx == position else "  ")
                   + f"{display:<15} "
                   + (label(app, selected) if selected else "(unavailable)"))
            if changed:
                row += " *"
            put(stdscr, y, 2, row, width,
                curses.A_REVERSE if idx == position else 0)
        if not entries:
            put(stdscr, 4, 2, "No matches. Press / to search or c to clear.", width)

    hint = ("/ Find  c Clear  S Save" if mode == "main"
            else "/ Find  c Clear")
    info = ("Search: " + filter_text + ("_" if searching else "")
            if searching or filter_text else notice or hint)
    put(stdscr, h - 5, 2, info, width, curses.A_DIM)
    # Two compact help lines avoid truncation in floating Foot windows.
    put(stdscr, h - 3, 2, "Up/Dn/Pg/Home/End/Wheel Move", width,
        curses.A_DIM)
    put(stdscr, h - 2, 2, "Enter/Space/Right  Left/B/Q/Esc Back",
        width, curses.A_DIM)
    stdscr.refresh()


def setup_colors(stdscr: curses.window) -> None:
    """Honor Foot's foreground/background, including transparency."""
    if not curses.has_colors():
        return
    curses.start_color()
    try:
        curses.use_default_colors()
        curses.init_pair(1, -1, -1)
        stdscr.bkgd(" ", curses.color_pair(1))
    except curses.error:
        pass


def setup_mouse() -> None:
    """Use ncurses' SGR mouse translation, as Foot supports xterm mouse input."""
    try:
        curses.mouseinterval(150)
        curses.mousemask(curses.BUTTON1_CLICKED | curses.BUTTON1_DOUBLE_CLICKED
                         | curses.BUTTON4_PRESSED | curses.BUTTON5_PRESSED)
    except (curses.error, AttributeError):
        pass


def mouse_action(stdscr: curses.window, mode: str, category_index: int,
                 option_index: int, filter_text: str) -> tuple[str, int] | None:
    """Turn clicks or wheel into a menu action. Header/footer are not active."""
    try:
        _, x, y, _, state = curses.getmouse()
    except (curses.error, ValueError):
        return None
    if state & curses.BUTTON4_PRESSED:
        return ("move", -1)
    if state & curses.BUTTON5_PRESSED:
        return ("move", 1)
    if not state & (curses.BUTTON1_CLICKED | curses.BUTTON1_DOUBLE_CLICKED):
        return None

    h, w = stdscr.getmaxyx()
    if x < 2 or x >= w - 1 or y < 4 or y >= h - 6:
        return None

    entries = menu_entries(mode, category_index, filter_text)
    if mode == "choose":
        position = current_position(entries, option_index)
        first = window_start(position, len(entries), page_size(h, mode))
        clicked = first + y - 4
        if 0 <= clicked < len(entries) and y < 4 + page_size(h, mode):
            return ("select", entries[clicked][0])
    elif mode == "main" and (y - 4) % 2 == 0:
        clicked = (y - 4) // 2
        if 0 <= clicked < len(entries):
            return ("select", entries[clicked][0])
    return None


def tui(stdscr: curses.window) -> None:
    try:
        curses.curs_set(0)
    except curses.error:
        pass
    curses.noecho()
    stdscr.keypad(True)
    setup_colors(stdscr)
    setup_mouse()

    saved = load()
    pending = {category: effective(category, saved) for category in CATALOG}
    categories = list(CATALOG)
    category_index = 0
    option_index = 0
    mode = "main"
    notice = ""
    # Search applies to the current menu only; returning to the category list
    # restores its own filter, just as Awtarchy Tips remembers menu selections.
    filters: dict[str, str] = {"main": ""}
    searching = False
    previous_filter = ""

    def select_item(selected: int) -> None:
        nonlocal category_index, option_index, mode, notice, searching
        if mode == "main":
            category_index = selected
            choices_for_category = installed(categories[category_index])
            if not choices_for_category:
                notice = "No supported installed apps for this category."
                return
            option_index = next(
                (i for i, (name, _) in enumerate(choices_for_category)
                 if name == pending[categories[category_index]]), 0)
            mode = "choose"
            searching = False
        elif mode == "choose":
            apps = installed(categories[category_index])
            if 0 <= selected < len(apps):
                pending[categories[category_index]] = apps[selected][0]
                option_index = selected
                mode = "main"
                searching = False
                notice = "Selection staged. Press S to review and save."

    try:
        while True:
            key_filter = "main" if mode == "main" else categories[category_index]
            filter_text = filters.get(key_filter, "")
            entries = menu_entries(mode, category_index, filter_text) \
                if mode != "review" else []
            selected_index = option_index if mode == "choose" else category_index
            if entries and not any(i == selected_index for i, _, _ in entries):
                if mode == "choose":
                    option_index = entries[0][0]
                else:
                    category_index = entries[0][0]
            draw(stdscr, pending, saved, category_index, option_index, mode,
                 notice, filter_text, searching)
            key = stdscr.getch()

            if searching:
                if key in (10, 13, curses.KEY_ENTER):
                    searching = False
                elif key == 27:
                    filters[key_filter] = previous_filter
                    searching = False
                elif key in (curses.KEY_BACKSPACE, 8, 127):
                    filters[key_filter] = filter_text[:-1]
                elif 32 <= key <= 126 and len(filter_text) < 80:
                    filters[key_filter] = filter_text + chr(key)
                continue

            if key == curses.KEY_RESIZE:
                continue
            if key in (27, curses.KEY_LEFT, ord("q"), ord("Q"),
                       ord("b"), ord("B")):
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

            move = 0
            clicked: int | None = None
            if key == curses.KEY_MOUSE:
                action = mouse_action(stdscr, mode, category_index,
                                      option_index, filter_text)
                if action is None:
                    continue
                if action[0] == "move":
                    move = action[1]
                else:
                    clicked = action[1]
            elif key in (curses.KEY_UP, ord("k"), ord("K")):
                move = -1
            elif key in (curses.KEY_DOWN, ord("j"), ord("J")):
                move = 1
            elif key == curses.KEY_PPAGE:
                move = -page_size(stdscr.getmaxyx()[0], mode)
            elif key == curses.KEY_NPAGE:
                move = page_size(stdscr.getmaxyx()[0], mode)
            elif key in (curses.KEY_HOME, ord("g")):
                move = -len(entries)
            elif key in (curses.KEY_END, ord("G")):
                move = len(entries)
            elif key == ord("/"):
                previous_filter = filter_text
                searching = True
                continue
            elif key in (ord("c"), ord("C")):
                filters[key_filter] = ""
                continue
            elif key in (10, 13, 32, curses.KEY_ENTER, curses.KEY_RIGHT):
                if entries:
                    clicked = (option_index if mode == "choose" else category_index)
            elif mode == "main" and key in (ord("s"), ord("S")):
                if any(pending[k] != effective(k, saved) for k in CATALOG):
                    mode = "review"
                else:
                    notice = "No changes to save."

            if move and entries:
                old = current_position(
                    entries, option_index if mode == "choose" else category_index)
                index = entries[max(0, min(len(entries) - 1, old + move))][0]
                if mode == "choose":
                    option_index = index
                else:
                    category_index = index
            elif clicked is not None:
                select_item(clicked)
    finally:
        try:
            curses.mousemask(0)
        except (curses.error, AttributeError):
            pass


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
            save({key: effective(key, saved) for key in CATALOG
                  if effective(key, saved)})
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
