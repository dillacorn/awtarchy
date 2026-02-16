#!/usr/bin/env bash
# github.com/dillacorn/awtarchy/tree/main/config/hypr/scripts
# ~/.config/hypr/scripts/screenshot_display.sh

set -euo pipefail

# deps
for cmd in grim hyprctl jq notify-send wl-copy makoctl; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "$cmd missing" >&2; exit 1; }
done

out_dir="$HOME/Pictures/Screenshots"
file="$out_dir/$(date +%m%d%Y-%I%p-%S).png"

mkdir -p "$out_dir"

# only clear our own prior notification (from this script) if it exists
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/awtarchy"
mkdir -p "$cache_dir"
nid_file="$cache_dir/screenshot_display.nid"
: "${MAKO_CLEAR_DELAY:=0.08}"

if [[ -f "$nid_file" ]]; then
  if read -r old_id < "$nid_file"; then
    if [[ -n "${old_id:-}" ]]; then
      makoctl dismiss -n "$old_id" >/dev/null 2>&1 || true
      sleep "$MAKO_CLEAR_DELAY"
    fi
  fi
fi

# get monitor name from cursor, fallback to focused
cursor_json="$(hyprctl -j cursors 2>/dev/null || true)"
if [[ -n "$cursor_json" ]] && echo "$cursor_json" | jq -e . >/dev/null 2>&1; then
    mon="$(echo "$cursor_json" | jq -r '.[0].monitor')"
fi

if [[ -z "${mon:-}" || "$mon" == "null" ]]; then
    monitor_json="$(hyprctl -j monitors 2>/dev/null || true)"
    if [[ -n "$monitor_json" ]] && echo "$monitor_json" | jq -e . >/dev/null 2>&1; then
        mon="$(echo "$monitor_json" | jq -r '.[] | select(.focused==true) | .name' | head -n1)"
    fi
fi

[[ -n "${mon:-}" ]] || { echo "No monitor found" >&2; exit 1; }

grim -o "$mon" "$file" >/dev/null 2>&1
wl-copy < "$file"

# send a new notification with a stable app-name and capture its id
nid="$(notify-send -p --app-name 'awtarchy-screenshot' 'Screenshot saved & copied' "$file" || true)"
printf '%s\n' "${nid:-}" > "$nid_file" 2>/dev/null || true
