#!/usr/bin/env bash
# Sway reads XCursor settings on session start; no Hyprland live cursor dispatch.
set -euo pipefail
case "${1:-}" in
    reapply|status)
        # Shared state is left alone. Sway picks up the user-selected cursor
        # through XCURSOR_THEME on the next Sway login.
        exit 0 ;;
    *)
        printf 'Sway: live compositor cursor switching is not ported\n' >&2
        exit 1 ;;
esac
