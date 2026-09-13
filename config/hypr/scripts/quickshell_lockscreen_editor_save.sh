#!/usr/bin/env bash
set -euo pipefail

CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"
CACHE_HOME="${XDG_CACHE_HOME:-${HOME}/.cache}"
STATE_BACKEND="${CONFIG_HOME}/hypr/scripts/quickshell_application_state.sh"
STATE_FILE="${CACHE_HOME}/awtarchy/quickshell-state.json"
tmp_file=""

cleanup_tmp() {
    if [[ -n "$tmp_file" ]]; then
        rm -f -- "$tmp_file" >/dev/null 2>&1 || true
    fi
}
trap cleanup_tmp EXIT

if [[ $# -ne 23 && $# -ne 25 ]]; then
    printf 'usage: %s <19 existing editor fields> <logo-animation> <mask-mode> <mask-character> <clock-format> [timezone-clocks-json custom-texts-json]\n' "${0##*/}" >&2
    false
fi

logo_animation="${20}"
mask_mode="${21}"
mask_character="${22}"
clock_format="${23}"
timezone_clocks_input="${24:-[]}"
custom_texts_input="${25:-[]}"

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

normalize_timezone_clocks() {
    jq -ce -n --argjson candidate "$1" '
        def clamp($value; $minimum; $maximum): [$minimum, ($value // 0), $maximum] | sort | .[1];
        if ($candidate | type) != "array" or ($candidate | length) > 12 then
            error("invalid timezone clocks")
        else
            [$candidate[]
                | select(type == "object")
                | {
                    id: ((.id // "") | tostring),
                    timezone: ((.timezone // "UTC") | tostring),
                    format: (if ((.format // "24h") | ascii_downcase) == "12h" then "12h" else "24h" end),
                    x: clamp((.x | tonumber?); 0.05; 0.95),
                    y: clamp((.y | tonumber?); 0.08; 0.92),
                    scale: clamp((.scale | tonumber?); 0.5; 100),
                    stretch_x: clamp((.stretch_x | tonumber?); 0.25; 4),
                    stretch_y: clamp((.stretch_y | tonumber?); 0.25; 4),
                    opacity: clamp((.opacity | tonumber?); 0; 100),
                    rotation: clamp((.rotation | tonumber?); -180; 180),
                    color: ((.color // "auto") | tostring),
                    visible: (if (.visible | type) == "boolean" then .visible else true end)
                }
            ]
        end
    '
}

normalize_custom_texts() {
    jq -ce -n --argjson candidate "$1" '
        def clamp($value; $minimum; $maximum): [$minimum, ($value // 0), $maximum] | sort | .[1];
        if ($candidate | type) != "array" or ($candidate | length) > 12 then
            error("invalid custom text")
        else
            [$candidate[]
                | select(type == "object")
                | {
                    id: ((.id // "") | tostring),
                    text: ((.text // "Custom Text") | tostring),
                    variants: (if (.variants | type) == "array" then [.variants[] | tostring] else [] end),
                    randomize: (if (.randomize | type) == "boolean" then .randomize else false end),
                    alignment: (if (.alignment == "left" or .alignment == "right") then .alignment else "center" end),
                    x: clamp((.x | tonumber?); 0.05; 0.95),
                    y: clamp((.y | tonumber?); 0.08; 0.92),
                    scale: clamp((.scale | tonumber?); 0.5; 100),
                    stretch_x: clamp((.stretch_x | tonumber?); 0.25; 4),
                    stretch_y: clamp((.stretch_y | tonumber?); 0.25; 4),
                    opacity: clamp((.opacity | tonumber?); 0; 100),
                    rotation: clamp((.rotation | tonumber?); -180; 180),
                    color: ((.color // "auto") | tostring),
                    visible: (if (.visible | type) == "boolean" then .visible else true end)
                }
            ]
        end
    '
}

timezone_clocks="$(normalize_timezone_clocks "$timezone_clocks_input")"
custom_texts="$(normalize_custom_texts "$custom_texts_input")"

bash "$STATE_BACKEND" save-lockscreen-editor "${@:1:19}"

mkdir -p -- "$(dirname -- "$STATE_FILE")"
tmp_file="$(mktemp "${STATE_FILE}.tmp.XXXXXX")"

jq \
    --arg logo_animation "$logo_animation" \
    --arg mask_mode "$mask_mode" \
    --arg mask_character "$mask_character" \
    --arg clock_format "$clock_format" \
    --argjson timezone_clocks "$timezone_clocks" \
    --argjson custom_texts "$custom_texts" \
    '.lockscreen_animation = $logo_animation
     | .lockscreen_password_mask_mode = $mask_mode
     | .lockscreen_password_mask_character = $mask_character
     | .lockscreen_clock_format = $clock_format
     | .lockscreen_timezone_clocks = $timezone_clocks
     | .lockscreen_custom_texts = $custom_texts' \
    "$STATE_FILE" >"$tmp_file"

chmod --reference="$STATE_FILE" "$tmp_file" 2>/dev/null || true
mv -f -- "$tmp_file" "$STATE_FILE"
tmp_file=""
