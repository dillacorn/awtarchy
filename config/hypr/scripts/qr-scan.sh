#!/usr/bin/env bash
# ~/.config/hypr/scripts/qr-scan.sh
# Single-instance guarded.

set -euo pipefail

# ---- single instance lock ----
lock_dir="${XDG_RUNTIME_DIR:-/tmp}/awtarchy-locks"
mkdir -p "$lock_dir"
lock_file="$lock_dir/qr-scan.lock"
exec 9>"$lock_file"
if ! flock -n 9; then
  notify-send "QR Code" "Already running."
  exit 0
fi

# ---- deps ----
for cmd in grim slurp zbarimg wl-copy notify-send mktemp; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "$cmd missing" >&2; exit 1; }
done

tempfile="$(mktemp --suffix=.png)"
cleanup() { rm -f "$tempfile"; }
trap cleanup EXIT

grim -g "$(slurp)" "$tempfile"
qr_output="$(zbarimg --quiet "$tempfile" 2>/dev/null | sed 's/^QR-Code://')"

if [[ -n "${qr_output:-}" ]]; then
  printf '%s' "$qr_output" | wl-copy
  notify-send "QR Code Scanned" "$qr_output"
else
  notify-send "QR Code" "No QR code found."
fi
