#!/usr/bin/env python3
"""Offline validation for KWin's private D-Bus workspace state receiver."""
import importlib.util
import json
import os
from pathlib import Path
import tempfile

root = Path(__file__).resolve().parents[1]
path = root / "trials/kwin/state-bridge.py"
spec = importlib.util.spec_from_file_location("state_bridge", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

state = {
    "version": 1,
    "desktops": [{"id": str(n), "name": str(n)} for n in range(1, 11)],
    "outputs": [
        {"name": "DP-1", "active": "3", "occupied": ["1", "3", "10"]},
        {"name": "DP-3", "active": "10", "occupied": []},
    ]
}
data = module.validate(json.dumps(state))
assert json.loads(data)["outputs"][0]["active"] == "3"

with tempfile.TemporaryDirectory(prefix="kwin-state-") as tmp:
    directory = Path(tmp) / "private"
    directory.mkdir(mode=0o700)
    module.publish(directory, data)
    file = directory / "workspace-state.json"
    assert file.read_bytes() == data
    assert file.stat().st_mode & 0o777 == 0o600
    module.publish(directory, data)
    assert file.read_bytes() == data
    changed = json.loads(data)
    changed["outputs"][0]["active"] = "4"
    module.publish(directory, module.validate(json.dumps(changed)))
    assert json.loads(file.read_text())["outputs"][0]["active"] == "4"

    # A link in place of the state file must never be followed or replaced.
    file.unlink()
    outside = Path(tmp) / "private-copy"
    outside.write_text("preserve")
    file.symlink_to(outside)
    try:
        module.publish(directory, data)
    except ValueError:
        pass
    else:
        raise AssertionError("Followed symlink")
    assert outside.read_text() == "preserve"

for bad in [
    {"version": 2, "desktops": state["desktops"], "outputs": state["outputs"]},
    {"version": 1, "desktops": [{"id": "1", "name": "one"}] * 2, "outputs": []},
    {"version": 1, "desktops": state["desktops"], "outputs": [{"name": "DP-1", "active": "99", "occupied": []}]},
    {"version": 1, "desktops": state["desktops"], "outputs": [{"name": "DP-1", "active": "1", "occupied": ["99"]}]},
    {"version": 1, "desktops": state["desktops"], "outputs": [{"name": "\nBAD", "active": "1", "occupied": []}]},
]:
    try:
        module.validate(json.dumps(bad))
    except ValueError:
        pass
    else:
        raise AssertionError("Accepted invalid state")
try:
    module.validate("x" * 20000)
except ValueError:
    pass
else:
    raise AssertionError("Accepted oversized state")

print("PASS: KWin bridge strict JSON, atomic writes, symlink protection")
