#!/usr/bin/env python3
"""Navigate Awtarchy's globally numbered Umbriel workspaces.

Native bare workspace-switch N chooses an output-local position. Always use
the unique explicit name 1..10, which follows a workspace across outputs.
This helper only handles wraparound and diagnostic queries; no IPC state is
persisted and no workspace is created or moved by navigation.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys

NAMES = {str(value) for value in range(1, 11)}


def inventory() -> list[dict]:
    result = subprocess.run(["umbriel", "workspaces", "--json"],
                            capture_output=True, text=True, check=True, timeout=6)
    payload = json.loads(result.stdout)
    if isinstance(payload, dict):
        if "err" in payload:
            raise ValueError(str(payload["err"]))
        payload = payload.get("ok", payload.get("workspaces"))
    if not isinstance(payload, list):
        raise ValueError("Invalid native Umbriel workspace inventory")
    rows = [item for item in payload if isinstance(item, dict)
            and item.get("named") is True and item.get("name") in NAMES
            and isinstance(item.get("output"), str) and item.get("output")]
    found = [item["name"] for item in rows]
    duplicates = sorted({name for name in found if found.count(name) > 1})
    if duplicates:
        raise ValueError("Duplicate globally named workspaces: " + ",".join(duplicates))
    if set(found) != NAMES:
        raise ValueError("Named workspaces incomplete; reload the new global config from a fresh session")
    return rows


def choose(direction: str, entries: list[dict]):
    active = [entry for entry in entries if entry.get("focused") is True]
    if len(active) != 1:
        raise ValueError("No unique focused numbered workspace")
    current = int(active[0]["name"])
    target = str((current - 1 + (1 if direction == "next" else -1)) % 10 + 1)
    result = subprocess.run(["umbriel", "msg", "workspace-switch", "--name", target],
                            capture_output=True, text=True, check=True, timeout=6)
    if '"err"' in result.stdout:
        raise ValueError(result.stdout.strip())


def main():
    if (os.environ.get("XDG_CURRENT_DESKTOP", "").casefold() != "umbriel"
            or not os.environ.get("WAYLAND_DISPLAY")):
        raise ValueError("An active Umbriel session is required")
    if len(sys.argv) != 2 or sys.argv[1] not in ("next", "previous", "status"):
        raise ValueError("Usage: workspace-nav.py next|previous|status")
    entries = inventory()
    if sys.argv[1] == "status":
        print(json.dumps(sorted(
            ({key: row.get(key) for key in
              ("name", "id", "output", "index", "active", "focused")}
             for row in entries),
            key=lambda row: int(row["name"])), separators=(",", ":")))
    else:
        choose(sys.argv[1], entries)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, TypeError, KeyError, json.JSONDecodeError,
            subprocess.TimeoutExpired, subprocess.CalledProcessError) as error:
        print("Umbriel global workspace navigation: " + str(error), file=sys.stderr)
        sys.exit(1)
