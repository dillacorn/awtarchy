#!/usr/bin/env bash
# Jay reads XCursor settings on session start; no Hyprland live cursor dispatch.
set -euo pipefail
case "${1:-}" in
    reapply|status)
        # Shared state is left alone. Jay picks up the user-selected cursor
        # through XCURSOR_THEME on the next Jay login.
        exit 0 ;;
    *)
        printf 'Jay: live compositor cursor switching is not ported\n' >&2
        exit 1 ;;
esac
