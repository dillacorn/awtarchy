#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
STATE = ROOT / "config/hypr/scripts/quickshell_application_state.sh"
BAR = ROOT / "config/quickshell/awtarchy/BarState.qml"
EDITOR = ROOT / "config/quickshell/awtarchy/LockscreenEditor.qml"
PREVIEW = ROOT / "config/quickshell/awtarchy/LockPreviewScene.qml"
SECURE = ROOT / "config/quickshell/awtarchy-lock/LockScene.qml"
SURFACE = ROOT / "config/quickshell/awtarchy-lock/LockSurface.qml"
LOCK_SHELL = ROOT / "config/quickshell/awtarchy-lock/shell.qml"


def once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


# ---------------------------------------------------------------------------
# Persistent Bash state backend
# ---------------------------------------------------------------------------
text = STATE.read_text()
text = once(
    text,
    "LOCKSCREEN_BACKGROUNDS_JSON='[\"black\",\"wallpaper\",\"color\"]'\n",
    "LOCKSCREEN_BACKGROUNDS_JSON='[\"black\",\"wallpaper\",\"color\"]'\n"
    "LOCKSCREEN_WALLPAPER_FITS_JSON='[\"cover\",\"contain\"]'\n"
    "LOCKSCREEN_OVERLAY_MODES_JSON='[\"none\",\"dark\",\"light\"]'\n",
    "state composition enums",
)
anchor = '''validate_lockscreen_background() {
'''
helpers = '''lockscreen_composition_defaults() {
    jq -cn '{
        lockscreen_wallpaper_fit: "cover",
        lockscreen_wallpaper_focal_x: 0.5,
        lockscreen_wallpaper_focal_y: 0.5,
        lockscreen_overlay_mode: "none",
        lockscreen_overlay_strength: 0,
        lockscreen_wallpaper_blur: 0
    }'
}

validate_lockscreen_wallpaper_fit() {
    local value="$1"
    if ! jq -e -n --arg value "$value" --argjson allowed "$LOCKSCREEN_WALLPAPER_FITS_JSON" \
        '$allowed | index($value) != null' >/dev/null 2>&1; then
        printf 'invalid lockscreen wallpaper fit: %s\\n' "$value" >&2
        exit 2
    fi
}

validate_lockscreen_overlay_mode() {
    local value="$1"
    if ! jq -e -n --arg value "$value" --argjson allowed "$LOCKSCREEN_OVERLAY_MODES_JSON" \
        '$allowed | index($value) != null' >/dev/null 2>&1; then
        printf 'invalid lockscreen overlay mode: %s\\n' "$value" >&2
        exit 2
    fi
}

normalize_unit_interval() {
    local value="$1" label="$2" normalized
    if ! normalized="$(jq -er -n --arg value "$value" '
        ($value | tonumber?) as $number
        | if $number != null and $number >= 0 and $number <= 1 then $number
          else error("out of range") end
    ' 2>/dev/null)"; then
        printf '%s must be 0-1\\n' "$label" >&2
        exit 2
    fi
    printf '%s' "$normalized"
}

normalize_percent_integer() {
    local value="$1" label="$2"
    [[ "$value" =~ ^[0-9]+$ ]] || {
        printf '%s must be an integer\\n' "$label" >&2
        exit 2
    }
    local numeric=$((10#$value))
    (( numeric >= 0 && numeric <= 100 )) || {
        printf '%s must be 0-100\\n' "$label" >&2
        exit 2
    }
    printf '%d' "$numeric"
}

'''
text = once(text, anchor, helpers + anchor, "state composition validators")
old_save = '''save_lockscreen_editor() {
    local normalized visibility="$2" background="$3" background_color="${4,,}" wallpaper="$5"
    if ! normalized="$(normalize_lockscreen_layout_json "$1" 2>/dev/null)"; then
        printf 'invalid lockscreen layout\\n' >&2
        exit 2
    fi
    validate_lockscreen_editor_visibility "$visibility"
    validate_lockscreen_background "$background"
    validate_lockscreen_hex_color "$background_color" 'lockscreen background color'
    wallpaper="$(normalize_lockscreen_wallpaper_path "$wallpaper")"
    if [[ "$background" == 'wallpaper' && -z "$wallpaper" ]]; then
        printf 'wallpaper background requires a selected local image\\n' >&2
        exit 2
    fi
    new_tmp
    jq \\
        --argjson layout "$normalized" \\
        --argjson visibility "$visibility" \\
        --arg background "$background" \\
        --arg background_color "$background_color" \\
        --arg wallpaper "$wallpaper" '
        .lockscreen_layout = $layout
        | .lockscreen_show_logo = $visibility.logo
        | .lockscreen_show_time = $visibility.time
        | .lockscreen_show_date = $visibility.date
        | .lockscreen_show_username = $visibility.username
        | .lockscreen_show_weather = $visibility.weather
        | .lockscreen_background = $background
        | .lockscreen_background_color = $background_color
        | .lockscreen_wallpaper_path = $wallpaper
    ' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}
'''
new_save = '''save_lockscreen_editor() {
    local normalized visibility="$2" background="$3" background_color="${4,,}" wallpaper="$5"
    local wallpaper_fit="${6:-cover}"
    local focal_x="${7:-0.5}"
    local focal_y="${8:-0.5}"
    local overlay_mode="${9:-none}"
    local overlay_strength="${10:-0}"
    local wallpaper_blur="${11:-0}"
    if ! normalized="$(normalize_lockscreen_layout_json "$1" 2>/dev/null)"; then
        printf 'invalid lockscreen layout\\n' >&2
        exit 2
    fi
    validate_lockscreen_editor_visibility "$visibility"
    validate_lockscreen_background "$background"
    validate_lockscreen_hex_color "$background_color" 'lockscreen background color'
    validate_lockscreen_wallpaper_fit "$wallpaper_fit"
    validate_lockscreen_overlay_mode "$overlay_mode"
    focal_x="$(normalize_unit_interval "$focal_x" 'lockscreen wallpaper focal x')"
    focal_y="$(normalize_unit_interval "$focal_y" 'lockscreen wallpaper focal y')"
    overlay_strength="$(normalize_percent_integer "$overlay_strength" 'lockscreen overlay strength')"
    wallpaper_blur="$(normalize_percent_integer "$wallpaper_blur" 'lockscreen wallpaper blur')"
    wallpaper="$(normalize_lockscreen_wallpaper_path "$wallpaper")"
    if [[ "$background" == 'wallpaper' && -z "$wallpaper" ]]; then
        printf 'wallpaper background requires a selected local image\\n' >&2
        exit 2
    fi
    new_tmp
    jq \\
        --argjson layout "$normalized" \\
        --argjson visibility "$visibility" \\
        --arg background "$background" \\
        --arg background_color "$background_color" \\
        --arg wallpaper "$wallpaper" \\
        --arg wallpaper_fit "$wallpaper_fit" \\
        --argjson focal_x "$focal_x" \\
        --argjson focal_y "$focal_y" \\
        --arg overlay_mode "$overlay_mode" \\
        --argjson overlay_strength "$overlay_strength" \\
        --argjson wallpaper_blur "$wallpaper_blur" '
        .lockscreen_layout = $layout
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
    ' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}
'''
text = once(text, old_save, new_save, "state atomic editor save")
old_reset_tail = '''        | .lockscreen_background = "black"
        | .lockscreen_background_color = "#000000"
        | .lockscreen_wallpaper_path = ""
        | .lockscreen_weather_location = ""
        | .lockscreen_layout = $layout
'''
new_reset_tail = '''        | .lockscreen_background = "black"
        | .lockscreen_background_color = "#000000"
        | .lockscreen_wallpaper_path = ""
        | .lockscreen_wallpaper_fit = "cover"
        | .lockscreen_wallpaper_focal_x = 0.5
        | .lockscreen_wallpaper_focal_y = 0.5
        | .lockscreen_overlay_mode = "none"
        | .lockscreen_overlay_strength = 0
        | .lockscreen_wallpaper_blur = 0
        | .lockscreen_weather_location = ""
        | .lockscreen_layout = $layout
'''
text = once(text, old_reset_tail, new_reset_tail, "state reset composition")
STATE.write_text(text)

# ---------------------------------------------------------------------------
# BarState persistent getters
# ---------------------------------------------------------------------------
text = BAR.read_text()
text = once(
    text,
    '''    readonly property var defaultLockscreenLayout: ({
''',
    '''    readonly property var defaultLockscreenComposition: ({
        lockscreen_wallpaper_fit: "cover",
        lockscreen_wallpaper_focal_x: 0.5,
        lockscreen_wallpaper_focal_y: 0.5,
        lockscreen_overlay_mode: "none",
        lockscreen_overlay_strength: 0,
        lockscreen_wallpaper_blur: 0
    })
    readonly property var defaultLockscreenLayout: ({
''',
    "BarState composition defaults",
)
anchor = '''    function lockscreenWeatherLocation() {
'''
getters = '''    function lockscreenWallpaperFit() {
        const value = String(data().lockscreen_wallpaper_fit || "");
        return ["cover", "contain"].indexOf(value) >= 0 ? value : "cover";
    }

    function lockscreenWallpaperFocalX() {
        const value = Number(data().lockscreen_wallpaper_focal_x);
        return Number.isFinite(value) ? Math.max(0, Math.min(1, value)) : 0.5;
    }

    function lockscreenWallpaperFocalY() {
        const value = Number(data().lockscreen_wallpaper_focal_y);
        return Number.isFinite(value) ? Math.max(0, Math.min(1, value)) : 0.5;
    }

    function lockscreenOverlayMode() {
        const value = String(data().lockscreen_overlay_mode || "");
        return ["none", "dark", "light"].indexOf(value) >= 0 ? value : "none";
    }

    function lockscreenOverlayStrength() {
        const value = Number(data().lockscreen_overlay_strength);
        return Number.isFinite(value) ? Math.max(0, Math.min(100, Math.round(value))) : 0;
    }

    function lockscreenWallpaperBlur() {
        const value = Number(data().lockscreen_wallpaper_blur);
        return Number.isFinite(value) ? Math.max(0, Math.min(100, Math.round(value))) : 0;
    }

'''
text = once(text, anchor, getters + anchor, "BarState composition getters")
BAR.write_text(text)

# ---------------------------------------------------------------------------
# Editor draft/history/save/controls
# ---------------------------------------------------------------------------
text = EDITOR.read_text()
text = once(
    text,
    '''    property string draftWallpaperPath: ""
''',
    '''    property string draftWallpaperPath: ""
    property string draftWallpaperFit: "cover"
    property real draftWallpaperFocalX: 0.5
    property real draftWallpaperFocalY: 0.5
    property string draftOverlayMode: "none"
    property int draftOverlayStrength: 0
    property int draftWallpaperBlur: 0
''',
    "editor composition draft properties",
)
old_snapshot = '''            backgroundMode: draftBackgroundMode,
            backgroundColor: draftBackgroundColor,
            wallpaperPath: draftWallpaperPath
'''
new_snapshot = '''            backgroundMode: draftBackgroundMode,
            backgroundColor: draftBackgroundColor,
            wallpaperPath: draftWallpaperPath,
            wallpaperFit: draftWallpaperFit,
            wallpaperFocalX: draftWallpaperFocalX,
            wallpaperFocalY: draftWallpaperFocalY,
            overlayMode: draftOverlayMode,
            overlayStrength: draftOverlayStrength,
            wallpaperBlur: draftWallpaperBlur
'''
text = once(text, old_snapshot, new_snapshot, "editor composition history snapshot")
old_restore = '''        draftWallpaperPath = typeof snapshot.wallpaperPath === "string"
            ? snapshot.wallpaperPath : "";
        scheduleContrastRefresh();
'''
new_restore = '''        draftWallpaperPath = typeof snapshot.wallpaperPath === "string"
            ? snapshot.wallpaperPath : "";
        draftWallpaperFit = ["cover", "contain"].indexOf(String(snapshot.wallpaperFit)) >= 0
            ? String(snapshot.wallpaperFit) : "cover";
        const focalX = Number(snapshot.wallpaperFocalX);
        const focalY = Number(snapshot.wallpaperFocalY);
        draftWallpaperFocalX = Number.isFinite(focalX) ? Math.max(0, Math.min(1, focalX)) : 0.5;
        draftWallpaperFocalY = Number.isFinite(focalY) ? Math.max(0, Math.min(1, focalY)) : 0.5;
        draftOverlayMode = ["none", "dark", "light"].indexOf(String(snapshot.overlayMode)) >= 0
            ? String(snapshot.overlayMode) : "none";
        const overlayStrength = Number(snapshot.overlayStrength);
        const wallpaperBlur = Number(snapshot.wallpaperBlur);
        draftOverlayStrength = Number.isFinite(overlayStrength)
            ? Math.max(0, Math.min(100, Math.round(overlayStrength))) : 0;
        draftWallpaperBlur = Number.isFinite(wallpaperBlur)
            ? Math.max(0, Math.min(100, Math.round(wallpaperBlur))) : 0;
        scheduleContrastRefresh();
'''
text = once(text, old_restore, new_restore, "editor restore composition history")
anchor = '''    function acceptWallpaperSelection(line) {
'''
setters = '''    function setDraftWallpaperFit(value) {
        const fit = String(value || "");
        if (["cover", "contain"].indexOf(fit) < 0)
            return;
        recordUndoBeforeChange();
        draftWallpaperFit = fit;
    }

    function setDraftWallpaperFocal(x, y) {
        const nextX = Number(x);
        const nextY = Number(y);
        if (!Number.isFinite(nextX) || !Number.isFinite(nextY))
            return;
        recordUndoBeforeChange();
        draftWallpaperFocalX = Math.max(0, Math.min(1, nextX));
        draftWallpaperFocalY = Math.max(0, Math.min(1, nextY));
        scheduleContrastRefresh();
    }

    function setDraftOverlay(mode, strength) {
        const nextMode = String(mode || "");
        const nextStrength = Number(strength);
        if (["none", "dark", "light"].indexOf(nextMode) < 0 || !Number.isFinite(nextStrength))
            return;
        recordUndoBeforeChange();
        draftOverlayMode = nextMode;
        draftOverlayStrength = Math.max(0, Math.min(100, Math.round(nextStrength)));
        scheduleContrastRefresh();
    }

    function setDraftWallpaperBlur(value) {
        const next = Number(value);
        if (!Number.isFinite(next))
            return;
        recordUndoBeforeChange();
        draftWallpaperBlur = Math.max(0, Math.min(100, Math.round(next)));
    }

'''
text = once(text, anchor, setters + anchor, "editor composition setters")
old_reset = '''        draftBackgroundColor = "#000000";
        draftWallpaperPath = "";
        draftAutoAccents = defaultAutoAccents();
'''
new_reset = '''        draftBackgroundColor = "#000000";
        draftWallpaperPath = "";
        draftWallpaperFit = "cover";
        draftWallpaperFocalX = 0.5;
        draftWallpaperFocalY = 0.5;
        draftOverlayMode = "none";
        draftOverlayStrength = 0;
        draftWallpaperBlur = 0;
        draftAutoAccents = defaultAutoAccents();
'''
text = once(text, old_reset, new_reset, "editor reset composition")
old_load = '''        draftBackgroundColor = BarState.lockscreenBackgroundColor();
        draftWallpaperPath = BarState.lockscreenWallpaperPath();
        draftAutoAccents = defaultAutoAccents();
'''
new_load = '''        draftBackgroundColor = BarState.lockscreenBackgroundColor();
        draftWallpaperPath = BarState.lockscreenWallpaperPath();
        draftWallpaperFit = BarState.lockscreenWallpaperFit();
        draftWallpaperFocalX = BarState.lockscreenWallpaperFocalX();
        draftWallpaperFocalY = BarState.lockscreenWallpaperFocalY();
        draftOverlayMode = BarState.lockscreenOverlayMode();
        draftOverlayStrength = BarState.lockscreenOverlayStrength();
        draftWallpaperBlur = BarState.lockscreenWallpaperBlur();
        draftAutoAccents = defaultAutoAccents();
'''
text = once(text, old_load, new_load, "editor load composition")
old_save_args = '''            draftBackgroundMode,
            draftBackgroundColor,
            draftWallpaperPath
'''
new_save_args = '''            draftBackgroundMode,
            draftBackgroundColor,
            draftWallpaperPath,
            draftWallpaperFit,
            String(draftWallpaperFocalX),
            String(draftWallpaperFocalY),
            draftOverlayMode,
            String(draftOverlayStrength),
            String(draftWallpaperBlur)
'''
text = once(text, old_save_args, new_save_args, "editor save composition")
old_preview = '''                backgroundMode: root.draftBackgroundMode
                wallpaperSource: wallpaperState.source
                backgroundColor: root.draftBackgroundColor
                autoAccents: root.draftAutoAccents
'''
new_preview = '''                backgroundMode: root.draftBackgroundMode
                wallpaperSource: wallpaperState.source
                backgroundColor: root.draftBackgroundColor
                wallpaperFit: root.draftWallpaperFit
                wallpaperFocalX: root.draftWallpaperFocalX
                wallpaperFocalY: root.draftWallpaperFocalY
                overlayMode: root.draftOverlayMode
                overlayStrength: root.draftOverlayStrength
                wallpaperBlur: root.draftWallpaperBlur
                autoAccents: root.draftAutoAccents
'''
text = once(text, old_preview, new_preview, "editor preview composition bindings")

# Focal handle before element selection rectangles so actual element drag targets
# retain higher z-order.
repeater_anchor = '''            Repeater {
                model: root.elementNames
'''
focal_handle = '''            Rectangle {
                id: wallpaperFocalHandle
                visible: root.draftBackgroundMode === "wallpaper"
                    && root.draftWallpaperFit === "cover"
                    && root.draftWallpaperPath.length > 0
                width: 22
                height: 22
                radius: width / 2
                x: root.draftWallpaperFocalX * Math.max(0, parent.width - width)
                y: root.draftWallpaperFocalY * Math.max(0, parent.height - height)
                color: "transparent"
                border.width: 2
                border.color: Theme.focus
                z: 190

                Rectangle {
                    anchors.centerIn: parent
                    width: 4
                    height: 4
                    radius: 2
                    color: Theme.focus
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.CrossCursor
                    preventStealing: true
                    onPressed: root.beginHistoryTransaction()
                    onPositionChanged: mouse => {
                        if (!pressed || editorFocus.width <= 0 || editorFocus.height <= 0)
                            return;
                        const scenePoint = parent.mapToItem(editorFocus, mouse.x, mouse.y);
                        root.setDraftWallpaperFocal(
                            scenePoint.x / editorFocus.width,
                            scenePoint.y / editorFocus.height);
                    }
                    onReleased: root.commitHistoryTransaction()
                    onCanceled: root.commitHistoryTransaction()
                }
            }

'''
text = once(text, repeater_anchor, focal_handle + repeater_anchor, "editor wallpaper focal handle")

# Increase panel base height and add composition row after background row.
text = once(
    text,
    '                height: 184 + ((root.elementPaletteOpen || root.backgroundPaletteOpen) ? 150 : 0)\n',
    '                height: 224 + ((root.elementPaletteOpen || root.backgroundPaletteOpen) ? 150 : 0)\n',
    "editor panel height",
)
background_row_end = '''                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: visible ? 142 : 0
                        spacing: 12
                        visible: root.elementPaletteOpen || root.backgroundPaletteOpen
'''
composition_row = '''                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 7

                        Text {
                            text: "Wallpaper fit"
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                        }
                        SettingsButton {
                            label: "Cover"
                            active: root.draftWallpaperFit === "cover"
                            available: root.draftWallpaperPath.length > 0
                            textSize: 9
                            onClicked: root.setDraftWallpaperFit("cover")
                        }
                        SettingsButton {
                            label: "Contain"
                            active: root.draftWallpaperFit === "contain"
                            available: root.draftWallpaperPath.length > 0
                            textSize: 9
                            onClicked: root.setDraftWallpaperFit("contain")
                        }

                        Text {
                            text: "Overlay"
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                        }
                        SettingsButton {
                            label: "None"
                            active: root.draftOverlayMode === "none"
                            textSize: 9
                            onClicked: root.setDraftOverlay("none", root.draftOverlayStrength)
                        }
                        SettingsButton {
                            label: "Darken"
                            active: root.draftOverlayMode === "dark"
                            textSize: 9
                            onClicked: root.setDraftOverlay("dark",
                                root.draftOverlayStrength > 0 ? root.draftOverlayStrength : 35)
                        }
                        SettingsButton {
                            label: "Lighten"
                            active: root.draftOverlayMode === "light"
                            textSize: 9
                            onClicked: root.setDraftOverlay("light",
                                root.draftOverlayStrength > 0 ? root.draftOverlayStrength : 35)
                        }
                        Slider {
                            id: overlaySlider
                            Layout.preferredWidth: 120
                            from: 0
                            to: 100
                            stepSize: 1
                            value: root.draftOverlayStrength
                            onPressedChanged: {
                                if (pressed) root.beginHistoryTransaction();
                                else root.commitHistoryTransaction();
                            }
                            onMoved: root.setDraftOverlay(root.draftOverlayMode, value)
                        }
                        Text {
                            text: root.draftOverlayStrength + "%"
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            Layout.preferredWidth: 34
                        }

                        Text {
                            text: "Blur"
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                        }
                        Slider {
                            id: blurSlider
                            Layout.preferredWidth: 110
                            from: 0
                            to: 100
                            stepSize: 1
                            value: root.draftWallpaperBlur
                            enabled: root.draftBackgroundMode === "wallpaper"
                            onPressedChanged: {
                                if (pressed) root.beginHistoryTransaction();
                                else root.commitHistoryTransaction();
                            }
                            onMoved: root.setDraftWallpaperBlur(value)
                        }
                        Text {
                            text: root.draftWallpaperBlur + "%"
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            Layout.preferredWidth: 34
                        }
                    }

'''
text = once(text, background_row_end, composition_row + background_row_end, "editor composition controls")
EDITOR.write_text(text)

# ---------------------------------------------------------------------------
# Byte-identical presentation scene background composition
# ---------------------------------------------------------------------------
text = PREVIEW.read_text()
text = once(text, 'import QtQuick.Layouts\n', 'import QtQuick.Layouts\nimport QtQuick.Effects\n', "scene effects import")
text = once(
    text,
    '''    required property color backgroundColor
    required property var autoAccents
''',
    '''    required property color backgroundColor
    required property string wallpaperFit
    required property real wallpaperFocalX
    required property real wallpaperFocalY
    required property string overlayMode
    required property real overlayStrength
    required property real wallpaperBlur
    required property var autoAccents
''',
    "scene composition inputs",
)
function_anchor = '''    function normalizedPoint(name) {
'''
geometry = '''    function wallpaperGeometry() {
        const sourceWidth = Number(wallpaperImage.sourceSize.width);
        const sourceHeight = Number(wallpaperImage.sourceSize.height);
        if (!Number.isFinite(sourceWidth) || !Number.isFinite(sourceHeight)
                || sourceWidth <= 0 || sourceHeight <= 0 || root.width <= 0 || root.height <= 0)
            return ({ x: 0, y: 0, width: root.width, height: root.height });
        const contain = root.wallpaperFit === "contain";
        const factor = contain
            ? Math.min(root.width / sourceWidth, root.height / sourceHeight)
            : Math.max(root.width / sourceWidth, root.height / sourceHeight);
        const targetWidth = sourceWidth * factor;
        const targetHeight = sourceHeight * factor;
        if (contain) {
            return ({
                x: (root.width - targetWidth) / 2,
                y: (root.height - targetHeight) / 2,
                width: targetWidth,
                height: targetHeight
            });
        }
        const focalX = Math.max(0, Math.min(1, Number(root.wallpaperFocalX)));
        const focalY = Math.max(0, Math.min(1, Number(root.wallpaperFocalY)));
        return ({
            x: -(targetWidth - root.width) * focalX,
            y: -(targetHeight - root.height) * focalY,
            width: targetWidth,
            height: targetHeight
        });
    }

'''
text = once(text, function_anchor, geometry + function_anchor, "scene wallpaper geometry")
old_background = '''    Rectangle {
        anchors.fill: parent
        color: root.backgroundMode === "color" ? root.backgroundColor : "#000000"
    }

    Image {
        anchors.fill: parent
        visible: root.backgroundMode === "wallpaper" && root.wallpaperSource.length > 0
        source: root.wallpaperSource
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
    }

'''
new_background = '''    Rectangle {
        anchors.fill: parent
        color: root.backgroundMode === "color" ? root.backgroundColor : "#000000"
    }

    Image {
        id: wallpaperImage
        readonly property var geometry: root.wallpaperGeometry()
        x: geometry.x
        y: geometry.y
        width: geometry.width
        height: geometry.height
        visible: false
        source: root.wallpaperSource
        fillMode: Image.Stretch
        asynchronous: true
        cache: true
    }

    MultiEffect {
        x: wallpaperImage.x
        y: wallpaperImage.y
        width: wallpaperImage.width
        height: wallpaperImage.height
        visible: root.backgroundMode === "wallpaper" && root.wallpaperSource.length > 0
        source: wallpaperImage
        autoPaddingEnabled: false
        blurEnabled: root.wallpaperBlur > 0
        blurMax: 32
        blur: Math.max(0, Math.min(1, root.wallpaperBlur / 100))
    }

    Rectangle {
        id: backgroundOverlay
        anchors.fill: parent
        visible: root.overlayMode !== "none" && root.overlayStrength > 0
        color: root.overlayMode === "light" ? "#ffffff" : "#000000"
        opacity: Math.max(0, Math.min(100, root.overlayStrength)) / 100
    }

'''
text = once(text, old_background, new_background, "scene composed background")
PREVIEW.write_text(text)
SECURE.write_bytes(PREVIEW.read_bytes())

# ---------------------------------------------------------------------------
# Secure LockSurface propagation
# ---------------------------------------------------------------------------
text = SURFACE.read_text()
text = once(
    text,
    '''    required property color backgroundColor
    required property var autoAccents
''',
    '''    required property color backgroundColor
    required property string wallpaperFit
    required property real wallpaperFocalX
    required property real wallpaperFocalY
    required property string overlayMode
    required property real overlayStrength
    required property real wallpaperBlur
    required property var autoAccents
''',
    "LockSurface composition properties",
)
text = once(
    text,
    '''        backgroundColor: root.backgroundColor
        autoAccents: root.autoAccents
''',
    '''        backgroundColor: root.backgroundColor
        wallpaperFit: root.wallpaperFit
        wallpaperFocalX: root.wallpaperFocalX
        wallpaperFocalY: root.wallpaperFocalY
        overlayMode: root.overlayMode
        overlayStrength: root.overlayStrength
        wallpaperBlur: root.wallpaperBlur
        autoAccents: root.autoAccents
''',
    "LockSurface scene composition bindings",
)
SURFACE.write_text(text)

# ---------------------------------------------------------------------------
# Secure shell independent normalization
# ---------------------------------------------------------------------------
text = LOCK_SHELL.read_text()
text = once(
    text,
    '''    property string lockWallpaperPath: ""
    property string lockWeatherLocation: ""
''',
    '''    property string lockWallpaperPath: ""
    property string lockWallpaperFit: "cover"
    property real lockWallpaperFocalX: 0.5
    property real lockWallpaperFocalY: 0.5
    property string lockOverlayMode: "none"
    property int lockOverlayStrength: 0
    property int lockWallpaperBlur: 0
    property string lockWeatherLocation: ""
    readonly property string wallpaperFit: normalizedWallpaperFit(lockWallpaperFit)
    readonly property real wallpaperFocalX: normalizedUnitInterval(lockWallpaperFocalX, 0.5)
    readonly property real wallpaperFocalY: normalizedUnitInterval(lockWallpaperFocalY, 0.5)
    readonly property string overlayMode: normalizedOverlayMode(lockOverlayMode)
    readonly property int overlayStrength: normalizedPercent(lockOverlayStrength)
    readonly property int wallpaperBlur: normalizedPercent(lockWallpaperBlur)
''',
    "secure composition state",
)
anchor = '''    function normalizedWallpaperPath(value) {
'''
normalizers = '''    function normalizedWallpaperFit(value) {
        const key = String(value || "");
        return ["cover", "contain"].indexOf(key) >= 0 ? key : "cover";
    }

    function normalizedOverlayMode(value) {
        const key = String(value || "");
        return ["none", "dark", "light"].indexOf(key) >= 0 ? key : "none";
    }

    function normalizedUnitInterval(value, fallback) {
        const numeric = Number(value);
        return Number.isFinite(numeric) ? Math.max(0, Math.min(1, numeric)) : fallback;
    }

    function normalizedPercent(value) {
        const numeric = Number(value);
        return Number.isFinite(numeric) ? Math.max(0, Math.min(100, Math.round(numeric))) : 0;
    }

'''
text = once(text, anchor, normalizers + anchor, "secure composition normalizers")
text = once(
    text,
    '''        lockWallpaperPath = "";
        lockWeatherLocation = "";
''',
    '''        lockWallpaperPath = "";
        lockWallpaperFit = "cover";
        lockWallpaperFocalX = 0.5;
        lockWallpaperFocalY = 0.5;
        lockOverlayMode = "none";
        lockOverlayStrength = 0;
        lockWallpaperBlur = 0;
        lockWeatherLocation = "";
''',
    "secure reset composition",
)
text = once(
    text,
    '''            lockWallpaperPath = normalizedWallpaperPath(parsed.lockscreen_wallpaper_path);
            lockWeatherLocation = normalizedWeatherLocation(parsed.lockscreen_weather_location);
''',
    '''            lockWallpaperPath = normalizedWallpaperPath(parsed.lockscreen_wallpaper_path);
            lockWallpaperFit = normalizedWallpaperFit(parsed.lockscreen_wallpaper_fit);
            lockWallpaperFocalX = normalizedUnitInterval(parsed.lockscreen_wallpaper_focal_x, 0.5);
            lockWallpaperFocalY = normalizedUnitInterval(parsed.lockscreen_wallpaper_focal_y, 0.5);
            lockOverlayMode = normalizedOverlayMode(parsed.lockscreen_overlay_mode);
            lockOverlayStrength = normalizedPercent(parsed.lockscreen_overlay_strength);
            lockWallpaperBlur = normalizedPercent(parsed.lockscreen_wallpaper_blur);
            lockWeatherLocation = normalizedWeatherLocation(parsed.lockscreen_weather_location);
''',
    "secure load composition",
)
text = once(
    text,
    '''                backgroundColor: root.lockBackgroundColor
                autoAccents: lockContrastCache.colors
''',
    '''                backgroundColor: root.lockBackgroundColor
                wallpaperFit: root.wallpaperFit
                wallpaperFocalX: root.wallpaperFocalX
                wallpaperFocalY: root.wallpaperFocalY
                overlayMode: root.overlayMode
                overlayStrength: root.overlayStrength
                wallpaperBlur: root.wallpaperBlur
                autoAccents: lockContrastCache.colors
''',
    "secure surface composition bindings",
)
LOCK_SHELL.write_text(text)

if PREVIEW.read_bytes() != SECURE.read_bytes():
    raise SystemExit("secure and preview scene parity lost")
