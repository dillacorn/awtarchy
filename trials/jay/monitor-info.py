#!/usr/bin/env python3
"""Read Jay's real DRM output inventory; never query another compositor."""
import json
import subprocess
import sys

def outputs():
    run = subprocess.run(["jay", "--json", "randr", "show"], check=True,
                         capture_output=True, text=True, timeout=4)
    lines = [line for line in run.stdout.splitlines() if line.strip()]
    if len(lines) != 1:
        raise ValueError("Unexpected Jay output inventory")
    result = json.loads(lines[0])
    if not isinstance(result, dict):
        raise ValueError("Malformed Jay output inventory")
    entries = []
    cards = result.get("drm_devices", [])
    if not isinstance(cards, list):
        raise ValueError("Malformed Jay DRM devices")
    connectors = [connector for card in cards for connector in card.get("connectors", [])]
    connectors += result.get("unbound_connectors", [])
    seen = set()
    for con in connectors:
        name = con.get("name")
        if not isinstance(name, str) or not name or name in seen:
            raise ValueError("Invalid/duplicate Jay connector")
        seen.add(name)
        output = con.get("output") or {}
        mode = output.get("mode") or {}
        enabled = bool(con.get("enabled")) and bool(output)
        entries.append({
            "name": name, "disabled": not enabled,
            "focused": False,
            "x": output.get("x", 0), "y": output.get("y", 0),
            "width": mode.get("width", output.get("width", 0)),
            "height": mode.get("height", output.get("height", 0)),
            "scale": output.get("scale", 1.0)
        })
    active = [e for e in entries if not e["disabled"]]
    if active:
        # Jay does not expose focused output in randr. This is a fallback
        # only for CLI settings operations; QML derives focus via Wayland.
        active[0]["focused"] = True
    return entries

def main():
    if len(sys.argv) != 2 or sys.argv[1] not in ("monitors", "activeworkspace"):
        raise ValueError("Usage: monitor-info.py monitors|activeworkspace")
    monitors = outputs()
    if sys.argv[1] == "monitors":
        print(json.dumps(monitors, separators=(",", ":")))
    else:
        first = next((m["name"] for m in monitors if m["focused"]), "")
        print(json.dumps({"monitor": first}))

if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError,
            subprocess.TimeoutExpired, json.JSONDecodeError) as exc:
        print(f"jay monitor inventory: {exc}", file=sys.stderr)
        sys.exit(1)
