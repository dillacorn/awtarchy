#!/usr/bin/env bash
set -euo pipefail

CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"
CACHE_HOME="${XDG_CACHE_HOME:-${HOME}/.cache}"
STATE_BACKEND="${CONFIG_HOME}/hypr/scripts/quickshell_application_state.sh"
STATE_FILE="${CACHE_HOME}/awtarchy/quickshell-state.json"

if [[ $# -ne 23 ]]; then
    printf 'usage: %s <19 existing editor fields> <logo-animation> <mask-mode> <mask-character> <clock-format>\n' "${0##*/}" >&2
    return 2 2>/dev/null || false
fi

logo_animation="${20}"
mask_mode="${21}"
mask_character="${22}"
clock_format="${23}"

case "$logo_animation" in
    random|swarm|edges|center|split|off) ;;
    *) logo_animation='split' ;;
esac

case "$mask_mode" in
    squares|dots|custom) ;;
    *) mask_mode='squares' ;;
esac

case "$clock_format" in
    24h|12h) ;;
    *) clock_format='24h' ;;
esac

mask_character="$({
    jq -nr --arg value "$mask_character" '
        $value
        | explode
        | map(select(. > 32 and (. < 127 or . > 159)))
        | (.[0] // 8226)
        | [.]
        | implode
    '
})"

bash "$STATE_BACKEND" save-lockscreen-editor "${@:1:19}"

mkdir -p -- "$(dirname -- "$STATE_FILE")"
tmp_file="$(mktemp "${STATE_FILE}.tmp.XXXXXX")"
trap 'rm -f -- "$tmp_file"' RETURN

jq \
    --arg logo_animation "$logo_animation" \
    --arg mask_mode "$mask_mode" \
    --arg mask_character "$mask_character" \
    --arg clock_format "$clock_format" \
    '.lockscreen_animation = $logo_animation
     | .lockscreen_password_mask_mode = $mask_mode
     | .lockscreen_password_mask_character = $mask_character
     | .lockscreen_clock_format = $clock_format' \
    "$STATE_FILE" >"$tmp_file"

chmod --reference="$STATE_FILE" "$tmp_file" 2>/dev/null || true
mv -f -- "$tmp_file" "$STATE_FILE"
trap - RETURN
