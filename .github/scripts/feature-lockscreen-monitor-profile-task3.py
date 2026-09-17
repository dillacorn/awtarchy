#!/usr/bin/env python3
from pathlib import Path

state_path = Path("config/hypr/scripts/quickshell_application_state.sh")
save_path = Path("config/hypr/scripts/quickshell_lockscreen_editor_save.sh")
bar_path = Path("config/quickshell/awtarchy/BarState.qml")

state = state_path.read_text(encoding="utf-8")
if "save_lockscreen_editor_profiles()" not in state:
    anchor = "\nvalidate_lockscreen_layout() {\n"
    if anchor not in state:
        raise SystemExit("application-state profile insertion anchor missing")
    block = r'''
normalize_lockscreen_profile_json() {
    local value="$1" normalized wallpaper count index path resolved zone

    if ! normalized="$(jq -ce -n --argjson candidate "$value" '
        def profile_keys: [
            "lockscreen_animation",
            "lockscreen_background",
            "lockscreen_background_color",
            "lockscreen_background_opacity",
            "lockscreen_background_opacity_previous",
            "lockscreen_blur_style",
            "lockscreen_clock_format",
            "lockscreen_custom_images",
            "lockscreen_custom_texts",
            "lockscreen_entry_transition",
            "lockscreen_entry_transition_duration",
            "lockscreen_layout",
            "lockscreen_overlay_mode",
            "lockscreen_overlay_strength",
            "lockscreen_password_mask_character",
            "lockscreen_password_mask_mode",
            "lockscreen_show_date",
            "lockscreen_show_logo",
            "lockscreen_show_time",
            "lockscreen_show_username",
            "lockscreen_show_weather",
            "lockscreen_timezone_clocks",
            "lockscreen_visualizer",
            "lockscreen_wallpaper_fit",
            "lockscreen_wallpaper_focal_x",
            "lockscreen_wallpaper_focal_y",
            "lockscreen_wallpaper_path",
            "lockscreen_wallpaper_blur",
            "lockscreen_weather_units"
        ];
        def layout_keys: ["logo", "time", "date", "username", "weather", "password"];
        def valid_color($value):
            ($value | type) == "string"
            and ($value == "auto" or ($value | test("^#[0-9A-Fa-f]{6}$")));
        def valid_transform($value; $password):
            ($value | type) == "object"
            and (($value | keys - ["color", "opacity", "rotation", "scale", "stretch_x", "stretch_y", "x", "y"] | length) == 0)
            and ($value.x | type) == "number"
            and ($value.y | type) == "number"
            and ($value.scale | type) == "number"
            and ($value.stretch_x | type) == "number"
            and ($value.stretch_y | type) == "number"
            and ($value.opacity | type) == "number"
            and ($value.rotation | type) == "number"
            and valid_color($value.color)
            and ($value.x >= (if $password then 0.15 else 0.05 end))
            and ($value.x <= (if $password then 0.85 else 0.95 end))
            and ($value.y >= (if $password then 0.20 else 0.08 end))
            and ($value.y <= (if $password then 0.86 else 0.92 end))
            and ($value.scale >= 0.5 and $value.scale <= 100)
            and ($value.stretch_x >= 0.25 and $value.stretch_x <= 4)
            and ($value.stretch_y >= 0.25 and $value.stretch_y <= 4)
            and ($value.opacity >= (if $password then 20 else 0 end) and $value.opacity <= 100)
            and ($value.rotation >= -180 and $value.rotation <= 180);
        def valid_optional_path($value):
            ($value | type) == "string"
            and ($value == "" or (
                ($value | startswith("/"))
                and ($value | contains("://") | not)
                and ($value | test("[\\u0000-\\u001f\\u007f-\\u009f]") | not)
            ));
        def valid_custom_images($items):
            ($items | type) == "array"
            and ($items | length) <= 12
            and ([ $items[].id ] | length) == ([ $items[].id ] | unique | length)
            and all($items[];
                (. | type) == "object"
                and ((. | keys - ["id", "opacity", "path", "rotation", "scale", "spawn_animation", "spawn_timing", "stretch_x", "stretch_y", "visible", "x", "y"] | length) == 0)
                and (.id | type) == "string" and (.id | test("^image-[A-Za-z0-9_-]{1,64}$"))
                and valid_optional_path(.path) and (.path != "")
                and (.x | type) == "number" and .x >= 0.05 and .x <= 0.95
                and (.y | type) == "number" and .y >= 0.08 and .y <= 0.92
                and (.scale | type) == "number" and .scale >= 0.5 and .scale <= 100
                and (.stretch_x | type) == "number" and .stretch_x >= 0.25 and .stretch_x <= 4
                and (.stretch_y | type) == "number" and .stretch_y >= 0.25 and .stretch_y <= 4
                and (.opacity | type) == "number" and .opacity >= 0 and .opacity <= 100
                and (.rotation | type) == "number" and .rotation >= -180 and .rotation <= 180
                and (.spawn_animation | type) == "string"
                and (["none", "pixel-warp", "closest-edge", "top", "bottom", "left", "right"] | index(.spawn_animation) != null)
                and (.spawn_timing | type) == "string"
                and (["during-logo", "after-logo"] | index(.spawn_timing) != null)
                and (.visible | type) == "boolean");
        def valid_timezone_clocks($items):
            ($items | type) == "array"
            and ($items | length) <= 12
            and ([ $items[].id ] | length) == ([ $items[].id ] | unique | length)
            and all($items[];
                (. | type) == "object"
                and ((. | keys - ["color", "format", "id", "opacity", "rotation", "scale", "show_label", "stretch_x", "stretch_y", "timezone", "visible", "x", "y"] | length) == 0)
                and (.id | type) == "string" and (.id | test("^timezone-[A-Za-z0-9_-]{1,64}$"))
                and (.timezone | type) == "string" and (.timezone | length) > 0
                and (.timezone | startswith("/") | not) and (.timezone | contains("..") | not)
                and (.timezone | test("[\\u0000-\\u001f\\u007f-\\u009f]") | not)
                and (.format == "24h" or .format == "12h")
                and (.show_label | type) == "boolean"
                and (.x | type) == "number" and .x >= 0.05 and .x <= 0.95
                and (.y | type) == "number" and .y >= 0.08 and .y <= 0.92
                and (.scale | type) == "number" and .scale >= 0.5 and .scale <= 100
                and (.stretch_x | type) == "number" and .stretch_x >= 0.25 and .stretch_x <= 4
                and (.stretch_y | type) == "number" and .stretch_y >= 0.25 and .stretch_y <= 4
                and (.opacity | type) == "number" and .opacity >= 0 and .opacity <= 100
                and (.rotation | type) == "number" and .rotation >= -180 and .rotation <= 180
                and valid_color(.color)
                and (.visible | type) == "boolean");
        def valid_custom_texts($items):
            ($items | type) == "array"
            and ($items | length) <= 12
            and ([ $items[].id ] | length) == ([ $items[].id ] | unique | length)
            and all($items[];
                (. | type) == "object"
                and ((. | keys - ["alignment", "color", "id", "opacity", "randomize", "rotation", "scale", "stretch_x", "stretch_y", "text", "variants", "visible", "x", "y"] | length) == 0)
                and (.id | type) == "string" and (.id | test("^text-[A-Za-z0-9_-]{1,64}$"))
                and (.text | type) == "string" and (.text | length) <= 4096
                and (.variants | type) == "array" and (.variants | length) <= 32
                and all(.variants[]; type == "string" and length <= 4096)
                and (.randomize | type) == "boolean"
                and (["left", "center", "right"] | index(.alignment) != null)
                and (.x | type) == "number" and .x >= 0.05 and .x <= 0.95
                and (.y | type) == "number" and .y >= 0.08 and .y <= 0.92
                and (.scale | type) == "number" and .scale >= 0.5 and .scale <= 100
                and (.stretch_x | type) == "number" and .stretch_x >= 0.25 and .stretch_x <= 4
                and (.stretch_y | type) == "number" and .stretch_y >= 0.25 and .stretch_y <= 4
                and (.opacity | type) == "number" and .opacity >= 0 and .opacity <= 100
                and (.rotation | type) == "number" and .rotation >= -180 and .rotation <= 180
                and valid_color(.color)
                and (.visible | type) == "boolean");
        def valid_visualizer($value):
            ($value | type) == "object"
            and (($value | keys - ["bands", "bend", "color", "enabled", "gap", "height", "opacity", "performance", "rotation", "scale", "sensitivity", "shape", "stretch_x", "stretch_y", "x", "y"] | length) == 0)
            and ($value.enabled | type) == "boolean"
            and ($value.x | type) == "number" and $value.x >= 0.05 and $value.x <= 0.95
            and ($value.y | type) == "number" and $value.y >= 0.08 and $value.y <= 0.92
            and ($value.scale | type) == "number" and $value.scale >= 0.5 and $value.scale <= 100
            and ($value.stretch_x | type) == "number" and $value.stretch_x >= 0.25 and $value.stretch_x <= 4
            and ($value.stretch_y | type) == "number" and $value.stretch_y >= 0.25 and $value.stretch_y <= 4
            and ($value.opacity | type) == "number" and $value.opacity >= 0 and $value.opacity <= 100
            and ($value.rotation | type) == "number" and $value.rotation >= -180 and $value.rotation <= 180
            and valid_color($value.color)
            and ($value.bands | type) == "number" and ($value.bands | floor) == $value.bands and $value.bands >= 4 and $value.bands <= 64
            and ($value.gap | type) == "number" and ($value.gap | floor) == $value.gap and $value.gap >= 0 and $value.gap <= 24
            and ($value.height | type) == "number" and ($value.height | floor) == $value.height and $value.height >= 25 and $value.height <= 300
            and ($value.sensitivity | type) == "number" and ($value.sensitivity | floor) == $value.sensitivity and $value.sensitivity >= 25 and $value.sensitivity <= 300
            and (["straight", "arc", "circle"] | index($value.shape) != null)
            and ($value.bend | type) == "number" and ($value.bend | floor) == $value.bend and $value.bend >= -2000 and $value.bend <= 2000
            and (["balanced", "responsive", "high"] | index($value.performance) != null);
        if
            ($candidate | type) == "object"
            and (($candidate | keys | sort) == (profile_keys | sort))
            and ($candidate.lockscreen_layout | type) == "object"
            and (($candidate.lockscreen_layout | keys | sort) == (layout_keys | sort))
            and all(layout_keys[]; . as $key | valid_transform($candidate.lockscreen_layout[$key]; $key == "password"))
            and ($candidate.lockscreen_show_logo | type) == "boolean"
            and ($candidate.lockscreen_show_time | type) == "boolean"
            and ($candidate.lockscreen_show_date | type) == "boolean"
            and ($candidate.lockscreen_show_username | type) == "boolean"
            and ($candidate.lockscreen_show_weather | type) == "boolean"
            and valid_custom_images($candidate.lockscreen_custom_images)
            and valid_timezone_clocks($candidate.lockscreen_timezone_clocks)
            and valid_custom_texts($candidate.lockscreen_custom_texts)
            and valid_visualizer($candidate.lockscreen_visualizer)
            and (["black", "wallpaper", "color"] | index($candidate.lockscreen_background) != null)
            and ($candidate.lockscreen_background_color | type) == "string"
            and ($candidate.lockscreen_background_color | test("^#[0-9A-Fa-f]{6}$"))
            and valid_optional_path($candidate.lockscreen_wallpaper_path)
            and ($candidate.lockscreen_background != "wallpaper" or $candidate.lockscreen_wallpaper_path != "")
            and (["cover", "contain"] | index($candidate.lockscreen_wallpaper_fit) != null)
            and ($candidate.lockscreen_wallpaper_focal_x | type) == "number" and $candidate.lockscreen_wallpaper_focal_x >= 0 and $candidate.lockscreen_wallpaper_focal_x <= 1
            and ($candidate.lockscreen_wallpaper_focal_y | type) == "number" and $candidate.lockscreen_wallpaper_focal_y >= 0 and $candidate.lockscreen_wallpaper_focal_y <= 1
            and ($candidate.lockscreen_background_opacity | type) == "number" and ($candidate.lockscreen_background_opacity | floor) == $candidate.lockscreen_background_opacity and $candidate.lockscreen_background_opacity >= 0 and $candidate.lockscreen_background_opacity <= 100
            and ($candidate.lockscreen_background_opacity_previous | type) == "number" and ($candidate.lockscreen_background_opacity_previous | floor) == $candidate.lockscreen_background_opacity_previous and $candidate.lockscreen_background_opacity_previous >= 0 and $candidate.lockscreen_background_opacity_previous <= 100
            and (["none", "dark", "light"] | index($candidate.lockscreen_overlay_mode) != null)
            and ($candidate.lockscreen_overlay_strength | type) == "number" and ($candidate.lockscreen_overlay_strength | floor) == $candidate.lockscreen_overlay_strength and $candidate.lockscreen_overlay_strength >= 0 and $candidate.lockscreen_overlay_strength <= 100
            and ($candidate.lockscreen_wallpaper_blur | type) == "number" and ($candidate.lockscreen_wallpaper_blur | floor) == $candidate.lockscreen_wallpaper_blur and $candidate.lockscreen_wallpaper_blur >= 0 and $candidate.lockscreen_wallpaper_blur <= 200
            and (["smooth", "pixelated"] | index($candidate.lockscreen_blur_style) != null)
            and (["auto", "fahrenheit", "celsius"] | index($candidate.lockscreen_weather_units) != null)
            and (["random", "swarm", "edges", "center", "split", "off"] | index($candidate.lockscreen_animation) != null)
            and (["fade", "pixel", "edges", "wipe"] | index($candidate.lockscreen_entry_transition) != null)
            and ($candidate.lockscreen_entry_transition_duration | type) == "number"
            and ($candidate.lockscreen_entry_transition_duration | floor) == $candidate.lockscreen_entry_transition_duration
            and $candidate.lockscreen_entry_transition_duration >= 800 and $candidate.lockscreen_entry_transition_duration <= 6000
            and (["squares", "dots", "custom"] | index($candidate.lockscreen_password_mask_mode) != null)
            and ($candidate.lockscreen_password_mask_character | type) == "string"
            and (($candidate.lockscreen_password_mask_character | explode | length) == 1)
            and (($candidate.lockscreen_password_mask_character | explode | .[0]) > 32)
            and ((($candidate.lockscreen_password_mask_character | explode | .[0]) < 127) or (($candidate.lockscreen_password_mask_character | explode | .[0]) > 159))
            and (["24h", "12h"] | index($candidate.lockscreen_clock_format) != null)
        then $candidate else error("invalid lockscreen profile") end
    ' 2>/dev/null)"; then
        printf 'invalid lockscreen profile\n' >&2
        return 2
    fi

    wallpaper="$(jq -r '.lockscreen_wallpaper_path' <<<"$normalized")"
    if [[ -n "$wallpaper" ]]; then
        [[ -f "$wallpaper" && -r "$wallpaper" ]] || {
            printf 'lockscreen wallpaper must be a readable absolute local file\n' >&2
            return 2
        }
        resolved="$(readlink -f -- "$wallpaper" 2>/dev/null || true)"
        [[ -n "$resolved" && -f "$resolved" && -r "$resolved" ]] || {
            printf 'lockscreen wallpaper could not be resolved\n' >&2
            return 2
        }
        normalized="$(jq -c --arg path "$resolved" '.lockscreen_wallpaper_path = $path' <<<"$normalized")"
    fi

    count="$(jq -r '.lockscreen_custom_images | length' <<<"$normalized")"
    for ((index = 0; index < count; ++index)); do
        path="$(jq -r --argjson index "$index" '.lockscreen_custom_images[$index].path' <<<"$normalized")"
        [[ -f "$path" && -r "$path" ]] || {
            printf 'lockscreen custom media must be a readable absolute local file\n' >&2
            return 2
        }
        resolved="$(readlink -f -- "$path" 2>/dev/null || true)"
        [[ -n "$resolved" && -f "$resolved" && -r "$resolved" ]] || {
            printf 'lockscreen custom media could not be resolved\n' >&2
            return 2
        }
        normalized="$(jq -c --argjson index "$index" --arg path "$resolved" '.lockscreen_custom_images[$index].path = $path' <<<"$normalized")"
    done

    count="$(jq -r '.lockscreen_timezone_clocks | length' <<<"$normalized")"
    for ((index = 0; index < count; ++index)); do
        zone="$(jq -r --argjson index "$index" '.lockscreen_timezone_clocks[$index].timezone' <<<"$normalized")"
        [[ -f "/usr/share/zoneinfo/$zone" ]] || {
            printf 'lockscreen timezone is unavailable: %s\n' "$zone" >&2
            return 2
        }
    done

    printf '%s' "$normalized"
}

normalize_lockscreen_monitor_overrides_json() {
    local value="$1" candidate result key profile normalized
    if ! candidate="$(jq -ce 'if type == "object" then . else error("invalid overrides") end' <<<"$value" 2>/dev/null)"; then
        printf 'invalid lockscreen monitor overrides\n' >&2
        return 2
    fi

    result='{}'
    while IFS= read -r key; do
        if ! jq -e -n --arg key "$key" '
            ($key | explode | length) >= 1
            and ($key | explode | length) <= 128
            and ($key | test("[\\u0000-\\u001f\\u007f-\\u009f]") | not)
        ' >/dev/null 2>&1; then
            printf 'invalid lockscreen monitor name\n' >&2
            return 2
        fi
        profile="$(jq -c --arg key "$key" '.[$key]' <<<"$candidate")"
        normalized="$(normalize_lockscreen_profile_json "$profile")" || return $?
        result="$(jq -c --arg key "$key" --argjson profile "$normalized" '. + {($key): $profile}' <<<"$result")"
    done < <(jq -r 'keys[]' <<<"$candidate")

    printf '%s' "$result"
}

save_lockscreen_editor_profiles() {
    local shared overrides
    shared="$(normalize_lockscreen_profile_json "$1")" || return $?
    overrides="$(normalize_lockscreen_monitor_overrides_json "$2")" || return $?

    new_tmp
    jq --argjson shared "$shared" --argjson overrides "$overrides" '
        . + $shared
        | .lockscreen_monitor_overrides = $overrides
    ' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}
'''
    state = state.replace(anchor, "\n" + block + anchor, 1)

if "save-lockscreen-editor-profiles)" not in state:
    dispatch_anchor = '''    save-lockscreen-editor)\n        case "$#" in\n            6|12|13|14|16|17|18|19|20) ;;\n            *) exit 2 ;;\n        esac\n        save_lockscreen_editor "${@:2}"\n        ;;\n'''
    if dispatch_anchor not in state:
        raise SystemExit("application-state save dispatch anchor missing")
    state = state.replace(
        dispatch_anchor,
        dispatch_anchor
        + '''    save-lockscreen-editor-profiles)\n        [[ $# -eq 3 ]] || exit 2\n        save_lockscreen_editor_profiles "$2" "$3"\n        ;;\n''',
        1,
    )
state_path.write_text(state, encoding="utf-8")

save = save_path.read_text(encoding="utf-8")
if 'profile_mode=false' not in save:
    old_check = '''if [[ $# -ne 23 && $# -ne 25 ]]; then\n    printf 'usage: %s <19 existing editor fields> <logo-animation> <mask-mode> <mask-character> <clock-format> [timezone-clocks-json custom-texts-json]\\n' "${0##*/}" >&2\n    false\nfi\n\n'''
    new_check = '''profile_mode=false\nif [[ "${1:-}" == "--profiles" ]]; then\n    [[ $# -eq 3 ]] || {\n        printf 'usage: %s --profiles <shared-profile-json> <monitor-overrides-json>\\n' "${0##*/}" >&2\n        false\n    }\n    profile_mode=true\nelif [[ $# -ne 23 && $# -ne 25 ]]; then\n    printf 'usage: %s <19 existing editor fields> <logo-animation> <mask-mode> <mask-character> <clock-format> [timezone-clocks-json custom-texts-json]\\n' "${0##*/}" >&2\n    false\nfi\n\n'''
    if old_check not in save:
        raise SystemExit("editor-save usage anchor missing")
    save = save.replace(old_check, new_check, 1)

    legacy_start = save.index('layout_input="${1}"')
    helper_start = save.index('normalize_timezone_clocks() {')
    legacy_block = save[legacy_start:helper_start]
    save = save[:legacy_start] + 'if [[ "$profile_mode" == false ]]; then\n' + legacy_block + 'fi\n\n' + save[helper_start:]

if 'repair_profile_optional_resources()' not in save:
    anchor = 'custom_images_input="$(filter_stale_custom_images "$custom_images_input")"\n'
    if anchor not in save:
        raise SystemExit("editor-save profile dispatch anchor missing")
    block = r'''repair_profile_optional_resources() {
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

if [[ "$profile_mode" == true ]]; then
    shared_profile="$(repair_profile_optional_resources "$2")"
    monitor_overrides="$(repair_override_profiles "$3")"
    bash "$STATE_BACKEND" save-lockscreen-editor-profiles "$shared_profile" "$monitor_overrides"
    printf '%s\n' '{"ok":true}'
    exit 0
fi

'''
    save = save.replace(anchor, block + anchor, 1)
save_path.write_text(save, encoding="utf-8")

bar = bar_path.read_text(encoding="utf-8")
resolver_import = 'import "LockscreenPresentationState.js" as LockscreenPresentationState\n'
if resolver_import not in bar:
    import_anchor = 'import Quickshell.Io\n'
    if import_anchor not in bar:
        raise SystemExit("BarState import anchor missing")
    bar = bar.replace(import_anchor, import_anchor + resolver_import, 1)
if 'lockscreen_monitor_overrides: {},' not in bar:
    empty_anchor = '            lockscreen_background_opacity: 100,\n'
    if empty_anchor not in bar:
        raise SystemExit("BarState emptyData anchor missing")
    bar = bar.replace(empty_anchor, empty_anchor + '            lockscreen_monitor_overrides: {},\n', 1)
if 'function lockscreenSharedProfile()' not in bar:
    facade_anchor = '    function identityLabelValid(value) {\n'
    if facade_anchor not in bar:
        raise SystemExit("BarState profile facade anchor missing")
    facade = '''    function lockscreenSharedProfile() {\n        const dependency = revision;\n        return LockscreenPresentationState.sharedProfile(data());\n    }\n\n    function lockscreenMonitorOverrides() {\n        const dependency = revision;\n        return LockscreenPresentationState.monitorOverrides(data());\n    }\n\n    function lockscreenProfileForMonitor(name) {\n        return LockscreenPresentationState.profileForMonitor(\n            lockscreenSharedProfile(), lockscreenMonitorOverrides(), String(name || ""));\n    }\n\n'''
    bar = bar.replace(facade_anchor, facade + facade_anchor, 1)
bar_path.write_text(bar, encoding="utf-8")
