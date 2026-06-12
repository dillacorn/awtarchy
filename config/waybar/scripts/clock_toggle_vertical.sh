#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
SRC="${XDG_CONFIG_HOME:-$HOME/.config}/waybar/scripts/clock_toggle.sh"

if [[ "$mode" == "toggle" ]]; then
  exec "$SRC" toggle
fi

json="$("$SRC" 2>/dev/null || true)"

python3 - "$mode" "$json" <<'PY'
import json
import sys

mode = sys.argv[1]
raw = sys.argv[2]

try:
    data = json.loads(raw)
except Exception:
    print(raw)
    raise SystemExit(0)

text = data.get("text", "")
parts = text.split()

icon = parts[0] if len(parts) >= 1 else ""
rest = parts[1:]

a = ""
b = ""

if icon == "" and rest:
    time_parts = rest[0].split(":", 1)
    a = time_parts[0]
    b = time_parts[1] if len(time_parts) > 1 else ""
elif icon == "":
    a = rest[0] if len(rest) >= 1 else ""
    b = rest[1] if len(rest) >= 2 else ""
elif rest:
    a = rest[0]
    b = rest[1] if len(rest) >= 2 else ""

if mode == "icon":
    data["text"] = icon
elif mode == "a":
    data["text"] = a
elif mode == "b":
    data["text"] = b

print(json.dumps(data, ensure_ascii=False))
PY
