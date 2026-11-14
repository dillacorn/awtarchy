#!/usr/bin/env bash
# github.com/dillacorn/awtarchy/tree/main/config/hypr/scripts
# ~/.config/hypr/scripts/screenshot_display.sh

# Super+Shift+D: capture the focused Hyprland monitor, save a PNG and
# copy the same image to the Wayland clipboard. No slurp or Satty.
set -euo pipefail

for cmd in grim hyprctl jq notify-send wl-copy mktemp date; do
  command -v "$cmd" >/dev/null 2>&1 || {
    printf '%s missing\n' "$cmd" >&2
    exit 1
  }
done

# Focused window/output, not the pointer's monitor. Refuse malformed/ambiguous
# IPC so we never accidentally capture another display.
mon="$(hyprctl -j monitors | jq -er '
    if type != "array" then error("invalid monitors") else
        [.[] | select(type == "object" and .focused == true)
             | .name | select(type == "string" and length > 0)] |
        if length == 1 then .[0]
        else error("expected exactly one focused monitor") end
    end
')" || {
  printf 'Unable to identify the focused Hyprland monitor\n' >&2
  exit 1
}

out_dir="$HOME/Pictures/Screenshots"
mkdir -p -- "$out_dir"
[[ -d "$out_dir" && ! -L "$out_dir" ]] || {
  printf 'Unsafe screenshots directory: %s\n' "$out_dir" >&2
  exit 1
}

# Unique even when the shortcut is pressed repeatedly within one second.
file="$(mktemp "$out_dir/$(date +%m%d%Y-%I%p-%S)-XXXXXXXX.png")" || exit 1
if ! grim -o "$mon" "$file"; then
  rm -f -- "$file"
  printf 'Failed to capture focused monitor: %s\n' "$mon" >&2
  exit 1
fi

# A screenshot already captured stays saved even if the clipboard fails.
if ! wl-copy --type image/png < "$file"; then
  printf 'Screenshot saved but clipboard copy failed: %s\n' "$file" >&2
  exit 1
fi

notify-send --app-name 'awtarchy-screenshot' 'Screenshot saved & copied' "$file" || true
