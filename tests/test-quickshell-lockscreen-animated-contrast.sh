#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$ROOT/config/hypr/scripts/quickshell_lockscreen_contrast.sh"
EDITOR="$ROOT/config/quickshell/awtarchy/LockscreenEditor.qml"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
require_text() { grep -Fq -- "$2" "$1" || fail "$3"; }
reject_text() { ! grep -Fq -- "$2" "$1" || fail "$3"; }

require_text "$HELPER" 'WALLPAPER_SAMPLE=""' \
    'contrast helper has no stable representative wallpaper sample state'
require_text "$HELPER" 'function prepare_wallpaper_sample()' \
    'contrast helper has no one-shot animated-media sample preparation'
require_text "$HELPER" '*.gif)' \
    'contrast helper has no deterministic GIF representative-frame path'
require_text "$HELPER" 'magick "${image}[0]" "$output"' \
    'GIF contrast does not use the deterministic first frame'
require_text "$HELPER" '*.mp4)' \
    'contrast helper has no deterministic MP4 representative-frame path'
require_text "$HELPER" 'ffmpeg -v error -nostdin -i "$image" -map 0:v:0 -frames:v 1 -y "$output"' \
    'MP4 contrast does not extract one deterministic representative frame'
require_text "$HELPER" 'prepare_wallpaper_sample "$wallpaper"' \
    'animated wallpaper sample is never prepared'
require_text "$HELPER" 'sample_wallpaper_contrast "$WALLPAPER_SAMPLE" "$layout" "$element"' \
    'per-element contrast does not reuse the single representative frame'
require_text "$HELPER" 'rm -rf -- "$TMP_DIR"' \
    'temporary representative-frame directory is not cleaned up'
reject_text "$HELPER" '-stream_loop' \
    'contrast helper unexpectedly loops animated media during sampling'
require_text "$HELPER" '--arg wallpaper "$wallpaper"' \
    'contrast cache no longer records the original selected media path'

prepare_count="$(grep -Fc -- 'prepare_wallpaper_sample "$wallpaper"' "$HELPER")"
[[ "$prepare_count" -eq 1 ]] || fail 'representative media frame is prepared more than once per contrast refresh'
prepare_line="$(grep -Fn -- 'prepare_wallpaper_sample "$wallpaper"' "$HELPER" | cut -d: -f1)"
loop_line="$(grep -Fn -- 'for element in $ELEMENTS; do' "$HELPER" | cut -d: -f1)"
[[ -n "$prepare_line" && -n "$loop_line" && "$prepare_line" -lt "$loop_line" ]] \
    || fail 'representative frame is not prepared once before per-element sampling begins'

require_text "$EDITOR" 'label: "Add Media"' \
    'custom animated/static element picker is still labeled Add Image'
require_text "$EDITOR" 'label: "Remove Media"' \
    'custom animated/static element removal is still labeled Remove Image'
require_text "$EDITOR" 'text: "Media Opacity"' \
    'custom media opacity control is still image-specific'
require_text "$EDITOR" 'Custom media are local presentation-only elements.' \
    'custom element helper text still describes media as images only'
require_text "$EDITOR" 'Opening custom media picker…' \
    'custom media picker status is still image-specific'
require_text "$EDITOR" 'Awtwall returned an invalid local media' \
    'custom picker validation status is still image-specific'

printf '%s\n' 'PASS: lockscreen animated contrast and custom media wording contracts'
