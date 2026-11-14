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


# Best-effort audible feedback for direct captures only. PipeWire playback
# must never block a screenshot or inherit the capture lock. Reproduce the
# user-selected "Classic: tighter double-click" preview at 80% volume.
play_screenshot_shutter() {
    command -v pw-play >/dev/null 2>&1 || return 0
    (
        python3 -c '
import math
import random
import struct
import sys

rate = 48000
rng = random.Random(2026)

def burst(t, start, duration, strength, decay=6):
    x = (t - start) / duration
    if not 0 <= x < 1:
        return 0.0
    return strength * math.exp(-decay * x)

def tone(t, start, duration, frequency, strength):
    x = (t - start) / duration
    if not 0 <= x < 1:
        return 0.0
    envelope = math.sin(math.pi * x) ** 2
    return strength * envelope * math.sin(
        2 * math.pi * frequency * (t - start)
    )

samples = []
for i in range(int(rate * 0.18)):
    t = i / rate
    noise = rng.uniform(-1, 1)
    value = noise * (
        burst(t, 0.005, 0.042, 1.0) +
        burst(t, 0.064, 0.058, 1.0)
    )
    value += tone(t, 0.006, 0.049, 170, 0.45)
    samples.append(value)

peak = max(abs(s) for s in samples) or 1.0
pcm = bytearray()
for value in samples:
    sample = max(-32768, min(32767, int(value / peak * 28000)))
    pcm.extend(struct.pack("<h", sample))
sys.stdout.buffer.write(pcm)
' | pw-play --raw --format=s16 --rate=48000 --channels=1 \
        --volume=0.80 --latency=20ms - >/dev/null 2>&1
    ) 9>&- </dev/null >/dev/null 2>&1 &
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
  play_screenshot_shutter
}
take_screenshot 9>"$lock_dir/hypr-screenshot.lock"
