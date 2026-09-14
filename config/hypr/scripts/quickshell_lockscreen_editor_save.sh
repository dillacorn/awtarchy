#!/usr/bin/env bash
set -euo pipefail

CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"
CACHE_HOME="${XDG_CACHE_HOME:-${HOME}/.cache}"
STATE_BACKEND="${CONFIG_HOME}/hypr/scripts/quickshell_application_state.sh"
STATE_FILE="${CACHE_HOME}/awtarchy/quickshell-state.json"
ZONEINFO_ROOT="/usr/share/zoneinfo"
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

layout_input="${1}"
custom_images_input="${13:-[]}"
visualizer_input="${14-}"
if [[ -z "$visualizer_input" ]]; then
    visualizer_input='{}'
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
        def clamp($value; $fallback; $minimum; $maximum):
            (($value | tonumber?) // $fallback) as $number
            | if $number < $minimum then $minimum
              elif $number > $maximum then $maximum
              else $number end;
        if ($candidate | type) != "array"
            or ($candidate | length) > 12
            or ([ $candidate[].id ] | length) != ([ $candidate[].id ] | unique | length)
            or any($candidate[];
                (. | type) != "object"
                or ((.id // "") | type) != "string"
                or ((.id // "") | test("^timezone-[A-Za-z0-9_-]{1,64}$") | not)
                or ((.timezone // "UTC") | type) != "string"
                or ((.timezone // "UTC") | startswith("/") or contains("..") or test("[\\u0000-\\u001f\\u007f-\\u009f]"))
                or ((.color // "auto") | type) != "string"
                or (((.color // "auto") == "auto" or ((.color // "") | test("^#[0-9A-Fa-f]{6}$"))) | not)
            )
        then error("invalid timezone clocks")
        else
            [$candidate[] | {
                id: .id,
                timezone: (.timezone // "UTC"),
                format: (if ((.format // "24h") | ascii_downcase) == "12h" then "12h" else "24h" end),
                x: clamp(.x; 0.5; 0.05; 0.95),
                y: clamp(.y; 0.6; 0.08; 0.92),
                scale: clamp(.scale; 1; 0.5; 100),
                stretch_x: clamp(.stretch_x; 1; 0.25; 4),
                stretch_y: clamp(.stretch_y; 1; 0.25; 4),
                opacity: clamp(.opacity; 100; 0; 100),
                rotation: clamp(.rotation; 0; -180; 180),
                color: ((.color // "auto") | ascii_downcase),
                visible: (if (.visible | type) == "boolean" then .visible else true end)
            }]
        end
    '
}

normalize_custom_texts() {
    jq -ce -n --argjson candidate "$1" '
        def clamp($value; $fallback; $minimum; $maximum):
            (($value | tonumber?) // $fallback) as $number
            | if $number < $minimum then $minimum
              elif $number > $maximum then $maximum
              else $number end;
        if ($candidate | type) != "array"
            or ($candidate | length) > 12
            or ([ $candidate[].id ] | length) != ([ $candidate[].id ] | unique | length)
            or any($candidate[];
                (. | type) != "object"
                or ((.id // "") | type) != "string"
                or ((.id // "") | test("^text-[A-Za-z0-9_-]{1,64}$") | not)
                or ((.text // "Custom Text") | type) != "string"
                or (((.text // "") | length) > 4096)
                or ((.variants // []) | type) != "array"
                or (((.variants // []) | length) > 32)
                or any((.variants // [])[]; type != "string" or length > 4096)
                or ((.alignment // "center") as $alignment | (["left", "center", "right"] | index($alignment)) == null)
                or ((.color // "auto") | type) != "string"
                or (((.color // "auto") == "auto" or ((.color // "") | test("^#[0-9A-Fa-f]{6}$"))) | not)
            )
        then error("invalid custom text")
        else
            [$candidate[] | {
                id: .id,
                text: (.text // "Custom Text"),
                variants: (.variants // []),
                randomize: (if (.randomize | type) == "boolean" then .randomize else false end),
                alignment: (.alignment // "center"),
                x: clamp(.x; 0.5; 0.05; 0.95),
                y: clamp(.y; 0.55; 0.08; 0.92),
                scale: clamp(.scale; 1; 0.5; 100),
                stretch_x: clamp(.stretch_x; 1; 0.25; 4),
                stretch_y: clamp(.stretch_y; 1; 0.25; 4),
                opacity: clamp(.opacity; 100; 0; 100),
                rotation: clamp(.rotation; 0; -180; 180),
                color: ((.color // "auto") | ascii_downcase),
                visible: (if (.visible | type) == "boolean" then .visible else true end)
            }]
        end
    '
}

backend_layout="$(jq -ce 'with_entries(.value |= del(.rotation))' <<<"$layout_input")"
backend_custom_images="$(jq -ce '[.[] | del(.spawn_timing)]' <<<"$custom_images_input")"
backend_visualizer="$(jq -ce 'del(.rotation)' <<<"$visualizer_input")"
timezone_clocks="$(normalize_timezone_clocks "$timezone_clocks_input")"
custom_texts="$(normalize_custom_texts "$custom_texts_input")"

while IFS= read -r zone; do
    [[ -n "$zone" && -f "${ZONEINFO_ROOT}/${zone}" ]] || {
        printf 'invalid timezone clock zone: %s\n' "$zone" >&2
        exit 2
    }
done < <(jq -r '.[].timezone' <<<"$timezone_clocks")

backend_args=("${@:1:19}")
backend_args[0]="$backend_layout"
backend_args[12]="$backend_custom_images"
backend_args[13]="$backend_visualizer"
bash "$STATE_BACKEND" save-lockscreen-editor "${backend_args[@]}"

mkdir -p -- "$(dirname -- "$STATE_FILE")"
tmp_file="$(mktemp "${STATE_FILE}.tmp.XXXXXX")"

jq \
    --argjson layout_extensions "$layout_input" \
    --argjson image_extensions "$custom_images_input" \
    --argjson visualizer_extension "$visualizer_input" \
    --arg logo_animation "$logo_animation" \
    --arg mask_mode "$mask_mode" \
    --arg mask_character "$mask_character" \
    --arg clock_format "$clock_format" \
    --argjson timezone_clocks "$timezone_clocks" \
    --argjson custom_texts "$custom_texts" '
    def clamp($value; $fallback; $minimum; $maximum):
        (($value | tonumber?) // $fallback) as $number
        | if $number < $minimum then $minimum
          elif $number > $maximum then $maximum
          else $number end;
    .lockscreen_layout = (
        .lockscreen_layout
        | with_entries(
            .key as $key
            | .value.rotation = clamp($layout_extensions[$key].rotation; 0; -180; 180)
        )
    )
    | .lockscreen_custom_images = [
        .lockscreen_custom_images[] as $base
        | ($image_extensions | map(select(.id == $base.id)) | .[0] // {}) as $extension
        | $base + {
            spawn_timing: (if $extension.spawn_timing == "after-logo" then "after-logo" else "during-logo" end)
        }
    ]
    | .lockscreen_visualizer = (.lockscreen_visualizer + {
        rotation: clamp($visualizer_extension.rotation; 0; -180; 180)
    })
    | .lockscreen_animation = $logo_animation
    | .lockscreen_password_mask_mode = $mask_mode
    | .lockscreen_password_mask_character = $mask_character
    | .lockscreen_clock_format = $clock_format
    | .lockscreen_timezone_clocks = $timezone_clocks
    | .lockscreen_custom_texts = $custom_texts
    ' "$STATE_FILE" >"$tmp_file"

chmod --reference="$STATE_FILE" "$tmp_file" 2>/dev/null || true
mv -f -- "$tmp_file" "$STATE_FILE"
tmp_file=""
