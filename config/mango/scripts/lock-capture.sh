#!/usr/bin/env bash
# Prepared lock screenshots are disabled while Mango's native lock is unported.
set -euo pipefail
case "${1:-}" in
    discard-prepared) ;;
    *)
        printf 'Mango: prepared Quickshell lock capture is unavailable.\n' >&2
        false
        ;;
esac
