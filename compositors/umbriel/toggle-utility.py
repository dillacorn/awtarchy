#!/usr/bin/env python3
"""Toggle only matching Umbriel floating utilities; never kill tiled windows."""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import time

CONFIG = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
SCRIPTS = CONFIG / "hypr/scripts"
UTILITIES = {
    "btop": (("btop",), ("foot", "--app-id", "btop", "--title", "btop", "btop"), True),
    "maccel": (("maccel",), ("foot", "--app-id", "maccel", "maccel", "tui"), False),
    "wiremix": (("Wiremix",), ("foot", "--app-id", "Wiremix", "--title", "Wiremix",
                           "wiremix", "-p", "auto", "-f", "30"), True),
    "displays": (("wdisplays", "network.cycles.wdisplays"), ("wdisplays",), True),
    "default-apps": (("awtarchy-default-apps",),
        ("foot", "--app-id", "awtarchy-default-apps", "--title",
         "awtarchy-default-apps", "python3", str(SCRIPTS / "default_applications.py"), "tui"), True),
    "smtty": (("smtty",), (str(SCRIPTS / "default_terminal.sh"),
        "--class", "smtty", "--", "smtty"), False),
    "smtty-O": (("smtty-O",), (str(SCRIPTS / "default_terminal.sh"),
        "--class", "smtty-O", "--hold", "--", "smtty", "-O"), False),
    "wallpicker": (("wallpicker",),
        ("foot", "--app-id", "wallpicker", "bash",
         str(CONFIG / "umbriel/awtarchy-trial/awtwall.sh"), "--resume"), False),
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


def matches_identity(window: dict, names: set[str]) -> bool:
    """Match exact utility app IDs; permit title fallback only for Foot."""
    app_id = window.get("app_id")
    title = window.get("title")
    return ((isinstance(app_id, str) and app_id.casefold() in names) or
            (isinstance(title, str) and title.casefold() in names and
             isinstance(app_id, str) and
             app_id.casefold() in ("foot", "footclient", "org.codeberg.dnkl.foot")))


def ensure_new_floating(previous: list, identities: tuple) -> None:
    """Verify the just-launched utility floats, without changing old tiled apps."""
    known_ids = {w.get("id") for w in previous if isinstance(w, dict)}
    names = {name.casefold() for name in identities}
    converted = set()
    for _ in range(60):
        for window in query("windows"):
            if not isinstance(window, dict):
                continue
            window_id = window.get("id")
            if (not isinstance(window_id, str) or not window_id or
                    window_id in known_ids or not matches_identity(window, names)):
                continue
            if window.get("floating") is True:
                return
            if window_id not in converted:
                reply = subprocess.run(
                    ["umbriel", "msg", "window-toggle-floating", window_id],
                    check=True, capture_output=True, text=True, timeout=6)
                data = json.loads(reply.stdout)
                if not isinstance(data, dict) or "err" in data or "ok" not in data:
                    raise RuntimeError("Umbriel refused floating for utility " + window_id)
                converted.add(window_id)
        time.sleep(0.1)
    raise RuntimeError("The launched utility did not report a floating window")


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
        if not matches_identity(window, names):
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
    before = query("windows")
    targets, launch = classify(before, query("workspaces"),
                               identities, protect)
    for window_id in targets:
        subprocess.run(["umbriel", "msg", "window-close", window_id],
                       check=True, capture_output=True, text=True, timeout=6)
    if launch:
        subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
        if name in ("btop", "wiremix", "displays"):
            ensure_new_floating(before, identities)


if __name__ == "__main__":
    try:
        if len(sys.argv) != 2:
            raise ValueError("Usage: toggle-utility.py UTILITY")
        toggle(sys.argv[1])
    except (OSError, RuntimeError, ValueError, KeyError, subprocess.CalledProcessError,
            subprocess.TimeoutExpired, json.JSONDecodeError) as error:
        print("Awtarchy Umbriel utility toggle: " + str(error), file=sys.stderr)
        sys.exit(1)
