#!/usr/bin/env bash
# FILE: ~/.config/hypr/scripts/fuzzel_toggle.sh
# Toggle fuzzel on the same bind (close if running, otherwise launch).
# Reason: fuzzel is a layer-surface, so hyprctl clients-based togglers won't see it.

set -euo pipefail

# ---------------- user-tweakable ----------------
FUZZEL_BIN="${FUZZEL_BIN:-fuzzel}"             # or full path: /usr/bin/fuzzel
FUZZEL_PROC="${FUZZEL_PROC:-fuzzel}"           # process name for pgrep/pkill
KILL_TIMEOUT_MS="${KILL_TIMEOUT_MS:-250}"      # wait before SIGKILL fallback
DEFAULT_ARGS=( )                               # e.g.: ( --anchor=bottom-left )
# -----------------------------------------------

need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1" >&2; exit 127; }; }
need_cmd pgrep
need_cmd pkill

# If fuzzel is running, close it.
if pgrep -u "$UID" -x "$FUZZEL_PROC" >/dev/null 2>&1; then
  pkill -u "$UID" -x "$FUZZEL_PROC" >/dev/null 2>&1 || true

  # wait a bit, then SIGKILL if still alive
  step_ms=25
  steps=$(( (KILL_TIMEOUT_MS + step_ms - 1) / step_ms ))
  for _ in $(seq 1 "$steps"); do
    pgrep -u "$UID" -x "$FUZZEL_PROC" >/dev/null 2>&1 || exit 0
    sleep 0.025
  done

  pkill -KILL -u "$UID" -x "$FUZZEL_PROC" >/dev/null 2>&1 || true
  exit 0
fi

# Otherwise, launch it (script args override/extend DEFAULT_ARGS).
need_cmd "$FUZZEL_BIN"
nohup "$FUZZEL_BIN" "${DEFAULT_ARGS[@]}" "$@" >/dev/null 2>&1 &
disown
