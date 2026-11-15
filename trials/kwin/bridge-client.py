#!/usr/bin/env python3
"""Register the private KWin Wayland socket with the trial-only D-Bus bridge."""
import asyncio
import re
import sys

async def register(name: str) -> int:
    from dbus_next import Message, MessageType
    from dbus_next.aio import MessageBus

    if not re.fullmatch(r"wayland-[0-9]+", name):
        print("KWin trial client: expected a local Wayland socket name", file=sys.stderr)
        return 1
    bus = await MessageBus().connect()
    try:
        call = Message(
            destination="org.awtarchy.KWinTrial1",
            path="/org/awtarchy/KWinTrial1",
            interface="org.awtarchy.KWinTrial1",
            member="RegisterDisplay",
            signature="s",
            body=[name],
        )
        result = await asyncio.wait_for(bus.call(call), timeout=3)
        if result.message_type != MessageType.METHOD_RETURN or result.body != [True]:
            print("KWin trial client: D-Bus display registration was refused", file=sys.stderr)
            return 1
        return 0
    finally:
        bus.disconnect()

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: bridge-client.py WAYLAND_DISPLAY", file=sys.stderr)
        raise SystemExit(2)
    raise SystemExit(asyncio.run(register(sys.argv[1])))
