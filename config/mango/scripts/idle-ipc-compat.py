#!/usr/bin/env python3
"""Narrow Mango IPC adapter for existing read-only Hypridle guards.

Only the exact JSON queries and DPMS commands used by Awtarchy's idle guard
are supported. This is intentionally *not* a general hyprctl emulation layer.
"""
import json
import subprocess
import sys


def query(command):
    run = subprocess.run(["mmsg", "get", command], check=True, capture_output=True,
                         text=True, timeout=2)
    raw = json.loads(run.stdout)
    if not isinstance(raw, dict) or raw.get("error"):
        raise ValueError("Invalid Mango compositor IPC response")
    return raw


def monitors():
    values = query("all-monitors").get("monitors")
    if not isinstance(values, list):
        raise ValueError("Missing Mango monitor list")
    return values


def clients():
    values = query("all-clients").get("clients")
    if not isinstance(values, list):
        raise ValueError("Missing Mango client list")
    output = []
    for client in values:
        if not isinstance(client, dict):
            raise ValueError("Malformed Mango client entry")
        tags = client.get("tags", [])
        if not isinstance(tags, list):
            raise ValueError("Malformed Mango tags")
        workspace = next((tag for tag in tags if type(tag) is int and 1 <= tag <= 31), -1)
        appid = str(client.get("appid") or "")
        output.append({
            "class": appid,
            "initialClass": appid,
            "title": str(client.get("title") or ""),
            "mapped": client.get("is_minimized") is not True,
            "workspace": {"id": workspace},
            "contentType": "none",    # Mango IPC provides no content-type hint.
            "inhibitingIdle": False,  # Unknown: do not claim actual inhibitor state.
        })
    return output


def active_monitor():
    values = monitors()
    focused = next((m for m in values if isinstance(m, dict)
                    and m.get("active") is True), None)
    if focused is None:
        raise ValueError("No focused Mango monitor")
    return focused


def active_tag(monitor):
    tags = monitor.get("active_tags")
    if not isinstance(tags, list) or not tags or type(tags[0]) is not int:
        raise ValueError("Mango monitor has no active tag")
    if not 1 <= tags[0] <= 31:
        raise ValueError("Invalid Mango tag")
    return tags[0]


def dpms(action):
    values = monitors()
    if not values:
        raise ValueError("No Mango outputs to control")
    operation = "wakeup_monitor" if action == "enable" else "sleep_monitor"
    for monitor in values:
        name = monitor.get("name") if isinstance(monitor, dict) else None
        if not isinstance(name, str) or not name or not all(
                c.isalnum() or c in "._:-" for c in name):
            raise ValueError("Unsafe Mango monitor name")
    for monitor in values:
        run = subprocess.run(["mmsg", "dispatch", f"{operation},{monitor['name']}"],
                             check=True, capture_output=True, text=True, timeout=2)
        try:
            response = json.loads(run.stdout)
        except ValueError as exc:
            raise ValueError("Mango DPMS dispatch returned invalid JSON") from exc
        if isinstance(response, dict) and response.get("error"):
            raise ValueError("Mango DPMS dispatch was refused")


def main(argv):
    if argv in (["clients", "-j"], ["-j", "clients"]):
        print(json.dumps(clients()))
    elif argv in (["monitors", "-j"], ["-j", "monitors"]):
        output = []
        for m in monitors():
            if not isinstance(m, dict):
                raise ValueError("Invalid Mango output")
            tags = m.get("active_tags", [])
            first = next((tag for tag in tags if type(tag) is int and 1 <= tag <= 31), 0)
            output.append({
                "name": str(m.get("name") or ""),
                "focused": m.get("active") is True,
                "activeWorkspace": {"id": first},
                "specialWorkspace": {"id": 0}
            })
        print(json.dumps(output))
    elif argv in (["activeworkspace", "-j"], ["-j", "activeworkspace"]):
        mon = active_monitor()
        tag = active_tag(mon)
        print(json.dumps({"id": tag, "name": str(tag), "monitor": mon["name"]}))
    elif len(argv) == 2 and argv[0] == "dispatch":
        if argv[1] == 'hl.dsp.dpms({ action = "enable" })':
            dpms("enable")
        elif argv[1] == 'hl.dsp.dpms({ action = "disable" })':
            dpms("disable")
        else:
            raise ValueError("Unsupported compositor dispatcher")
    else:
        raise ValueError("Unsupported Mango compatibility operation")


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except (OSError, ValueError, subprocess.CalledProcessError,
            subprocess.TimeoutExpired) as error:
        print(f"mango-idle-ipc: {error}", file=sys.stderr)
        sys.exit(1)
