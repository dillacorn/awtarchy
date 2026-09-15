#!/usr/bin/env bash
# Toggle the Awtarchy Quickshell power/session menu.

set -euo pipefail

SCRIPTS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts"
CAPTURE_HELPER="${SCRIPTS_DIR}/quickshell_lockscreen_capture.sh"
QS_BIN="${QS_BIN:-qs}"
POLL_INTERVAL="${AWTARCHY_LOCK_CAPTURE_POLL_INTERVAL:-0.05}"

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

restore_editor() {
    if (( editor_suppressed )); then
        "$QS_BIN" -c awtarchy ipc call lockcapture restoreEditor >/dev/null 2>&1 || true
        editor_suppressed=0
    fi
}

main() {
    local opened=""
    local accepted=""

    "$SCRIPTS_DIR/quickshell.sh" start >/dev/null

    # Map a transparent, focusable Power Menu surface before screenshot work
    # starts. L/H/R/S/O/Z/Escape can be retained immediately after SUPER+P
    # while the visible menu remains hidden from the secure transition capture.
    for _ in {1..20}; do
        opened="$("$QS_BIN" -c awtarchy ipc call powermenu begin 2>/dev/null | tail -n1 || true)"
        if [[ "$opened" == true || "$opened" == false ]]; then
            break
        fi
        sleep 0.01
    done

    # false means SUPER+P toggled an already-open Power Menu closed. If
    # Quickshell never became reachable, do not start screenshot work for a
    # menu that cannot own keyboard input.
    if [[ "$opened" != true ]]; then
        return 0
    fi

    if [[ -x "$CAPTURE_HELPER" ]]; then
        capture_dir="$("$CAPTURE_HELPER" stage-begin 2>/dev/null || true)"
        if [[ -n "$capture_dir" ]]; then
            # Escape or an explicit close may have happened while grim was
            # running. Stop instead of publishing a bundle that cannot be used.
            if ! capture_wanted; then
                cleanup_incomplete_capture
                return 0
            fi

            # In the normal case no Lockscreen Editor backing window is mapped,
            # so the first snapshot is already both the visible transition source
            # and a clean frozen desktop. Publish it without a second capture.
            hidden="$("$QS_BIN" -c awtarchy ipc call lockcapture editorHidden 2>/dev/null | tail -n1 || true)"
            if [[ "$hidden" == true ]]; then
                if capture_wanted \
                    && "$CAPTURE_HELPER" stage-promote-clean "$capture_dir" >/dev/null 2>&1; then
                    prepared=1
                fi
            elif "$QS_BIN" -c awtarchy ipc call lockcapture suppressEditor >/dev/null 2>&1; then
                # Editor-visible fallback preserves the approved two-snapshot
                # path: transition frame first, then a verified clean desktop.
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

    # Restore an editor only when the fallback path actually suppressed one.
    # The completed capture bundle stays private until Lock consumes it or the
    # Power Menu discards it.
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

    # If no action was already accepted, make the visual Power Menu visible.
    # reveal() is intentionally a no-op during an action handoff.
    "$QS_BIN" -c awtarchy ipc call powermenu reveal >/dev/null 2>&1 || true
}

main "$@"
