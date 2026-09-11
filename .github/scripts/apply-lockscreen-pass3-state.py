#!/usr/bin/env python3
from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one anchor, found {count}")
    return text.replace(old, new, 1)


app_path = Path("config/hypr/scripts/quickshell_application_state.sh")
app = app_path.read_text()

app = replace_once(
    app,
    "LOCKSCREEN_CUSTOM_IMAGE_MAX=12\nCURSOR_VARIANTS_JSON=",
    """LOCKSCREEN_CUSTOM_IMAGE_MAX=12
LOCKSCREEN_VISUALIZER_SHAPES_JSON='[\"straight\",\"arc\",\"circle\"]'
LOCKSCREEN_VISUALIZER_DEFAULT_JSON='{\"enabled\":false,\"x\":0.5,\"y\":0.8,\"scale\":1,\"stretch_x\":1,\"stretch_y\":1,\"opacity\":100,\"color\":\"auto\",\"bands\":16,\"gap\":4,\"height\":100,\"sensitivity\":100,\"shape\":\"straight\",\"bend\":45}'
CURSOR_VARIANTS_JSON=""",
    "visualizer constants",
)

visualizer_functions = r'''normalize_lockscreen_visualizer_json() {
    local value="$1"
    jq -ce -n \
        --argjson candidate "$value" \
        --argjson defaults "$LOCKSCREEN_VISUALIZER_DEFAULT_JSON" \
        --argjson shapes "$LOCKSCREEN_VISUALIZER_SHAPES_JSON" '
        def allowed_keys: ["bands", "bend", "color", "enabled", "gap", "height", "opacity", "scale", "sensitivity", "shape", "stretch_x", "stretch_y", "x", "y"];
        if ($candidate | type) != "object"
            or (($candidate | keys - allowed_keys | length) != 0)
        then error("invalid lockscreen visualizer")
        else
            ($candidate.enabled // $defaults.enabled) as $enabled
            | ($candidate.x // $defaults.x) as $x
            | ($candidate.y // $defaults.y) as $y
            | ($candidate.scale // $defaults.scale) as $scale
            | ($candidate.stretch_x // $defaults.stretch_x) as $stretch_x
            | ($candidate.stretch_y // $defaults.stretch_y) as $stretch_y
            | ($candidate.opacity // $defaults.opacity) as $opacity
            | ($candidate.color // $defaults.color) as $color
            | ($candidate.bands // $defaults.bands) as $bands
            | ($candidate.gap // $defaults.gap) as $gap
            | ($candidate.height // $defaults.height) as $height
            | ($candidate.sensitivity // $defaults.sensitivity) as $sensitivity
            | ($candidate.shape // $defaults.shape) as $shape
            | ($candidate.bend // $defaults.bend) as $bend
            | if
                ($enabled | type) == "boolean"
                and ($x | type) == "number" and $x >= 0.05 and $x <= 0.95
                and ($y | type) == "number" and $y >= 0.08 and $y <= 0.92
                and ($scale | type) == "number" and $scale >= 0.5 and $scale <= 2
                and ($stretch_x | type) == "number" and $stretch_x >= 0.25 and $stretch_x <= 4
                and ($stretch_y | type) == "number" and $stretch_y >= 0.25 and $stretch_y <= 4
                and ($opacity | type) == "number" and $opacity >= 0 and $opacity <= 100
                and ($color | type) == "string"
                and ($color == "auto" or ($color | test("^#[0-9A-Fa-f]{6}$")))
                and ($bands | type) == "number" and ($bands | floor) == $bands and $bands >= 4 and $bands <= 64
                and ($gap | type) == "number" and ($gap | floor) == $gap and $gap >= 0 and $gap <= 24
                and ($height | type) == "number" and ($height | floor) == $height and $height >= 25 and $height <= 300
                and ($sensitivity | type) == "number" and ($sensitivity | floor) == $sensitivity and $sensitivity >= 25 and $sensitivity <= 300
                and ($shape | type) == "string" and ($shapes | index($shape) != null)
                and ($bend | type) == "number" and ($bend | floor) == $bend and $bend >= -100 and $bend <= 100
              then {
                enabled: $enabled,
                x: $x,
                y: $y,
                scale: $scale,
                stretch_x: $stretch_x,
                stretch_y: $stretch_y,
                opacity: $opacity,
                color: (if $color == "auto" then "auto" else ($color | ascii_downcase) end),
                bands: $bands,
                gap: $gap,
                height: $height,
                sensitivity: $sensitivity,
                shape: $shape,
                bend: $bend
              }
              else error("invalid lockscreen visualizer")
              end
        end
    '
}

set_lockscreen_visualizer_enabled() {
    local enabled current normalized
    enabled="$(parse_bool "$1" 'lockscreen visualizer enabled')"
    current="$(jq -c --argjson defaults "$LOCKSCREEN_VISUALIZER_DEFAULT_JSON" \
        '.lockscreen_visualizer // $defaults' "$STATE_FILE")"
    if ! normalized="$(normalize_lockscreen_visualizer_json "$current" 2>/dev/null)"; then
        normalized="$LOCKSCREEN_VISUALIZER_DEFAULT_JSON"
    fi
    new_tmp
    jq --argjson visualizer "$normalized" --argjson enabled "$enabled" '
        .lockscreen_visualizer = ($visualizer | .enabled = $enabled)
    ' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

set_lockscreen_background_opacity() {
    local value
    value="$(normalize_percent_integer "$1" 'lockscreen background opacity')"
    new_tmp
    jq --argjson value "$value" '.lockscreen_background_opacity = $value' \
        "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

'''
app = replace_once(
    app,
    "validate_lockscreen_background() {",
    visualizer_functions + "validate_lockscreen_background() {",
    "visualizer functions",
)

app = replace_once(
    app,
    '    local custom_images_input="${13:-[]}"\n    local custom_images\n',
    '    local custom_images_input="${13:-[]}"\n'
    '    local visualizer_input="${14:-$LOCKSCREEN_VISUALIZER_DEFAULT_JSON}"\n'
    '    local background_opacity_input="${15:-100}"\n'
    '    local custom_images visualizer background_opacity\n',
    "editor save locals",
)
app = replace_once(
    app,
    '    custom_images="$(normalize_lockscreen_custom_images_json "$custom_images_input")"\n',
    '    custom_images="$(normalize_lockscreen_custom_images_json "$custom_images_input")"\n'
    '    visualizer="$(normalize_lockscreen_visualizer_json "$visualizer_input")"\n'
    '    background_opacity="$(normalize_percent_integer "$background_opacity_input" \'lockscreen background opacity\')"\n',
    "editor save normalization",
)
app = replace_once(
    app,
    '        --argjson custom_images "$custom_images" \'\n',
    '        --argjson custom_images "$custom_images" \\\n'
    '        --argjson visualizer "$visualizer" \\\n'
    '        --argjson background_opacity "$background_opacity" \'\n',
    "editor save jq args",
)
app = replace_once(
    app,
    '        | .lockscreen_custom_images = $custom_images\n',
    '        | .lockscreen_custom_images = $custom_images\n'
    '        | .lockscreen_visualizer = $visualizer\n'
    '        | .lockscreen_background_opacity = $background_opacity\n',
    "editor save assignments",
)

app = replace_once(
    app,
    '    jq --argjson layout "$LOCKSCREEN_LAYOUT_DEFAULT_JSON" \'\n',
    '    jq --argjson layout "$LOCKSCREEN_LAYOUT_DEFAULT_JSON" \\\n'
    '        --argjson visualizer "$LOCKSCREEN_VISUALIZER_DEFAULT_JSON" \'\n',
    "reset jq args",
)
app = replace_once(
    app,
    '        | .lockscreen_custom_images = []\n',
    '        | .lockscreen_custom_images = []\n'
    '        | .lockscreen_visualizer = $visualizer\n'
    '        | .lockscreen_background_opacity = 100\n',
    "reset Pass 3 assignments",
)

app = replace_once(
    app,
    '''    set-lockscreen-audio-reactive)
        [[ -n ${2:-} ]] || exit 2
        set_lockscreen_option lockscreen_audio_reactive "$2" 'lockscreen audio reactive'
        ;;
''',
    '''    set-lockscreen-visualizer-enabled)
        [[ -n ${2:-} ]] || exit 2
        set_lockscreen_visualizer_enabled "$2"
        ;;
    set-lockscreen-background-opacity)
        [[ -n ${2:-} ]] || exit 2
        set_lockscreen_background_opacity "$2"
        ;;
    set-lockscreen-audio-reactive)
        [[ -n ${2:-} ]] || exit 2
        set_lockscreen_option lockscreen_audio_reactive "$2" 'lockscreen audio reactive'
        ;;
''',
    "Pass 3 dispatch",
)
app = replace_once(
    app,
    '            6|12|13|14) ;;',
    '            6|12|13|14|16) ;;',
    "editor save argc",
)
app = replace_once(
    app,
    'set-lockscreen-logo-physics-hz <30|60|90>|set-lockscreen-audio-reactive <true|false>',
    'set-lockscreen-logo-physics-hz <30|60|90>|set-lockscreen-visualizer-enabled <true|false>|set-lockscreen-background-opacity <0-100>|set-lockscreen-audio-reactive <true|false>',
    "usage string",
)
app_path.write_text(app)


bar_path = Path("config/quickshell/awtarchy/BarState.qml")
bar = bar_path.read_text()

visualizer_default = '''    readonly property var defaultLockscreenVisualizer: ({
        enabled: false,
        x: 0.50,
        y: 0.80,
        scale: 1.0,
        stretch_x: 1.0,
        stretch_y: 1.0,
        opacity: 100,
        color: "auto",
        bands: 16,
        gap: 4,
        height: 100,
        sensitivity: 100,
        shape: "straight",
        bend: 45
    })
'''
bar = replace_once(
    bar,
    '    readonly property var defaultLockscreenLayout: ({\n',
    visualizer_default + '    readonly property var defaultLockscreenLayout: ({\n',
    "BarState visualizer defaults",
)
bar = replace_once(
    bar,
    '            lockscreen_custom_images: [],\n',
    '            lockscreen_custom_images: [],\n'
    '            lockscreen_visualizer: root.defaultLockscreenVisualizer,\n'
    '            lockscreen_background_opacity: 100,\n',
    "BarState empty data",
)

visualizer_readers = r'''    function lockscreenVisualizer() {
        const defaults = root.defaultLockscreenVisualizer;
        const value = data().lockscreen_visualizer;
        if (!value || typeof value !== "object" || Array.isArray(value))
            return defaults;

        const enabled = typeof value.enabled === "boolean" ? value.enabled : defaults.enabled;
        const x = Number(value.x ?? defaults.x);
        const y = Number(value.y ?? defaults.y);
        const scale = Number(value.scale ?? defaults.scale);
        const stretchX = Number(value.stretch_x ?? defaults.stretch_x);
        const stretchY = Number(value.stretch_y ?? defaults.stretch_y);
        const opacity = Number(value.opacity ?? defaults.opacity);
        const color = String(value.color ?? defaults.color).toLowerCase();
        const bands = Number(value.bands ?? defaults.bands);
        const gap = Number(value.gap ?? defaults.gap);
        const height = Number(value.height ?? defaults.height);
        const sensitivity = Number(value.sensitivity ?? defaults.sensitivity);
        const shape = String(value.shape ?? defaults.shape);
        const bend = Number(value.bend ?? defaults.bend);

        if (!Number.isFinite(x) || x < 0.05 || x > 0.95
                || !Number.isFinite(y) || y < 0.08 || y > 0.92
                || !Number.isFinite(scale) || scale < 0.5 || scale > 2
                || !Number.isFinite(stretchX) || stretchX < 0.25 || stretchX > 4
                || !Number.isFinite(stretchY) || stretchY < 0.25 || stretchY > 4
                || !Number.isFinite(opacity) || opacity < 0 || opacity > 100
                || (color !== "auto" && !/^#[0-9a-f]{6}$/.test(color))
                || !Number.isInteger(bands) || bands < 4 || bands > 64
                || !Number.isInteger(gap) || gap < 0 || gap > 24
                || !Number.isInteger(height) || height < 25 || height > 300
                || !Number.isInteger(sensitivity) || sensitivity < 25 || sensitivity > 300
                || ["straight", "arc", "circle"].indexOf(shape) < 0
                || !Number.isInteger(bend) || bend < -100 || bend > 100)
            return defaults;

        return ({
            enabled: enabled,
            x: x,
            y: y,
            scale: scale,
            stretch_x: stretchX,
            stretch_y: stretchY,
            opacity: Math.round(opacity),
            color: color,
            bands: bands,
            gap: gap,
            height: height,
            sensitivity: sensitivity,
            shape: shape,
            bend: bend
        });
    }

    function lockscreenBackgroundOpacity() {
        const value = Number(data().lockscreen_background_opacity);
        if (!Number.isFinite(value) || !Number.isInteger(value) || value < 0 || value > 100)
            return 100;
        return value;
    }

'''
bar = replace_once(
    bar,
    '    function lockscreenAudioReactiveEnabled() {\n',
    visualizer_readers + '    function lockscreenAudioReactiveEnabled() {\n',
    "BarState Pass 3 readers",
)
bar_path.write_text(bar)
