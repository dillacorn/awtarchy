#!/usr/bin/env bash
# ~/.config/waybar/scripts/ddc_brightness_vertical.sh
# Outputs one JSON field for the vertical split: icon|value.

set -euo pipefail

mode="${1:-}"
SRC="${XDG_CONFIG_HOME:-$HOME/.config}/waybar/scripts/ddc_brightness.sh"

json="$("$SRC" status 2>/dev/null || true)"

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

text = str(data.get("text", ""))
parts = text.split(maxsplit=1)

icon = parts[0] if parts else ""
value = parts[1] if len(parts) > 1 else ""

if mode == "icon":
    data["text"] = icon
elif mode == "value":
    data["text"] = value

print(json.dumps(data, ensure_ascii=False))
PY
