#!/usr/bin/env bash
set -euo pipefail

find_waybar_pid() {
  local pid="${PPID:-}"

  while [[ -n "$pid" && "$pid" != "1" && -r "/proc/$pid/stat" ]]; do
    local comm
    comm="$(cat "/proc/$pid/comm" 2>/dev/null || true)"

    if [[ "$comm" == "waybar" ]]; then
      printf '%s\n' "$pid"
      return 0
    fi

    pid="$(awk '{print $4}' "/proc/$pid/stat" 2>/dev/null || true)"
  done

  printf 'manual\n'
}

waybar_pid="$(find_waybar_pid)"
state_file="${XDG_RUNTIME_DIR:-/tmp}/waybar-clock-toggle.${waybar_pid}.state"

mode="$(cat "$state_file" 2>/dev/null || printf 'time')"

if [[ "${1:-}" == "toggle" ]]; then
  if [[ "$mode" == "date" ]]; then
    printf 'time\n' > "$state_file"
  else
    printf 'date\n' > "$state_file"
  fi

  if [[ "$waybar_pid" != "manual" ]]; then
    kill -RTMIN+12 "$waybar_pid" 2>/dev/null || true
  fi

  exit 0
fi

date_wday="$(date '+%a')"
date_mday="$(date '+%-m/%-d')"
date_full="$(date '+%A, %B %-d, %Y')"
time_24="$(date '+%H:%M')"
time_12="$(date '+%-I:%M %p')"

if command -v cal >/dev/null 2>&1; then
  calendar_text="$(cal | sed '1d')"
else
  calendar_text="$(python3 - <<'PY'
import calendar
from datetime import date

today = date.today()
lines = calendar.month(today.year, today.month).rstrip().splitlines()
print("\n".join(lines[1:]))
PY
)"
fi

if [[ "$mode" == "date" ]]; then
  text=" ${date_wday} ${date_mday}"
  class="date"
  tooltip="${date_full}
24h: ${time_24}
12h: ${time_12}

${calendar_text}"
else
  text=" ${time_24}"
  class="time"
  tooltip="${date_full}
24h: ${time_24}
12h: ${time_12}"
fi

python3 - "$text" "$tooltip" "$class" <<'PY'
import json
import sys

text, tooltip, css_class = sys.argv[1], sys.argv[2], sys.argv[3]
print(json.dumps({
    "text": text,
    "tooltip": tooltip,
    "class": css_class,
}, ensure_ascii=False))
PY
