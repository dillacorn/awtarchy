#!/usr/bin/env python3
"""Read-only KWin monitor summary from KScreen's official JSON interface."""
from __future__ import annotations

import json
import subprocess
import sys


def show(doc: object) -> str:
    if not isinstance(doc, dict) or not isinstance(doc.get("outputs"), list):
        raise ValueError("KScreen JSON is missing the outputs array")
    rows = []
    for output in doc["outputs"]:
        if not isinstance(output, dict):
            raise ValueError("Invalid KScreen output")
        name = output.get("name")
        if not isinstance(name, str) or not name or "\n" in name:
            raise ValueError("Invalid KScreen connector name")
        connected = output.get("connected")
        if connected is not True:
            state = "disconnected" if connected is False else "unknown"
            rows.append(f"{name}: {state}")
            continue
        # Some virtual outputs omit 'enabled'. Absence is not evidence of
        # disablement; never silently interpret missing data as disabled.
        enabled = output.get("enabled")
        state = ("enabled" if enabled is True else
                 "disabled" if enabled is False else "enabled unknown")
        current = output.get("currentModeId")
        mode = next((
            item for item in output.get("modes", [])
            if isinstance(item, dict) and str(item.get("id")) == str(current)
        ), None)
        timing = "mode unknown"
        if mode:
            size = mode.get("size") or {}
            refresh = mode.get("refreshRate")
            if (isinstance(size, dict) and isinstance(size.get("width"), int)
                    and isinstance(size.get("height"), int)
                    and isinstance(refresh, (int, float))):
                timing = (f"{size['width']}x{size['height']}@{refresh:.2f}Hz")
        pos = output.get("pos")
        coords = "position unknown"
        if isinstance(pos, dict) and "x" in pos and "y" in pos:
            if isinstance(pos["x"], int) and isinstance(pos["y"], int):
                coords = f"{pos['x']},{pos['y']}"
        scale = output.get("scale")
        scaled = f"scale {scale:g}" if isinstance(scale, (int, float)) and scale > 0 else "scale unknown"
        rows.append(f"{name}: {state}, {timing}, {coords}, {scaled}")
    return "\n".join(rows)


def main() -> int:
    try:
        result = subprocess.run(
            ["/usr/bin/kscreen-doctor", "-j"], check=True, capture_output=True,
            text=True, timeout=12,
        )
        print(show(json.loads(result.stdout)))
    except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired,
            ValueError, TypeError, json.JSONDecodeError) as error:
        print(f"KWin monitor inspection failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
