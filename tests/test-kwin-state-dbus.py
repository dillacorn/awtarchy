#!/usr/bin/env python3
"""End-to-end isolated KWin workspace D-Bus receiver test."""
import asyncio
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

from dbus_next import Message, MessageType
from dbus_next.aio import MessageBus

SOURCE = Path(__file__).resolve().parents[1] / "trials/kwin/state-bridge.py"


async def run() -> None:
    with tempfile.TemporaryDirectory(prefix="awtarchy-kwin-dbus-") as tmp:
        state_dir = Path(tmp) / "runtime"
        state_dir.mkdir(mode=0o700)
        process = subprocess.Popen(
            [sys.executable, str(SOURCE), "--state-dir", str(state_dir)],
            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True,
            env=dict(os.environ),
        )
        bus = None
        try:
            ready = state_dir / "ready"
            for _ in range(100):
                if ready.is_file() and (state_dir / "workspace-state.json").is_file():
                    break
                if process.poll() is not None:
                    raise AssertionError("D-Bus state service died during startup")
                await asyncio.sleep(0.03)
            else:
                raise AssertionError("D-Bus state bridge did not become ready")

            bus = await MessageBus().connect()
            async def update(body):
                message = Message(
                    destination="org.awtarchy.KWinTrial1",
                    path="/org/awtarchy/KWinTrial1",
                    interface="org.awtarchy.KWinTrial1",
                    member="UpdateState",
                    signature="s",
                    body=[body],
                )
                return await asyncio.wait_for(bus.call(message), timeout=5)

            current = {
                "version": 1,
                "desktops": [{"id": "1", "name": "1"},
                             {"id": "2", "name": "2"}],
                "outputs": [{"name": "DP-3", "active": "2", "occupied": ["2"]}],
            }
            response = await update(json.dumps(current))
            assert response.message_type == MessageType.METHOD_RETURN
            assert response.body == [True], response.body
            stored = json.loads((state_dir / "workspace-state.json").read_text())
            assert stored == current

            response = await update(json.dumps({**current, "version": 999}))
            assert response.body == [False], response.body
            assert json.loads((state_dir / "workspace-state.json").read_text()) == current

            # Rejection should not kill the receiver.
            response = await update(json.dumps(current))
            assert response.body == [True], response.body
            assert process.poll() is None
        finally:
            if bus is not None:
                bus.disconnect()
            process.terminate()
            try:
                _, err = process.communicate(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
                _, err = process.communicate(timeout=3)
            assert process.returncode in (0, -15), err


asyncio.run(run())
print("PASS: KWin D-Bus bridge accepts valid state and rejects invalid state")
