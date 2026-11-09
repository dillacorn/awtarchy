#!/usr/bin/env bash
# Mango screenshot adapter; keep Hyprland's capture helpers untouched.
set -euo pipefail

mode="${1:-}"
case "$mode" in
    area|screen|output) ;;
    *)
        printf 'Usage: capture.sh {area|screen|output}\n' >&2
        exit 2
        ;;
esac

directory="${XDG_PICTURES_DIR:-$HOME/Pictures}/Screenshots"
mkdir -p -- "$directory"

region=""
case "$mode" in
    area)
        region="$(slurp)" || exit 1
        [[ -n "$region" ]] || exit 1
        ;;
    output)
        # Select a single output, matching Awtarchy's old display and
        # fullscreen screenshot actions without Hyprland's frame freeze.
        region="$(slurp -o -r)" || exit 1
        [[ -n "$region" ]] || exit 1
        ;;
esac

target="$(mktemp "$directory/mango-$(date +%Y%m%d-%H%M%S)-XXXXXX.png")" || exit 1
if [[ -n "$region" ]]; then
    grim -g "$region" "$target" || { rm -f -- "$target"; exit 1; }
else
    grim "$target" || { rm -f -- "$target"; exit 1; }
fi

printf 'Screenshot: %s\n' "$target"
