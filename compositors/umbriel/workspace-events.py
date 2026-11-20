#!/usr/bin/env python3
"""Subscribe to Umbriel workspace/window events; print changed Quickshell state.

One persistent Unix socket replaces the old 700 ms CLI subprocess polling.
No compositor settings are mutated and no global filesystem files are written.
"""
from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import socket
import sys

MAX_EVENT_BYTES = 8 * 1024 * 1024


def snapshot_builder():
    path = Path(__file__).with_name("workspace-state.py")
    if path.is_symlink() or not path.is_file():
        raise ValueError("Workspace state adapter is missing or unsafe")
    spec = importlib.util.spec_from_file_location("awtarchy_umbriel_workspace_state", path)
    if spec is None or spec.loader is None:
        raise ValueError("Cannot load Umbriel state adapter")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.collect


def socket_path() -> str:
    if os.environ.get("XDG_CURRENT_DESKTOP", "").casefold() != "umbriel":
        raise ValueError("Workspace subscription requires an Umbriel session")
    runtime, display = os.environ.get("XDG_RUNTIME_DIR"), os.environ.get("WAYLAND_DISPLAY")
    if not runtime or not display:
        raise ValueError("Umbriel runtime directory or display unavailable")
    directory = Path(runtime)
    if (not directory.is_dir() or directory.is_symlink() or
            directory.stat().st_uid != os.getuid()):
        raise ValueError("Unsafe Umbriel runtime directory")
    override = os.environ.get("UMBRIEL_SOCKET")
    if override:
        if not Path(override).is_absolute():
            raise ValueError("UMBRIEL_SOCKET must be an absolute Unix socket path")
        return override
    if "/" in display or display in (".", ".."):
        raise ValueError("Invalid Wayland display name")
    return str(directory / ("umbriel-" + display + ".sock"))


def serve():
    collect = snapshot_builder()
    workspaces = None
    windows = None
    previous = None
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        connection.settimeout(5)
        connection.connect(socket_path())
        connection.settimeout(None)
        connection.sendall(b'{"cmd":"subscribe","events":["workspaces","windows"]}\n')
        with connection.makefile("r", encoding="utf-8") as events:
            for line in events:
                if len(line) > MAX_EVENT_BYTES:
                    raise ValueError("Oversized Umbriel IPC event")
                packet = json.loads(line)
                if not isinstance(packet, dict):
                    raise ValueError("Invalid Umbriel IPC event")
                if "err" in packet:
                    raise ValueError(str(packet["err"]))
                name, data = packet.get("event"), packet.get("data")
                if name not in ("workspaces", "windows"):
                    continue
                if not isinstance(data, list):
                    raise ValueError("Invalid " + name + " snapshot")
                if name == "workspaces":
                    workspaces = data
                else:
                    windows = data
                if workspaces is None or windows is None:
                    continue
                state = collect(workspaces, windows)
                encoded = json.dumps(state, separators=(",", ":"), ensure_ascii=True)
                if encoded != previous:
                    print(encoded, flush=True)
                    previous = encoded
    raise ConnectionError("Umbriel IPC subscription disconnected")


if __name__ == "__main__":
    try:
        serve()
    except (OSError, ValueError, RuntimeError, TypeError, KeyError,
            json.JSONDecodeError, ConnectionError) as error:
        print("Umbriel workspace events: " + str(error), file=sys.stderr)
        sys.exit(1)
