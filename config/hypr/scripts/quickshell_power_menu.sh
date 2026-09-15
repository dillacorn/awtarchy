#!/usr/bin/env bash
# Toggle the Awtarchy Quickshell power/session menu.

set -euo pipefail

SCRIPTS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts"
CAPTURE_HELPER="${SCRIPTS_DIR}/quickshell_lockscreen_capture.sh"
QS_BIN="${QS_BIN:-qs}"
POLL_INTERVAL="${AWTARCHY_LOCK_CAPTURE_POLL_INTERVAL:-0.05}"

"$SCRIPTS_DIR/quickshell.sh" start >/dev/null

capture_dir=""
editor_suppressed=0
prepared=0

restore_editor() {
    if (( editor_suppressed )); then
        "$QS_BIN" -c awtarchy ipc call lockcapture restoreEditor >/dev/null 2>&1 || true
        editor_suppressed=0
    fi
}

cleanup_incomplete_capture() {
    if [[ -n "$capture_dir" && -x "$CAPTURE_HELPER" ]]; then
        "$CAPTURE_HELPER" cleanup "$capture_dir" >/dev/null 2>&1 || true
        capture_dir=""
    fi
}

if [[ -x "$CAPTURE_HELPER" ]]; then
    capture_dir="$($CAPTURE_HELPER stage-begin 2>/dev/null || true)"
    if [[ -n "$capture_dir" ]]; then
        if "$QS_BIN" -c awtarchy ipc call lockcapture suppressEditor >/dev/null 2>&1; then
            editor_suppressed=1
            for _ in {1..80}; do
                hidden="$($QS_BIN -c awtarchy ipc call lockcapture editorHidden 2>/dev/null | tail -n1 || true)"
                if [[ "$hidden" == true ]]; then
                    if "$CAPTURE_HELPER" stage-complete "$capture_dir" >/dev/null 2>&1; then
                        prepared=1
                    fi
                    break
                fi
                sleep "$POLL_INTERVAL"
            done
        fi
    fi
fi

# Restore the editor before the power menu appears. The completed capture bundle,
# when present, stays private until Lock consumes it or PowerMenu discards it.
restore_editor
if (( ! prepared )); then
    cleanup_incomplete_capture
fi

"$QS_BIN" -c awtarchy ipc call powermenu toggle
