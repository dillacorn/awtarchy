#!/usr/bin/env bash
# ~/.config/hypr/scripts/screenshot_area.sh
# Single-instance ONLY during capture (slurp+grim). Satty can stay open while you take more screenshots.

set -euo pipefail

lock_dir="${XDG_RUNTIME_DIR:-/tmp}/awtarchy-locks"
mkdir -p "$lock_dir"
lock_file="$lock_dir/screenshot_capture.lock"

exec 9>"$lock_file"
if ! flock -n 9; then
  notify-send "Screenshot" "Capture already running."
  exit 0
fi

for cmd in grim slurp wl-copy satty notify-send mktemp; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "$cmd missing" >&2; exit 1; }
done

OUTPUT_DIR="$HOME/Pictures/Screenshots"
mkdir -p "$OUTPUT_DIR"

GEOM="$(slurp -b '#ffffff20' -c '#00000040')" || exit 1
[[ -n "${GEOM:-}" ]] || exit 1

TMP_DIR="${XDG_RUNTIME_DIR:-/tmp}"
TMPFILE="$(mktemp "$TMP_DIR/satty-shot-XXXXXX.png")"
OUTFILE="$OUTPUT_DIR/$(date +%m%d%Y-%I%p-%S).png"

cleanup() { rm -f "$TMPFILE"; }
trap cleanup EXIT

grim -g "$GEOM" "$TMPFILE"
wl-copy --type image/png < "$TMPFILE"

# Release lock BEFORE satty starts, so you can take another screenshot while satty is open.
flock -u 9 || true
exec 9>&- || true

satty \
  --filename "$TMPFILE" \
  --output-filename "$OUTFILE" \
  --default-hide-toolbars
