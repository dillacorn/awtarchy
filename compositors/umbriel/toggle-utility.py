#!/usr/bin/env python3
"""Toggle only matching Umbriel floating utilities; never kill tiled windows."""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys

CONFIG = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
SCRIPTS = CONFIG / "hypr/scripts"
UTILITIES = {
    "btop": (("btop",), ("foot", "--app-id", "btop", "--title", "btop", "btop"), False),
    "maccel": (("maccel",), ("foot", "--app-id", "maccel", "maccel", "tui"), False),
    "wiremix": (("Wiremix",), ("foot", "--app-id", "Wiremix", "--title", "Wiremix",
                           "wiremix", "-p", "auto", "-f", "30"), False),
    "default-apps": (("awtarchy-default-apps",),
        ("foot", "--app-id", "awtarchy-default-apps", "--title",
         "awtarchy-default-apps", "python3", str(SCRIPTS / "default_applications.py"), "tui"), True),
    "smtty": (("smtty",), (str(SCRIPTS / "default_terminal.sh"),
        "--class", "smtty", "--", "smtty"), False),
    "smtty-O": (("smtty-O",), (str(SCRIPTS / "default_terminal.sh"),
        "--class", "smtty-O", "--hold", "--", "smtty", "-O"), False),
    "wallpicker": (("wallpicker",),
        ("foot", "--app-id", "wallpicker", "awtwall", "--resume"), False),
    "awtarchy-tips-tui": (("awtarchy-tips-tui",), ("foot", "--app-id",
        "awtarchy-tips-tui", str(SCRIPTS / "awtarchy-tips-tui.sh")), False),
}


def query(kind: str) -> list:
    response = subprocess.run(["umbriel", kind, "--json"], check=True,
        capture_output=True, text=True, timeout=6)
    body = json.loads(response.stdout)
    if isinstance(body, dict):
        if "err" in body:
            raise ValueError(str(body["err"]))
        body = body.get("ok", body.get(kind))
    if not isinstance(body, list):
        raise ValueError("Expected Umbriel " + kind + " array")
    return body


def classify(windows: list, workspaces: list, identities: tuple,
             protect_tiled: bool) -> tuple[tuple[str, ...], bool]:
    focused = [w for w in workspaces
               if isinstance(w, dict) and w.get("focused") is True]
    if len(focused) != 1:
        raise ValueError("Expected exactly one focused Umbriel workspace")
    workspace_id = str(focused[0].get("id", ""))
    output = str(focused[0].get("output", ""))
    if not workspace_id or not output:
        raise ValueError("Focused workspace has no stable identity")
    names = {name.casefold() for name in identities}
    local, remote = [], []
    tiled = False
    for window in windows:
        if not isinstance(window, dict):
            continue
        app_id = window.get("app_id")
        title = window.get("title")
        # Foot/Footclient installations can expose their generic app-id while
        # honoring the explicit terminal title. Restrict this fallback to
        # known terminal identities and an exact utility title, never an
        # arbitrary window title or a substring match.
        id_match = isinstance(app_id, str) and app_id.casefold() in names
        title_match = (isinstance(title, str) and title.casefold() in names
                       and isinstance(app_id, str)
                       and app_id.casefold() in ("foot", "footclient",
                                                "org.codeberg.dnkl.foot"))
        if not (id_match or title_match):
            continue
        if window.get("floating") is not True:
            tiled = True
            continue
        window_id = window.get("id")
        if not isinstance(window_id, str) or not window_id:
            raise ValueError("Matching utility has no stable window ID")
        if str(window.get("workspace", "")) == workspace_id and window.get("output") == output:
            local.append(window_id)
        else:
            remote.append(window_id)
    if protect_tiled and tiled:
        return (), False
    if local:
        return (local[-1],), False
    return tuple(remote), True


def toggle(name: str):
    if name not in UTILITIES:
        raise ValueError("Unknown Umbriel utility: " + name)
    if (os.environ.get("XDG_CURRENT_DESKTOP", "").casefold() != "umbriel"
            or not os.environ.get("WAYLAND_DISPLAY")):
        raise ValueError("An active Umbriel session is required")
    identities, command, protect = UTILITIES[name]
    targets, launch = classify(query("windows"), query("workspaces"),
                               identities, protect)
    for window_id in targets:
        subprocess.run(["umbriel", "msg", "window-close", window_id],
                       check=True, capture_output=True, text=True, timeout=6)
    if launch:
        subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)


if __name__ == "__main__":
    try:
        if len(sys.argv) != 2:
            raise ValueError("Usage: toggle-utility.py UTILITY")
        toggle(sys.argv[1])
    except (OSError, RuntimeError, ValueError, KeyError, subprocess.CalledProcessError,
            subprocess.TimeoutExpired, json.JSONDecodeError) as error:
        print("Awtarchy Umbriel utility toggle: " + str(error), file=sys.stderr)
        sys.exit(1)
