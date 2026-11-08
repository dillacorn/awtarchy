#!/usr/bin/env python3
"""Mango equivalent of Awtarchy's floating-app toggle.

Works through authenticated compositor-session IPC. Close only exact client
IDs that match the named utility; keep tiled windows untouched when requested.
No Hyprland dispatcher and no broad process termination.
"""
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import time


def ipc(*args):
    result = subprocess.run(
        ["mmsg", *args], capture_output=True, text=True, check=True, timeout=2)
    parsed = json.loads(result.stdout)
    if not isinstance(parsed, dict) or parsed.get("error"):
        raise RuntimeError("Mango IPC rejected operation")
    return parsed


def focused_workspace():
    monitors = ipc("get", "all-monitors").get("monitors")
    if not isinstance(monitors, list):
        raise RuntimeError("Invalid Mango monitor list")
    focused = [m for m in monitors if isinstance(m, dict) and m.get("active") is True]
    if len(focused) != 1 or not isinstance(focused[0].get("name"), str):
        raise RuntimeError("No unique active Mango monitor")
    monitor = focused[0]
    tags = monitor.get("active_tags")
    if not isinstance(tags, list) or not tags or not all(
            type(tag) is int and 1 <= tag <= 31 for tag in tags):
        raise RuntimeError("Invalid active Mango tags")
    return monitor["name"], set(tags)


def process_matches(client, proc):
    pid = client.get("pid")
    if not proc or type(pid) is not int or pid <= 0:
        return False
    try:
        current = Path(f"/proc/{pid}/comm").read_text().strip()
        if current.casefold() == proc.casefold():
            return True
        command = Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")[0]
        return command.rsplit(b"/", 1)[-1].decode("utf-8", "replace").casefold() == proc.casefold()
    except OSError:
        return False


def matching_client(client, app_class, app_title, app_proc):
    if not isinstance(client, dict) or type(client.get("id")) is not int:
        return False
    if client["id"] <= 0 or client.get("is_minimized") is True:
        return False
    appid = str(client.get("appid") or "")
    title = str(client.get("title") or "")
    # Class is authoritative when the compositor exposes it. A foreign
    # application may legitimately use the same title.
    if app_class and appid:
        return appid.casefold() == app_class.casefold()
    if app_title and title.casefold() == app_title.casefold():
        return True
    if not app_class and not app_title:
        return process_matches(client, app_proc)
    return False


def launch(command):
    if not command.strip():
        raise ValueError("Missing launch command")
    subprocess.Popen(
        ["sh", "-lc", command], stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def toggle(name, command):
    if not os.environ.get("MANGO_INSTANCE_SIGNATURE") or (
            os.environ.get("XDG_CURRENT_DESKTOP") != "mango"):
        raise RuntimeError("Not in a Mango compositor session")
    monitor, tags = focused_workspace()
    clients = ipc("get", "all-clients").get("clients")
    if not isinstance(clients, list):
        raise RuntimeError("Invalid Mango client list")

    app_class = os.environ.get("APP_CLASS_OVERRIDE", name)
    app_title = os.environ.get("APP_TITLE_OVERRIDE", name)
    try:
        parts = shlex.split(command)
    except ValueError as exc:
        raise ValueError("Invalid utility launch command") from exc
    app_proc = os.environ.get("APP_PROC_OVERRIDE", Path(parts[0]).name if parts else "")

    matched = [
        c for c in clients
        if matching_client(c, app_class, app_title, app_proc)
    ]
    if os.environ.get("APP_NO_LAUNCH_IF_TILED", "0") == "1" and any(
            c.get("is_floating") is not True for c in matched):
        return

    floating = [c for c in matched if c.get("is_floating") is True]
    here = [c for c in floating if c.get("monitor") == monitor
            and isinstance(c.get("tags"), list)
            and tags.intersection(t for t in c["tags"] if type(t) is int)]
    if here:
        cid = here[-1]["id"]
        ipc("dispatch", "killclient", f"client,{cid}")
        return

    for c in floating:
        ipc("dispatch", "killclient", f"client,{c['id']}")
    if floating:
        time.sleep(0.05)
    launch(command)


def main(argv):
    if len(argv) != 2 or not argv[0]:
        raise ValueError("usage: launch-handler.py NAME 'launch command'")
    toggle(*argv)


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except (OSError, RuntimeError, ValueError, subprocess.CalledProcessError,
            subprocess.TimeoutExpired) as err:
        print(f"Mango utility launcher: {err}", file=sys.stderr)
        sys.exit(1)
