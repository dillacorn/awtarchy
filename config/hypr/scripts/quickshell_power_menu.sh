#!/usr/bin/env bash
# Toggle the Awtarchy Quickshell power/session menu.

set -euo pipefail

SCRIPTS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts"
CAPTURE_HELPER="${SCRIPTS_DIR}/quickshell_lockscreen_capture.sh"
QS_BIN="${QS_BIN:-qs}"
POLL_INTERVAL="${AWTARCHY_LOCK_CAPTURE_POLL_INTERVAL:-0.05}"

"$SCRIPTS_DIR/quickshell.sh" start >/dev/null

# Map a transparent, focusable Power Menu surface before screenshot work starts.
# This makes L/H/R/S/O/Z/Escape responsive immediately after SUPER+P while the
# visible menu remains hidden from the secure transition capture.
opened=""
for _ in {1..20}; do
    opened="$("$QS_BIN" -c awtarchy ipc call powermenu begin 2>/dev/null | tail -n1 || true)"
    if [[ "$opened" == true || "$opened" == false ]]; then
        break
    fi
    sleep 0.01
done

# false means SUPER+P toggled an already-open Power Menu closed. If Quickshell
# never became reachable, do not start capture work for a menu that cannot own
# keyboard input.
if [[ "$opened" != true ]]; then
    return 0 2>/dev/null || true
fi

capture_dir=""
editor_suppressed=0
prepared=0
hidden=""
wanted=""

cleanup_incomplete_capture() {
    if [[ -n "$capture_dir" && -x "$CAPTURE_HELPER" ]]; then
        "$CAPTURE_HELPER" cleanup "$capture_dir" >/dev/null 2>&1 || true
        capture_dir=""
    fi
}

capture_wanted() {
    wanted="$("$QS_BIN" -c awtarchy ipc call powermenu captureWanted 2>/dev/null | tail -n1 || true)"
    [[ "$wanted" == true ]]
}

if [[ -x "$CAPTURE_HELPER" ]]; then
    capture_dir="$("$CAPTURE_HELPER" stage-begin 2>/dev/null || true)"
    if [[ -n "$capture_dir" ]]; then
        # The user may already have selected a non-lock action or pressed
        # Escape while grim was running. Stop here instead of publishing a
        # capture bundle that can no longer be consumed.
        if ! capture_wanted; then
            cleanup_incomplete_capture
            return 0 2>/dev/null || true
        fi

        # In the normal case no Lockscreen Editor backing window is mapped, so
        # the first snapshot is already both the visible transition source and
        # a clean frozen desktop. Publish it immediately instead of hiding UI,
        # polling, and paying for a second full-resolution screenshot pass.
        hidden="$("$QS_BIN" -c awtarchy ipc call lockcapture editorHidden 2>/dev/null | tail -n1 || true)"
        if [[ "$hidden" == true ]]; then
            if capture_wanted \
                && "$CAPTURE_HELPER" stage-promote-clean "$capture_dir" >/dev/null 2>&1; then
                prepared=1
            fi
        elif "$QS_BIN" -c awtarchy ipc call lockcapture suppressEditor >/dev/null 2>&1; then
            # Editor-visible fallback preserves the approved two-snapshot path:
            # transition frame first, then a verified clean desktop frame.
            editor_suppressed=1
            for _ in {1..80}; do
                if ! capture_wanted; then
                    break
                fi
                hidden="$("$QS_BIN" -c awtarchy ipc call lockcapture editorHidden 2>/dev/null | tail -n1 || true)"
                if [[ "$hidden" == true ]]; then
                    if capture_wanted \
                        && "$CAPTURE_HELPER" stage-complete "$capture_dir" >/dev/null 2>&1; then
                        prepared=1
                    fi
                    break
                fi
                sleep "$POLL_INTERVAL"
            done
        fi
    fi
fi

restore_editor() {
    if (( editor_suppressed )); then
        "$QS_BIN" -c awtarchy ipc call lockcapture restoreEditor >/dev/null 2>&1 || true
        editor_suppressed=0
    fi
}

# Restore an editor only when the fallback path actually suppressed one. The
# completed capture bundle stays private until Lock consumes it or PowerMenu
# discards it.
restore_editor

if (( prepared )); then
    accepted="$("$QS_BIN" -c awtarchy ipc call powermenu capturePrepared 2>/dev/null | tail -n1 || true)"
    if [[ "$accepted" != true ]]; then
        "$CAPTURE_HELPER" discard-prepared >/dev/null 2>&1 || true
    fi
else
    cleanup_incomplete_capture
    "$QS_BIN" -c awtarchy ipc call powermenu captureFailed >/dev/null 2>&1 || true
fi

# If no action was already accepted, make the visual Power Menu visible now.
# reveal() is intentionally a no-op while an action handoff is in progress.
"$QS_BIN" -c awtarchy ipc call powermenu reveal >/dev/null 2>&1 || true
