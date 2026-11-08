#!/usr/bin/env python3
"""Read Mango 0.18.5's authoritative IPC, without querying Hyprland."""
import json
import subprocess
import sys

def query(kind):
    p = subprocess.run(["mmsg", "get", kind], capture_output=True, text=True, timeout=2, check=True)
    obj = json.loads(p.stdout)
    if not isinstance(obj, dict) or "error" in obj:
        raise RuntimeError("Mango IPC error: " + str(obj))
    return obj

def main():
    monitors = query("all-monitors").get("monitors")
    clients = query("all-clients").get("clients")
    if not isinstance(monitors, list) or not isinstance(clients, list):
        raise RuntimeError("Malformed Mango monitor/client snapshot")
    print(json.dumps({"monitors": monitors, "clients": clients}, separators=(",", ":")))

if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError,
            subprocess.TimeoutExpired) as exc:
        print(f"mango snapshot: {exc}", file=sys.stderr)
        sys.exit(1)
