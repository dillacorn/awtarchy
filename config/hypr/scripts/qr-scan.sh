#!/usr/bin/env bash
# ~/.config/hypr/scripts/qr-scan.sh
# Single-instance guarded, but releases lock before wl-copy (wl-copy may fork).

set -euo pipefail

lock_dir="${XDG_RUNTIME_DIR:-/tmp}/awtarchy-locks"
mkdir -p "$lock_dir"
lock_file="$lock_dir/qr-scan.lock"

exec 9>"$lock_file"
if ! flock -n 9; then
  notify-send "QR Code" "Already running."
  exit 0
fi

for cmd in grim slurp zbarimg wl-copy notify-send mktemp; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "$cmd missing" >&2; exit 1; }
done

tempfile="$(mktemp --suffix=.png)"
cleanup() { rm -f "$tempfile"; }
trap cleanup EXIT

selection="$(slurp 2>/dev/null || true)"
if [[ -z "${selection:-}" ]]; then
  notify-send "QR Code" "Canceled."
  exit 0
fi

grim -g "$selection" "$tempfile"

qr_output="$(zbarimg --quiet "$tempfile" 2>/dev/null | sed 's/^QR-Code://g' | head -n1 || true)"

if [[ -z "${qr_output:-}" ]]; then
  notify-send "QR Code" "No QR code found."
  exit 0
fi

# RELEASE THE LOCK BEFORE wl-copy (wl-copy may fork and inherit FDs)
exec 9>&-

# Prefer --foreground if available, otherwise still works because lock FD is closed.
if wl-copy --help 2>&1 | grep -q -- '--foreground'; then
  wl-copy --foreground <<<"$qr_output"
else
  wl-copy <<<"$qr_output"
fi

notify-send "QR Code Scanned" "$qr_output"
