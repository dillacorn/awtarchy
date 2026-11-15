#!/usr/bin/env python3
"""Private KWin trial workspace state receiver, not a permanent user service.

The KWin script sends bounded JSON over the session bus. Only this process
owns the exported service; it atomically publishes minimal state inside the
private trial runtime directory. Never writes global compositor configuration.
"""
from __future__ import annotations

import argparse
import asyncio
import json
import os
from pathlib import Path
import stat
import sys
import tempfile

SERVICE = "org.awtarchy.KWinTrial1"
PATH = "/org/awtarchy/KWinTrial1"
INTERFACE = "org.awtarchy.KWinTrial1"
MAX_BYTES = 8192
MAX_OUTPUTS = 16
MAX_DESKTOPS = 32


def validate(raw: str) -> bytes:
    if not isinstance(raw, str) or len(raw.encode("utf-8")) > MAX_BYTES:
        raise ValueError("Oversized or invalid workspace update")
    obj = json.loads(raw)
    if not isinstance(obj, dict) or obj.get("version") != 1:
        raise ValueError("Unknown workspace state version")
    desktops = obj.get("desktops")
    outputs = obj.get("outputs")
    if not isinstance(desktops, list) or not 1 <= len(desktops) <= MAX_DESKTOPS:
        raise ValueError("Invalid desktop list")
    if not isinstance(outputs, list) or len(outputs) > MAX_OUTPUTS:
        raise ValueError("Invalid output list")
    ids = set()
    for desktop in desktops:
        if not isinstance(desktop, dict):
            raise ValueError("Invalid desktop")
        ident = desktop.get("id")
        name = desktop.get("name")
        if not isinstance(ident, str) or not 1 <= len(ident) <= 128:
            raise ValueError("Invalid desktop ID")
        if not isinstance(name, str) or not 1 <= len(name) <= 128:
            raise ValueError("Invalid desktop name")
        if ident in ids or any(ord(c) < 32 for c in ident + name):
            raise ValueError("Duplicate or unsafe desktop")
        ids.add(ident)
    names = set()
    for output in outputs:
        if not isinstance(output, dict):
            raise ValueError("Invalid output")
        name = output.get("name")
        active = output.get("active")
        occupied = output.get("occupied")
        if not isinstance(name, str) or not 1 <= len(name) <= 128:
            raise ValueError("Invalid output name")
        if name in names or any(ord(c) < 32 for c in name):
            raise ValueError("Duplicate or unsafe output")
        names.add(name)
        if active is not None and active not in ids:
            raise ValueError("Output references unknown active desktop")
        if not isinstance(occupied, list) or len(occupied) > MAX_DESKTOPS:
            raise ValueError("Invalid occupied list")
        if any(not isinstance(item, str) or item not in ids for item in occupied):
            raise ValueError("Unknown occupied desktop")
    return (json.dumps(obj, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")


def check_root(root: Path) -> None:
    if not root.is_absolute() or root.is_symlink() or not root.is_dir():
        raise ValueError("Session state root is missing or unsafe")
    if root.stat().st_uid != os.geteuid() or stat.S_IMODE(root.stat().st_mode) != 0o700:
        raise ValueError("Session state root must be private and user-owned")


def publish(root: Path, state: bytes) -> None:
    check_root(root)
    target = root / "workspace-state.json"
    if target.is_symlink() or (target.exists() and not target.is_file()):
        raise ValueError("Unsafe existing KWin state file")
    if target.exists() and target.read_bytes() == state:
        return
    fd, temp = tempfile.mkstemp(prefix=".workspaces.", dir=root)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(state)
        os.chmod(temp, 0o600)
        os.replace(temp, target)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


async def serve(root: Path) -> None:
    from dbus_next import BusType, RequestNameReply
    from dbus_next.aio import MessageBus
    from dbus_next.service import ServiceInterface, method

    class Receiver(ServiceInterface):
        def __init__(self):
            super().__init__(INTERFACE)

        @method()
        def UpdateState(self, state: "s") -> "b":
            try:
                publish(root, validate(state))
                return True
            except (OSError, ValueError, json.JSONDecodeError) as error:
                print("KWin state update rejected: " + str(error), file=sys.stderr)
                return False

    bus = await MessageBus(bus_type=BusType.SESSION).connect()
    bus.export(PATH, Receiver())
    result = await bus.request_name(SERVICE)
    if result != RequestNameReply.PRIMARY_OWNER:
        raise RuntimeError("An existing KWin state bridge owns the D-Bus name")
    check_root(root)
    # Create a real file before Quickshell starts watching its path.
    # The KWin publisher replaces this with the exact live workspace state.
    initial = {"version": 1,
               "desktops": [{"id": str(n), "name": str(n)} for n in range(1, 11)],
               "outputs": []}
    publish(root, validate(json.dumps(initial)))
    # Ready is published only after the D-Bus service name is exclusively owned
    # and the initial workspace state file is present.
    (root / "ready").write_text("ready\n", encoding="utf-8")
    os.chmod(root / "ready", 0o600)
    await bus.wait_for_disconnect()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--state-dir", required=True, type=Path)
    args = parser.parse_args()
    try:
        check_root(args.state_dir)
        asyncio.run(serve(args.state_dir))
        return 0
    except (OSError, RuntimeError, ValueError, ImportError) as error:
        print("KWin state bridge: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
