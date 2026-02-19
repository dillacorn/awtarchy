#!/usr/bin/env bash
set -euo pipefail

# last_to_load_recorder.sh
# Records the LAST user-systemd unit that changes state within a window after start.
# Output: ~/.local/state/awtarchy/last-to-load-recorder.log
#
# Env overrides:
#   WINDOW_SEC   (default 90)   NOTE: singular name you asked for
#   INTERVAL_SEC (default 0.25)

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/awtarchy"
LOG="$STATE_DIR/last-to-load-recorder.log"
mkdir -p "$STATE_DIR"

WINDOW_SEC="${WINDOW_SEC:-90}"
INTERVAL_SEC="${INTERVAL_SEC:-0.25}"

ts() { date -Is; }

{
  echo "=== last-to-load-recorder ==="
  echo "start: $(ts)"
  echo "window_sec: $WINDOW_SEC"
  echo "interval_sec: $INTERVAL_SEC"
  echo
} >"$LOG"

# Snapshot current state for ALL user units
declare -A prev
while IFS=$'\t' read -r unit active sub; do
  [[ -z "${unit:-}" ]] && continue
  prev["$unit"]="${active}|${sub}"
done < <(systemctl --user list-units --all --no-legend --no-pager \
        | awk '{print $1"\t"$3"\t"$4}')

end_epoch=$(( $(date +%s) + WINDOW_SEC ))

last_when=""
last_unit=""
last_from=""
last_to=""

while (( $(date +%s) < end_epoch )); do
  now="$(ts)"
  while IFS=$'\t' read -r unit active sub; do
    [[ -z "${unit:-}" ]] && continue
    cur="${active}|${sub}"
    old="${prev[$unit]:-}"

    if [[ -n "$old" && "$cur" != "$old" ]]; then
      echo "$now change: $unit $old -> $cur" >>"$LOG"
      last_when="$now"
      last_unit="$unit"
      last_from="$old"
      last_to="$cur"
      prev["$unit"]="$cur"
    elif [[ -z "$old" ]]; then
      echo "$now new: $unit (was none) -> $cur" >>"$LOG"
      last_when="$now"
      last_unit="$unit"
      last_from="(none)"
      last_to="$cur"
      prev["$unit"]="$cur"
    fi
  done < <(systemctl --user list-units --all --no-legend --no-pager \
          | awk '{print $1"\t"$3"\t"$4}')

  sleep "$INTERVAL_SEC"
done

{
  echo
  echo "end: $(ts)"
  if [[ -n "$last_unit" ]]; then
    echo "LAST_CHANGE_AT: $last_when"
    echo "LAST_CHANGE_UNIT: $last_unit"
    echo "LAST_CHANGE_FROM: $last_from"
    echo "LAST_CHANGE_TO:   $last_to"
  else
    echo "LAST_CHANGE_AT: (none)"
    echo "LAST_CHANGE_UNIT: (none)"
  fi
} >>"$LOG"

echo "$LOG"
