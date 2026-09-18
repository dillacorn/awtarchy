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

profile_mode=false
if [[ "${1:-}" == "--profiles" ]]; then
    [[ $# -eq 3 || $# -eq 4 ]] || {
        printf 'usage: %s --profiles <monitor-profiles-json> <last-edited-profile-json> [saved-profiles-json]\n' "${0##*/}" >&2
        false
    }
    profile_mode=true
elif [[ $# -ne 23 && $# -ne 25 ]]; then
    printf 'usage: %s <19 existing editor fields> <logo-animation> <mask-mode> <mask-character> <clock-format> [timezone-clocks-json custom-texts-json]\n' "${0##*/}" >&2
    false
fi

if [[ "$profile_mode" == false ]]; then
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

fi

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
                or ((.timezone // "UTC") | startswith("/") or contains("..") or test("[[:cntrl:]]"))
                or ((.color // "auto") | type) != "string"
                or (((.color // "auto") == "auto" or ((.color // "") | test("^#[0-9A-Fa-f]{6}$"))) | not)
            )
        then error("invalid timezone clocks")
        else
            [$candidate[] | {
                id: .id,
                timezone: (.timezone // "UTC"),
                format: (if ((.format // "24h") | ascii_downcase) == "12h" then "12h" else "24h" end),
                show_label: (if (.show_label | type) == "boolean" then .show_label else true end),
                x: clamp(.x; 0.5; 0.05; 0.95),
                y: clamp(.y; 0.6; 0.08; 0.92),
                scale: clamp(.scale; 1; 0.5; 100),
                stretch_x: clamp(.stretch_x; 1; 0.25; 4),
                stretch_y: clamp(.stretch_y; 1; 0.25; 4),
                opacity: clamp(.opacity; 100; 5; 100),
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
                opacity: clamp(.opacity; 100; 5; 100),
                rotation: clamp(.rotation; 0; -180; 180),
                color: ((.color // "auto") | ascii_downcase),
                visible: (if (.visible | type) == "boolean" then .visible else true end)
            }]
        end
    '
}

custom_image_entry_schema_valid() {
    jq -e -n --argjson candidate "$1" '
        def allowed_keys: ["id", "opacity", "path", "rotation", "scale", "spawn_animation", "spawn_timing", "stretch_x", "stretch_y", "visible", "x", "y"];
        def spawns: ["none", "pixel-warp", "closest-edge", "top", "bottom", "left", "right"];
        ($candidate | type) == "object"
        and (($candidate | keys - allowed_keys | length) == 0)
        and ($candidate.id | type) == "string"
        and ($candidate.id | test("^image-[A-Za-z0-9_-]{1,64}$"))
        and ($candidate.path | type) == "string"
        and ($candidate.path | startswith("/"))
        and ($candidate.path | contains("://") | not)
        and ($candidate.path | test("[[:cntrl:]]") | not)
        and ($candidate.x | type) == "number" and $candidate.x >= 0.05 and $candidate.x <= 0.95
        and ($candidate.y | type) == "number" and $candidate.y >= 0.08 and $candidate.y <= 0.92
        and ($candidate.scale | type) == "number" and $candidate.scale >= 0.50 and $candidate.scale <= 100.00
        and ($candidate.stretch_x | type) == "number" and $candidate.stretch_x >= 0.25 and $candidate.stretch_x <= 4.00
        and ($candidate.stretch_y | type) == "number" and $candidate.stretch_y >= 0.25 and $candidate.stretch_y <= 4.00
        and ($candidate.opacity | type) == "number" and $candidate.opacity >= 5 and $candidate.opacity <= 100
        and (($candidate.rotation // 0) | type) == "number"
        and ($candidate.rotation // 0) >= -180 and ($candidate.rotation // 0) <= 180
        and (($candidate.spawn_animation // "none") | type) == "string"
        and (($candidate.spawn_animation // "none") as $spawn | (spawns | index($spawn) != null))
        and ($candidate.visible | type) == "boolean"
    ' >/dev/null 2>&1
}

filter_stale_custom_images() {
    local value="$1" candidate count index entry path

    # Keep malformed input intact so the authoritative backend still rejects it.
    # Only schema-valid optional images whose local file disappeared are removed.
    if ! candidate="$(jq -ce 'if type == "array" then . else empty end' <<<"$value" 2>/dev/null)"; then
        printf '%s' "$value"
        return 0
    fi

    count="$(jq -r 'length' <<<"$candidate")"
    for ((index = count - 1; index >= 0; --index)); do
        entry="$(jq -c --argjson index "$index" '.[$index]' <<<"$candidate")"
        custom_image_entry_schema_valid "$entry" || continue
        path="$(jq -r '.path' <<<"$entry")"
        if [[ ! -f "$path" || ! -r "$path" ]]; then
            candidate="$(jq -c --argjson index "$index" 'del(.[$index])' <<<"$candidate")"
        fi
    done

    printf '%s' "$candidate"
}

filter_stale_timezone_clocks() {
    local candidate="$1" count index zone

    # Schema is already normalized before this point. A missing zoneinfo file is
    # therefore an external-resource disappearance, not malformed clock data.
    count="$(jq -r 'length' <<<"$candidate")"
    for ((index = count - 1; index >= 0; --index)); do
        zone="$(jq -r --argjson index "$index" '.[$index].timezone' <<<"$candidate")"
        if [[ -z "$zone" || ! -f "${ZONEINFO_ROOT}/${zone}" ]]; then
            candidate="$(jq -c --argjson index "$index" 'del(.[$index])' <<<"$candidate")"
        fi
    done

    printf '%s' "$candidate"
}

repair_profile_optional_resources() {
    local value="$1" candidate images repaired background wallpaper
    if ! candidate="$(jq -ce 'if type == "object" then . else empty end' <<<"$value" 2>/dev/null)"; then
        printf '%s' "$value"
        return 0
    fi

    images="$(jq -c '.lockscreen_custom_images // []' <<<"$candidate")"
    repaired="$(filter_stale_custom_images "$images")"
    if jq -e 'type == "array"' >/dev/null 2>&1 <<<"$repaired"; then
        candidate="$(jq -c --argjson images "$repaired" '.lockscreen_custom_images = $images' <<<"$candidate")"
    fi

    background="$(jq -r '.lockscreen_background // ""' <<<"$candidate")"
    wallpaper="$(jq -r '.lockscreen_wallpaper_path // ""' <<<"$candidate")"
    if [[ "$background" == "wallpaper" ]]; then
        if [[ -z "$wallpaper" ]]; then
            candidate="$(jq -c '.lockscreen_background = "black" | .lockscreen_wallpaper_path = ""' <<<"$candidate")"
        elif [[ "$wallpaper" == /* && "$wallpaper" != *://* \
            && "$wallpaper" != *$'\n'* && "$wallpaper" != *$'\r'* \
            && ( ! -f "$wallpaper" || ! -r "$wallpaper" ) ]]; then
            candidate="$(jq -c '.lockscreen_background = "black" | .lockscreen_wallpaper_path = ""' <<<"$candidate")"
        fi
    fi

    printf '%s' "$candidate"
}

repair_override_profiles() {
    local value="$1" candidate result key profile repaired
    if ! candidate="$(jq -ce 'if type == "object" then . else empty end' <<<"$value" 2>/dev/null)"; then
        printf '%s' "$value"
        return 0
    fi
    result='{}'
    while IFS= read -r key; do
        profile="$(jq -c --arg key "$key" '.[$key]' <<<"$candidate")"
        repaired="$(repair_profile_optional_resources "$profile")"
        if jq -e 'type == "object"' >/dev/null 2>&1 <<<"$repaired"; then
            result="$(jq -c --arg key "$key" --argjson profile "$repaired" '. + {($key): $profile}' <<<"$result")"
        else
            result="$(jq -c --arg key "$key" --argjson profile "$profile" '. + {($key): $profile}' <<<"$result")"
        fi
    done < <(jq -r 'keys[]' <<<"$candidate")
    printf '%s' "$result"
}

repair_saved_profiles() {
    local value="$1" candidate result='[]' count index entry profile repaired
    if ! candidate="$(jq -ce 'if type == "array" then . else empty end' <<<"$value" 2>/dev/null)"; then
        printf '%s' "$value"
        return 0
    fi

    count="$(jq -r 'length' <<<"$candidate")"
    for ((index = 0; index < count; ++index)); do
        entry="$(jq -c --argjson index "$index" '.[$index]' <<<"$candidate")"
        if jq -e 'type == "object" and (.profile | type) == "object"' >/dev/null 2>&1 <<<"$entry"; then
            profile="$(jq -c '.profile' <<<"$entry")"
            repaired="$(repair_profile_optional_resources "$profile")"
            if jq -e 'type == "object"' >/dev/null 2>&1 <<<"$repaired"; then
                entry="$(jq -c --argjson profile "$repaired" '.profile = $profile' <<<"$entry")"
            fi
        fi
        result="$(jq -c --argjson entry "$entry" '. + [$entry]' <<<"$result")"
    done
    printf '%s' "$result"
}

if [[ "$profile_mode" == true ]]; then
    monitor_profiles="$(repair_override_profiles "$2")"
    last_edited_profile="$(repair_profile_optional_resources "$3")"
    if [[ $# -eq 4 ]]; then
        saved_profiles="$(repair_saved_profiles "$4")"
        bash "$STATE_BACKEND" save-lockscreen-editor-profiles \
            "$monitor_profiles" "$last_edited_profile" "$saved_profiles"
    else
        bash "$STATE_BACKEND" save-lockscreen-editor-profiles \
            "$monitor_profiles" "$last_edited_profile"
    fi
    printf '%s\n' '{"ok":true}'
    exit 0
fi

custom_images_input="$(filter_stale_custom_images "$custom_images_input")"
backend_layout="$(jq -ce 'with_entries(.value |= del(.rotation))' <<<"$layout_input")"
backend_custom_images="$(jq -ce '[.[] | del(.spawn_timing)]' <<<"$custom_images_input")"
backend_visualizer="$(jq -ce 'del(.rotation)' <<<"$visualizer_input")"
timezone_clocks="$(normalize_timezone_clocks "$timezone_clocks_input")"
timezone_clocks="$(filter_stale_timezone_clocks "$timezone_clocks")"
custom_texts="$(normalize_custom_texts "$custom_texts_input")"

backend_args=("${@:1:19}")
backend_args[0]="$backend_layout"
backend_args[12]="$backend_custom_images"
backend_args[13]="$backend_visualizer"

# Older/upgraded state can retain wallpaper mode after its wallpaper path has
# been cleared or a previously-valid local file has disappeared. Repair only
# that stale optional state; malformed paths still go to the strict backend.
if [[ "${backend_args[2]}" == "wallpaper" ]]; then
    wallpaper_path="${backend_args[4]}"
    if [[ -z "$wallpaper_path" ]]; then
        backend_args[2]="black"
        backend_args[4]=""
    elif [[ "$wallpaper_path" == /* && "$wallpaper_path" != *://* \
        && "$wallpaper_path" != *$'\n'* && "$wallpaper_path" != *$'\r'* \
        && ( ! -f "$wallpaper_path" || ! -r "$wallpaper_path" ) ]]; then
        backend_args[2]="black"
        backend_args[4]=""
    fi
fi

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
    | .lockscreen_password_feedback_mode = $mask_mode
    | del(.lockscreen_password_mask_mode)
    | .lockscreen_password_mask_character = $mask_character
    | .lockscreen_clock_format = $clock_format
    | .lockscreen_timezone_clocks = $timezone_clocks
    | .lockscreen_custom_texts = $custom_texts
    ' "$STATE_FILE" >"$tmp_file"

chmod --reference="$STATE_FILE" "$tmp_file" 2>/dev/null || true
mv -f -- "$tmp_file" "$STATE_FILE"
tmp_file=""
printf '%s\n' '{"ok":true}'
