#!/usr/bin/env python3
from pathlib import Path
import re


def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


def regex_once(text, pattern, repl, label):
    new, count = re.subn(pattern, repl, text, count=1, flags=re.S)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one regex match, found {count}")
    return new

app_path = Path("config/hypr/scripts/quickshell_application_state.sh")
app = app_path.read_text()
app = replace_once(
    app,
    "LOCKSCREEN_LAYOUT_DEFAULT_JSON='{\"logo\":{\"x\":0.5,\"y\":0.34,\"scale\":1,\"color\":\"auto\"},\"time\":{\"x\":0.5,\"y\":0.51,\"scale\":1,\"color\":\"auto\"},\"date\":{\"x\":0.5,\"y\":0.555,\"scale\":1,\"color\":\"auto\"},\"username\":{\"x\":0.5,\"y\":0.595,\"scale\":1,\"color\":\"auto\"},\"weather\":{\"x\":0.5,\"y\":0.635,\"scale\":1,\"color\":\"auto\"},\"password\":{\"x\":0.5,\"y\":0.7,\"scale\":1,\"color\":\"auto\"}}'",
    "LOCKSCREEN_LAYOUT_DEFAULT_JSON='{\"logo\":{\"x\":0.5,\"y\":0.34,\"scale\":1,\"stretch_x\":1,\"stretch_y\":1,\"opacity\":100,\"color\":\"auto\"},\"time\":{\"x\":0.5,\"y\":0.51,\"scale\":1,\"stretch_x\":1,\"stretch_y\":1,\"opacity\":100,\"color\":\"auto\"},\"date\":{\"x\":0.5,\"y\":0.555,\"scale\":1,\"stretch_x\":1,\"stretch_y\":1,\"opacity\":100,\"color\":\"auto\"},\"username\":{\"x\":0.5,\"y\":0.595,\"scale\":1,\"stretch_x\":1,\"stretch_y\":1,\"opacity\":100,\"color\":\"auto\"},\"weather\":{\"x\":0.5,\"y\":0.635,\"scale\":1,\"stretch_x\":1,\"stretch_y\":1,\"opacity\":100,\"color\":\"auto\"},\"password\":{\"x\":0.5,\"y\":0.7,\"scale\":1,\"stretch_x\":1,\"stretch_y\":1,\"opacity\":100,\"color\":\"auto\"}}'\nLOCKSCREEN_CUSTOM_IMAGE_MAX=12",
    "layout defaults",
)

new_layout = r'''normalize_lockscreen_layout_json() {
    local value="$1"
    jq -ce -n \
        --argjson candidate "$value" \
        --argjson keys "$LOCKSCREEN_LAYOUT_KEYS_JSON" '
        def allowed_keys: ["color", "opacity", "scale", "stretch_x", "stretch_y", "x", "y"];
        if (
            ($candidate | type) == "object"
            and (($candidate | keys | sort) == ($keys | sort))
            and all($keys[];
                . as $key
                | ($candidate[$key] | type) == "object"
                and (($candidate[$key] | keys - allowed_keys | length) == 0)
                and ($candidate[$key].x | type) == "number"
                and ($candidate[$key].y | type) == "number"
                and (($candidate[$key].scale // 1) | type) == "number"
                and (($candidate[$key].stretch_x // 1) | type) == "number"
                and (($candidate[$key].stretch_y // 1) | type) == "number"
                and (($candidate[$key].opacity // 100) | type) == "number"
                and (($candidate[$key] | has("color") | not)
                    or (($candidate[$key].color | type) == "string"
                        and ($candidate[$key].color == "auto"
                            or ($candidate[$key].color | test("^#[0-9A-Fa-f]{6}$")))))
                and (($candidate[$key].scale // 1) >= 0.50)
                and (($candidate[$key].scale // 1) <= 2.00)
                and (($candidate[$key].stretch_x // 1) >= 0.25)
                and (($candidate[$key].stretch_x // 1) <= 4.00)
                and (($candidate[$key].stretch_y // 1) >= 0.25)
                and (($candidate[$key].stretch_y // 1) <= 4.00)
                and (($candidate[$key].opacity // 100) >= (if $key == "password" then 20 else 0 end))
                and (($candidate[$key].opacity // 100) <= 100)
                and (if $key == "password" then
                    $candidate[$key].x >= 0.15 and $candidate[$key].x <= 0.85
                    and $candidate[$key].y >= 0.20 and $candidate[$key].y <= 0.86
                else
                    $candidate[$key].x >= 0.05 and $candidate[$key].x <= 0.95
                    and $candidate[$key].y >= 0.08 and $candidate[$key].y <= 0.92
                end)
            )
        ) then
            reduce $keys[] as $key ({};
                .[$key] = {
                    x: $candidate[$key].x,
                    y: $candidate[$key].y,
                    scale: ($candidate[$key].scale // 1),
                    stretch_x: ($candidate[$key].stretch_x // 1),
                    stretch_y: ($candidate[$key].stretch_y // 1),
                    opacity: ($candidate[$key].opacity // 100),
                    color: ($candidate[$key].color // "auto")
                })
        else
            error("invalid lockscreen layout")
        end
    '
}

normalize_lockscreen_custom_images_json() {
    local value="$1" normalized count index path resolved
    if ! normalized="$(jq -ce -n \
        --argjson candidate "$value" \
        --argjson maximum "$LOCKSCREEN_CUSTOM_IMAGE_MAX" '
        def keys_ok: ["id", "opacity", "path", "scale", "stretch_x", "stretch_y", "visible", "x", "y"];
        if (($candidate | type) == "array"
            and ($candidate | length) <= $maximum
            and ([ $candidate[].id ] | length) == ([ $candidate[].id ] | unique | length)
            and all($candidate[];
                (. | type) == "object"
                and ((. | keys | sort) == keys_ok)
                and (.id | type) == "string"
                and (.id | test("^image-[A-Za-z0-9_-]{1,64}$"))
                and (.path | type) == "string"
                and (.path | startswith("/"))
                and (.path | contains("://") | not)
                and (.path | test("[\\u0000-\\u001f\\u007f-\\u009f]") | not)
                and (.x | type) == "number" and .x >= 0.05 and .x <= 0.95
                and (.y | type) == "number" and .y >= 0.08 and .y <= 0.92
                and (.scale | type) == "number" and .scale >= 0.50 and .scale <= 2.00
                and (.stretch_x | type) == "number" and .stretch_x >= 0.25 and .stretch_x <= 4.00
                and (.stretch_y | type) == "number" and .stretch_y >= 0.25 and .stretch_y <= 4.00
                and (.opacity | type) == "number" and .opacity >= 0 and .opacity <= 100
                and (.visible | type) == "boolean"))
        then $candidate else error("invalid custom images") end
    ' 2>/dev/null)"; then
        printf 'invalid lockscreen custom images\n' >&2
        exit 2
    fi

    count="$(jq -r 'length' <<<"$normalized")"
    for ((index = 0; index < count; ++index)); do
        path="$(jq -r --argjson index "$index" '.[$index].path' <<<"$normalized")"
        [[ -f "$path" && -r "$path" ]] || {
            printf 'lockscreen custom image must be a readable absolute local file\n' >&2
            exit 2
        }
        resolved="$(readlink -f -- "$path" 2>/dev/null || true)"
        [[ -n "$resolved" && "$resolved" == /* && -f "$resolved" && -r "$resolved" ]] || {
            printf 'lockscreen custom image could not be resolved\n' >&2
            exit 2
        }
        normalized="$(jq -c --argjson index "$index" --arg path "$resolved" '.[$index].path = $path' <<<"$normalized")"
    done
    printf '%s' "$normalized"
}
'''
app = regex_once(
    app,
    r'normalize_lockscreen_layout_json\(\) \{.*?\n\}\n\n(?=validate_lockscreen_layout\(\))',
    new_layout + "\n",
    "layout normalizer",
)

new_save = r'''save_lockscreen_editor() {
    local normalized visibility="$2" background="$3" background_color="${4,,}" wallpaper="$5"
    local wallpaper_fit="${6:-cover}"
    local focal_x="${7:-0.5}"
    local focal_y="${8:-0.5}"
    local overlay_mode="${9:-none}"
    local overlay_strength="${10:-0}"
    local wallpaper_blur="${11:-0}"
    local weather_units="${12:-auto}"
    local custom_images_input="${13:-[]}"
    local custom_images
    if ! normalized="$(normalize_lockscreen_layout_json "$1" 2>/dev/null)"; then
        printf 'invalid lockscreen layout\n' >&2
        exit 2
    fi
    custom_images="$(normalize_lockscreen_custom_images_json "$custom_images_input")"
    validate_lockscreen_editor_visibility "$visibility"
    validate_lockscreen_background "$background"
    validate_lockscreen_hex_color "$background_color" 'lockscreen background color'
    validate_lockscreen_wallpaper_fit "$wallpaper_fit"
    validate_lockscreen_overlay_mode "$overlay_mode"
    validate_lockscreen_weather_units "$weather_units"
    focal_x="$(normalize_unit_interval "$focal_x" 'lockscreen wallpaper focal x')"
    focal_y="$(normalize_unit_interval "$focal_y" 'lockscreen wallpaper focal y')"
    overlay_strength="$(normalize_percent_integer "$overlay_strength" 'lockscreen overlay strength')"
    wallpaper_blur="$(normalize_percent_integer "$wallpaper_blur" 'lockscreen wallpaper blur')"
    wallpaper="$(normalize_lockscreen_wallpaper_path "$wallpaper")"
    if [[ "$background" == 'wallpaper' && -z "$wallpaper" ]]; then
        printf 'wallpaper background requires a selected local image\n' >&2
        exit 2
    fi
    new_tmp
    jq \
        --argjson layout "$normalized" \
        --argjson visibility "$visibility" \
        --arg background "$background" \
        --arg background_color "$background_color" \
        --arg wallpaper "$wallpaper" \
        --arg wallpaper_fit "$wallpaper_fit" \
        --argjson focal_x "$focal_x" \
        --argjson focal_y "$focal_y" \
        --arg overlay_mode "$overlay_mode" \
        --argjson overlay_strength "$overlay_strength" \
        --argjson wallpaper_blur "$wallpaper_blur" \
        --arg weather_units "$weather_units" \
        --argjson custom_images "$custom_images" '
        .lockscreen_layout = $layout
        | .lockscreen_custom_images = $custom_images
        | .lockscreen_show_logo = $visibility.logo
        | .lockscreen_show_time = $visibility.time
        | .lockscreen_show_date = $visibility.date
        | .lockscreen_show_username = $visibility.username
        | .lockscreen_show_weather = $visibility.weather
        | .lockscreen_background = $background
        | .lockscreen_background_color = $background_color
        | .lockscreen_wallpaper_path = $wallpaper
        | .lockscreen_wallpaper_fit = $wallpaper_fit
        | .lockscreen_wallpaper_focal_x = $focal_x
        | .lockscreen_wallpaper_focal_y = $focal_y
        | .lockscreen_overlay_mode = $overlay_mode
        | .lockscreen_overlay_strength = $overlay_strength
        | .lockscreen_wallpaper_blur = $wallpaper_blur
        | .lockscreen_weather_units = $weather_units
    ' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}
'''
app = regex_once(
    app,
    r'save_lockscreen_editor\(\) \{.*?\n\}\n(?=reset_lockscreen_presentation\(\))',
    new_save,
    "editor save",
)
app = replace_once(
    app,
    '        | .lockscreen_layout = $layout\n',
    '        | .lockscreen_layout = $layout\n        | .lockscreen_custom_images = []\n',
    "reset custom images",
)
app = replace_once(app, '            6|12|13) ;;', '            6|12|13|14) ;;', "editor command arity")
app_path.write_text(app)

bar_path = Path("config/quickshell/awtarchy/BarState.qml")
bar = bar_path.read_text()
for name in ("logo", "time", "date", "username", "weather", "password"):
    bar = bar.replace(
        f'{name}: ({{ x:',
        f'{name}: ({{ x:',
        1,
    )
# Expand only the default lockscreen layout block.
default_pattern = r'''    readonly property var defaultLockscreenLayout: \(\{.*?\n    \}\)'''
default_repl = '''    readonly property var defaultLockscreenLayout: ({
        logo: ({ x: 0.50, y: 0.34, scale: 1.0, stretch_x: 1.0, stretch_y: 1.0, opacity: 100, color: "auto" }),
        time: ({ x: 0.50, y: 0.51, scale: 1.0, stretch_x: 1.0, stretch_y: 1.0, opacity: 100, color: "auto" }),
        date: ({ x: 0.50, y: 0.555, scale: 1.0, stretch_x: 1.0, stretch_y: 1.0, opacity: 100, color: "auto" }),
        username: ({ x: 0.50, y: 0.595, scale: 1.0, stretch_x: 1.0, stretch_y: 1.0, opacity: 100, color: "auto" }),
        weather: ({ x: 0.50, y: 0.635, scale: 1.0, stretch_x: 1.0, stretch_y: 1.0, opacity: 100, color: "auto" }),
        password: ({ x: 0.50, y: 0.70, scale: 1.0, stretch_x: 1.0, stretch_y: 1.0, opacity: 100, color: "auto" })
    })'''
bar = regex_once(bar, default_pattern, default_repl, "BarState defaults")
bar = replace_once(
    bar,
    '            lockscreen_layout: root.defaultLockscreenLayout,\n',
    '            lockscreen_layout: root.defaultLockscreenLayout,\n            lockscreen_custom_images: [],\n',
    "BarState empty custom images",
)

layout_reader = r'''    function lockscreenLayoutPoint(value, fallback, password) {
        const fallbackColor = String(fallback.color || "auto");
        const fallbackPoint = ({
            x: fallback.x, y: fallback.y, scale: fallback.scale,
            stretch_x: fallback.stretch_x, stretch_y: fallback.stretch_y,
            opacity: fallback.opacity, color: fallbackColor
        });
        if (!value || typeof value !== "object" || Array.isArray(value))
            return fallbackPoint;
        const x = Number(value.x);
        const y = Number(value.y);
        const scale = Number(value.scale === undefined ? 1 : value.scale);
        const stretchX = Number(value.stretch_x === undefined ? 1 : value.stretch_x);
        const stretchY = Number(value.stretch_y === undefined ? 1 : value.stretch_y);
        const opacity = Number(value.opacity === undefined ? 100 : value.opacity);
        const rawColor = String(value.color === undefined ? "auto" : value.color);
        const color = rawColor === "auto" || /^#[0-9a-fA-F]{6}$/.test(rawColor)
            ? rawColor.toLowerCase() : fallbackColor;
        const minX = password ? 0.15 : 0.05;
        const maxX = password ? 0.85 : 0.95;
        const minY = password ? 0.20 : 0.08;
        const maxY = password ? 0.86 : 0.92;
        const minOpacity = password ? 20 : 0;
        if (!Number.isFinite(x) || !Number.isFinite(y) || !Number.isFinite(scale)
                || !Number.isFinite(stretchX) || !Number.isFinite(stretchY)
                || !Number.isFinite(opacity)
                || x < minX || x > maxX || y < minY || y > maxY
                || scale < 0.50 || scale > 2.00
                || stretchX < 0.25 || stretchX > 4.00
                || stretchY < 0.25 || stretchY > 4.00
                || opacity < minOpacity || opacity > 100)
            return fallbackPoint;
        return ({ x: x, y: y, scale: scale, stretch_x: stretchX,
            stretch_y: stretchY, opacity: opacity, color: color });
    }
    function lockscreenLayout() {
        const defaults = root.defaultLockscreenLayout;
        const value = data().lockscreen_layout;
        if (!value || typeof value !== "object" || Array.isArray(value))
            return defaults;
        return ({
            logo: lockscreenLayoutPoint(value.logo, defaults.logo, false),
            time: lockscreenLayoutPoint(value.time, defaults.time, false),
            date: lockscreenLayoutPoint(value.date, defaults.date, false),
            username: lockscreenLayoutPoint(value.username, defaults.username, false),
            weather: lockscreenLayoutPoint(value.weather, defaults.weather, false),
            password: lockscreenLayoutPoint(value.password, defaults.password, true)
        });
    }

    function lockscreenCustomImages() {
        const value = data().lockscreen_custom_images;
        if (!Array.isArray(value) || value.length > 12)
            return [];
        const result = [];
        const ids = ({});
        for (const raw of value) {
            if (!raw || typeof raw !== "object" || Array.isArray(raw))
                return [];
            const id = String(raw.id || "");
            const path = String(raw.path || "");
            const x = Number(raw.x);
            const y = Number(raw.y);
            const scale = Number(raw.scale);
            const stretchX = Number(raw.stretch_x);
            const stretchY = Number(raw.stretch_y);
            const opacity = Number(raw.opacity);
            if (!/^image-[A-Za-z0-9_-]{1,64}$/.test(id) || ids[id]
                    || !path.startsWith("/") || path.indexOf("://") >= 0
                    || /[\\u0000-\\u001f\\u007f-\\u009f]/.test(path)
                    || !Number.isFinite(x) || x < 0.05 || x > 0.95
                    || !Number.isFinite(y) || y < 0.08 || y > 0.92
                    || !Number.isFinite(scale) || scale < 0.50 || scale > 2.00
                    || !Number.isFinite(stretchX) || stretchX < 0.25 || stretchX > 4.00
                    || !Number.isFinite(stretchY) || stretchY < 0.25 || stretchY > 4.00
                    || !Number.isFinite(opacity) || opacity < 0 || opacity > 100
                    || typeof raw.visible !== "boolean")
                return [];
            ids[id] = true;
            result.push(({ id: id, path: path, x: x, y: y, scale: scale,
                stretch_x: stretchX, stretch_y: stretchY,
                opacity: opacity, visible: raw.visible }));
        }
        return result;
    }
'''
bar = regex_once(
    bar,
    r'    function lockscreenLayoutPoint\(value, fallback, password\) \{.*?\n    \}\n    function lockscreenLayout\(\) \{.*?\n    \}\n',
    layout_reader,
    "BarState layout reader",
)
bar_path.write_text(bar)
print("Pass 2 persistence and BarState patch applied")
