#!/usr/bin/env bash
# Native lock runs without the Hyprland frozen-frame screencopy transition.
set -euo pipefail
case "${1:-}" in
    cleanup|discard-prepared) exit 0 ;;
    *) printf 'Sway lock frame preparation is not supported\n' >&2; exit 1 ;;
esac
