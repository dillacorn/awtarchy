#!/usr/bin/env bash
# github.com/dillacorn/awtarchy/tree/main/config/hypr/scripts
# ~/.config/hypr/scripts/screenshot_display.sh

# Super+Shift+D: capture the focused Hyprland monitor, save a PNG and
# copy the same image to the Wayland clipboard. No slurp or Satty.
set -euo pipefail

for cmd in grim hyprctl jq wl-copy mktemp date flock; do
  command -v "$cmd" >/dev/null 2>&1 || {
    printf '%s missing\n' "$cmd" >&2
    exit 1
  }
done

# Queue rapid captures and avoid a notification that could appear in the next
# image. Keep this private and session-scoped, never use a shared /tmp lock.
runtime="${XDG_RUNTIME_DIR:-}"
[[ -n "$runtime" && -d "$runtime" && ! -L "$runtime" ]] || {
  printf 'Safe XDG_RUNTIME_DIR required for screenshot lock\n' >&2
  exit 1
}
lock_dir="$runtime/awtarchy-locks"
# XDG_RUNTIME_DIR itself is private; the screenshot lock file contains no data.
# mkdir -p handles concurrent first invocations safely without a chmod race.
mkdir -p -- "$lock_dir"
[[ -d "$lock_dir" && ! -L "$lock_dir" ]] || {
  printf 'Unsafe screenshot lock directory\n' >&2
  exit 1
}

take_screenshot() {
  flock -w 5 9 || {
    printf 'Screenshot queue timed out after 5 seconds\n' >&2
    return 1
  }
  # Focused monitor, not pointer location. Refuse ambiguous IPC.
  local mon out_dir file
  mon="$(hyprctl -j monitors 9>&- | jq -er '
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
file="$(mktemp "$out_dir/$(date +%m%d%Y-%I%p-%S)-XXXXXXXX.png")" || return 1
if ! grim -o "$mon" "$file" 9>&-; then
  rm -f -- "$file"
  printf 'Failed to capture focused monitor: %s\n' "$mon" >&2
  exit 1
fi

# A screenshot already captured stays saved even if the clipboard fails.
if ! wl-copy --type image/png < "$file" 9>&-; then
  printf 'Screenshot saved but clipboard copy failed: %s\n' "$file" >&2
  exit 1
fi

  # No flash/notification: rapid captures remain visually uncontaminated.
}
take_screenshot 9>"$lock_dir/hypr-screenshot.lock"
