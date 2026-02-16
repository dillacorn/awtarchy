#!/usr/bin/env bash
# github.com/dillacorn/awtarchy/tree/main/config/hypr/scripts
# ~/.config/hypr/scripts/gif_capture.sh

set -euo pipefail

# --- config ---
FPS=10
SCALE_WIDTH=640
MAX_DURATION=600
SAVE_DIR="$HOME/Videos/Gifs"

# --- deps ---
for cmd in wf-recorder slurp ffmpeg notify-send; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "$cmd is required." >&2; exit 1; }
done
mkdir -p "$SAVE_DIR"

# --- paths (stable names so the hotkey can toggle) ---
RBASE="/tmp/gif-record-$USER"
PID_FILE="$RBASE.pid"      # wf-recorder PID
W_PID_FILE="$RBASE.wpid"   # watchdog PID
MP4_FILE="$RBASE.mp4"
PAL_FILE="$RBASE-palette.png"

umask 177

stop_recording() {
  # stop recorder if running
  if [[ -f "$PID_FILE" ]]; then
    REC_PID="$(cat "$PID_FILE" || true)"
    if [[ -n "${REC_PID:-}" ]] && kill -0 "$REC_PID" 2>/dev/null; then
      kill -TERM "$REC_PID" 2>/dev/null || true
      # wait for exit (max ~3s), then hard kill if needed
      for _ in 1 2 3 4 5 6; do
        kill -0 "$REC_PID" 2>/dev/null || break
        sleep 0.5
      done
      kill -KILL "$REC_PID" 2>/dev/null || true
    fi
    rm -f "$PID_FILE"
  fi

  # stop watchdog
  if [[ -f "$W_PID_FILE" ]]; then
    W_PID="$(cat "$W_PID_FILE" || true)"
    [[ -n "${W_PID:-}" ]] && kill -TERM "$W_PID" 2>/dev/null || true
    rm -f "$W_PID_FILE"
  fi
}

compile_gif() {
  # small grace to ensure mp4 gets closed
  sleep 0.25

  if [[ ! -s "$MP4_FILE" ]]; then
    rm -f "$PAL_FILE" "$MP4_FILE" 2>/dev/null || true
    notify-send "GIF Recording" "No video captured."
    exit 0
  fi

  notify-send "GIF Recording" "Compiling…"

  ffmpeg -v error -i "$MP4_FILE" -filter_complex \
    "fps=${FPS},scale=${SCALE_WIDTH}:-1:flags=lanczos,palettegen=stats_mode=full" \
    -y "$PAL_FILE"

  umask 077
  OUT="$SAVE_DIR/$(date +%Y%m%d-%H%M%S).gif"

  ffmpeg -v error -i "$MP4_FILE" -i "$PAL_FILE" -filter_complex \
    "fps=${FPS},scale=${SCALE_WIDTH}:-1:flags=lanczos,paletteuse=dither=sierra2_4a" \
    -y "$OUT"

  rm -f "$PAL_FILE" "$MP4_FILE" 2>/dev/null || true
  notify-send "GIF Saved" "Saved to $OUT"
}

# --- toggle logic ---
if [[ -f "$PID_FILE" ]]; then
  stop_recording
  compile_gif
  exit 0
fi

# start branch
COORDS="$(slurp || true)"
[[ -n "${COORDS:-}" ]] || exit 1

# clean any stale files
rm -f "$MP4_FILE" "$PAL_FILE" 2>/dev/null || true

notify-send "GIF Recording" "Recording started. Press the hotkey again to stop."

# start recorder in background and record its REAL pid
wf-recorder -g "$COORDS" -f "$MP4_FILE" >/dev/null 2>&1 &
REC_PID=$!
echo "$REC_PID" > "$PID_FILE"

# watchdog to enforce MAX_DURATION
(
  for _ in $(seq $MAX_DURATION); do
    kill -0 "$REC_PID" 2>/dev/null || exit 0
    sleep 1
  done
  kill -TERM "$REC_PID" 2>/dev/null || true
) &
echo $! > "$W_PID_FILE"

disown
