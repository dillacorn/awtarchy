#!/usr/bin/env bash
set -euo pipefail
mode="${1:-}"
[[ "$mode" == area || "$mode" == screen ]] || { printf 'Usage: capture.sh area|screen\n' >&2; exit 2; }
directory="${XDG_PICTURES_DIR:-$HOME/Pictures}/Screenshots"
mkdir -p -- "$directory"
target="$(mktemp "$directory/mango-$(date +%Y%m%d-%H%M%S)-XXXXXX.png")"
if [[ "$mode" == area ]]; then
    region="$(slurp)" || { rm -f -- "$target"; exit 1; }
    grim -g "$region" "$target" || { rm -f -- "$target"; exit 1; }
else
    grim "$target" || { rm -f -- "$target"; exit 1; }
fi
printf 'Screenshot: %s\n' "$target"
