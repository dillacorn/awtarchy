#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def replace_once(rel, old, new):
    path = ROOT / rel
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{rel}: expected one anchor, found {count}: {old[:120]!r}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


STATE = "config/hypr/scripts/quickshell_application_state.sh"
BAR_STATE = "config/quickshell/awtarchy/BarState.qml"
SHELL = "config/quickshell/awtarchy-lock/shell.qml"
SURFACE = "config/quickshell/awtarchy-lock/LockSurface.qml"
SCENE = "config/quickshell/awtarchy-lock/LockScene.qml"
PREVIEW = "config/quickshell/awtarchy/LockPreviewScene.qml"
EDITOR = "config/quickshell/awtarchy/LockscreenEditor.qml"
QUICK = "config/quickshell/awtarchy/QuickSettings.qml"

# Persisted state helper.
replace_once(
    STATE,
    "LOCKSCREEN_ANIMATIONS_JSON='[\"random\",\"swarm\",\"edges\",\"center\",\"split\",\"off\"]'\n",
    "LOCKSCREEN_ANIMATIONS_JSON='[\"random\",\"swarm\",\"edges\",\"center\",\"split\",\"off\"]'\n"
    "LOCKSCREEN_ENTRY_TRANSITIONS_JSON='[\"fade\",\"pixel\",\"iris\",\"edges\",\"wipe\"]'\n",
)
replace_once(
    STATE,
    '''validate_lockscreen_animation() {
    local value="$1"
    if ! jq -e -n \\
        --arg value "$value" \\
        --argjson allowed "$LOCKSCREEN_ANIMATIONS_JSON" \\
        '$allowed | index($value) != null' >/dev/null 2>&1; then
        printf 'invalid lockscreen animation: %s\\n' "$value" >&2
        exit 2
    fi
}


validate_cursor_variant() {''',
    '''validate_lockscreen_animation() {
    local value="$1"
    if ! jq -e -n \\
        --arg value "$value" \\
        --argjson allowed "$LOCKSCREEN_ANIMATIONS_JSON" \\
        '$allowed | index($value) != null' >/dev/null 2>&1; then
        printf 'invalid lockscreen animation: %s\\n' "$value" >&2
        exit 2
    fi
}

validate_lockscreen_entry_transition() {
    local value="$1"
    if ! jq -e -n \\
        --arg value "$value" \\
        --argjson allowed "$LOCKSCREEN_ENTRY_TRANSITIONS_JSON" \\
        '$allowed | index($value) != null' >/dev/null 2>&1; then
        printf 'invalid lockscreen entry transition: %s\\n' "$value" >&2
        exit 2
    fi
}


validate_cursor_variant() {''',
)
replace_once(
    STATE,
    '''set_lockscreen_animation() {
    local value="$1"
    validate_lockscreen_animation "$value"
    new_tmp
    jq --arg value "$value" '.lockscreen_animation = $value' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

set_lockscreen_logo_physics_hz() {''',
    '''set_lockscreen_animation() {
    local value="$1"
    validate_lockscreen_animation "$value"
    new_tmp
    jq --arg value "$value" '.lockscreen_animation = $value' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

set_lockscreen_entry_transition() {
    local value="$1"
    validate_lockscreen_entry_transition "$value"
    new_tmp
    jq --arg value "$value" '.lockscreen_entry_transition = $value' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

set_lockscreen_logo_physics_hz() {''',
)
replace_once(
    STATE,
    '''    local visualizer_input="${14:-$LOCKSCREEN_VISUALIZER_DEFAULT_JSON}"
    local background_opacity_input="${15:-100}"
    local custom_images visualizer background_opacity
''',
    '''    local visualizer_input="${14:-$LOCKSCREEN_VISUALIZER_DEFAULT_JSON}"
    local background_opacity_input="${15:-100}"
    local entry_transition_input="${16:-}"
    local custom_images visualizer background_opacity entry_transition
''',
)
replace_once(
    STATE,
    '''    background_opacity="$(normalize_percent_integer "$background_opacity_input" 'lockscreen background opacity')"
    validate_lockscreen_editor_visibility "$visibility"
''',
    '''    background_opacity="$(normalize_percent_integer "$background_opacity_input" 'lockscreen background opacity')"
    if [[ -n "$entry_transition_input" ]]; then
        entry_transition="$entry_transition_input"
        validate_lockscreen_entry_transition "$entry_transition"
    else
        entry_transition="$(jq -r '.lockscreen_entry_transition // "fade"' "$STATE_FILE")"
        if ! jq -e -n --arg value "$entry_transition" \\
            --argjson allowed "$LOCKSCREEN_ENTRY_TRANSITIONS_JSON" \\
            '$allowed | index($value) != null' >/dev/null 2>&1; then
            entry_transition="fade"
        fi
    fi
    validate_lockscreen_editor_visibility "$visibility"
''',
)
replace_once(
    STATE,
    '''        --argjson visualizer "$visualizer" \\
        --argjson background_opacity "$background_opacity" '
        .lockscreen_layout = $layout
''',
    '''        --argjson visualizer "$visualizer" \\
        --argjson background_opacity "$background_opacity" \\
        --arg entry_transition "$entry_transition" '
        .lockscreen_layout = $layout
''',
)
replace_once(
    STATE,
    '''        | .lockscreen_background_opacity = $background_opacity
        | .lockscreen_show_logo = $visibility.logo
''',
    '''        | .lockscreen_background_opacity = $background_opacity
        | .lockscreen_entry_transition = $entry_transition
        | .lockscreen_show_logo = $visibility.logo
''',
)
replace_once(
    STATE,
    '''        .lockscreen_animation = "split"
        | .lockscreen_logo_physics_hz = 30
''',
    '''        .lockscreen_animation = "split"
        | .lockscreen_entry_transition = "fade"
        | .lockscreen_logo_physics_hz = 30
''',
)
replace_once(
    STATE,
    '''    set-lockscreen-animation)
        [[ -n ${2:-} ]] || exit 2
        set_lockscreen_animation "$2"
        ;;
    set-lockscreen-logo-physics-hz)
''',
    '''    set-lockscreen-animation)
        [[ -n ${2:-} ]] || exit 2
        set_lockscreen_animation "$2"
        ;;
    set-lockscreen-entry-transition)
        [[ -n ${2:-} ]] || exit 2
        set_lockscreen_entry_transition "$2"
        ;;
    set-lockscreen-logo-physics-hz)
''',
)
replace_once(STATE, "            6|12|13|14|16) ;;\n", "            6|12|13|14|16|17) ;;\n")

# Desktop state reader.
replace_once(
    BAR_STATE,
    '''    readonly property var lockscreenAnimationPresets: [
        { key: "random", label: "Random" },
        { key: "swarm", label: "Swarm" },
        { key: "edges", label: "Edges" },
        { key: "center", label: "Center" },
        { key: "split", label: "Split" },
        { key: "off", label: "Off" }
    ]
''',
    '''    readonly property var lockscreenAnimationPresets: [
        { key: "random", label: "Random" },
        { key: "swarm", label: "Swarm" },
        { key: "edges", label: "Edges" },
        { key: "center", label: "Center" },
        { key: "split", label: "Split" },
        { key: "off", label: "Off" }
    ]
    readonly property var lockscreenEntryTransitionPresets: [
        { key: "fade", label: "Fade" },
        { key: "pixel", label: "Pixel" },
        { key: "iris", label: "Reverse Iris" },
        { key: "edges", label: "Edges" },
        { key: "wipe", label: "Wipe" }
    ]
''',
)
replace_once(
    BAR_STATE,
    '''            lockscreen_animation: "split",
            lockscreen_logo_physics_hz: 30,
''',
    '''            lockscreen_animation: "split",
            lockscreen_entry_transition: "fade",
            lockscreen_logo_physics_hz: 30,
''',
)
replace_once(
    BAR_STATE,
    '''    function lockscreenBooleanPreference(field, fallback) {
''',
    '''    function lockscreenEntryTransition() {
        const value = String(data().lockscreen_entry_transition || "fade");
        for (const preset of lockscreenEntryTransitionPresets) {
            if (preset.key === value)
                return value;
        }
        return "fade";
    }

    function lockscreenBooleanPreference(field, fallback) {
''',
)

# Secure shell state loading/pass-through.
replace_once(
    SHELL,
    '''    property string lockAnimationPreference: "split"
    property int lockLogoPhysicsHz: 30
''',
    '''    property string lockAnimationPreference: "split"
    property string lockEntryTransition: "fade"
    property int lockLogoPhysicsHz: 30
''',
)
replace_once(
    SHELL,
    '''    function normalizedLogoPhysicsHz(value) {
''',
    '''    function normalizedEntryTransition(value) {
        const key = String(value || "");
        return ["fade", "pixel", "iris", "edges", "wipe"].indexOf(key) >= 0
            ? key : "fade";
    }

    function normalizedLogoPhysicsHz(value) {
''',
)
replace_once(
    SHELL,
    '''        lockAnimationPreference = "split";
        lockLogoPhysicsHz = 30;
''',
    '''        lockAnimationPreference = "split";
        lockEntryTransition = "fade";
        lockLogoPhysicsHz = 30;
''',
)
replace_once(
    SHELL,
    '''            lockAnimationPreference = normalizedAnimationPreference(parsed.lockscreen_animation);
            lockLogoPhysicsHz = normalizedLogoPhysicsHz(parsed.lockscreen_logo_physics_hz);
''',
    '''            lockAnimationPreference = normalizedAnimationPreference(parsed.lockscreen_animation);
            lockEntryTransition = normalizedEntryTransition(parsed.lockscreen_entry_transition);
            lockLogoPhysicsHz = normalizedLogoPhysicsHz(parsed.lockscreen_logo_physics_hz);
''',
)
replace_once(
    SHELL,
    '''                animationPreference: root.lockAnimationPreference
                randomFormationMode: root.randomFormationMode
''',
    '''                animationPreference: root.lockAnimationPreference
                entryTransition: root.lockEntryTransition
                randomFormationMode: root.randomFormationMode
''',
)

# Secure surface: pass state to scene and keep the real input active while presentation waits for reveal.
replace_once(
    SURFACE,
    '''    required property string animationPreference
    required property int randomFormationMode
''',
    '''    required property string animationPreference
    required property string entryTransition
    required property int randomFormationMode
''',
)
replace_once(
    SURFACE,
    '''        animationPreference: root.animationPreference
        randomFormationMode: root.randomFormationMode
''',
    '''        animationPreference: root.animationPreference
        entryTransition: root.entryTransition
        randomFormationMode: root.randomFormationMode
''',
)
replace_once(
    SURFACE,
    '''        opacity: (root.unlocking ? 0 : root.entered ? 1 : 0)
            * scene.elementOpacity("password")
''',
    '''        opacity: scene.securePasswordEntryOpacity
            * scene.elementOpacity("password")
''',
)

# Shared secure/editor scene.
replace_once(
    SCENE,
    '''    required property string animationPreference
    required property int randomFormationMode
''',
    '''    required property string animationPreference
    required property string entryTransition
    required property int randomFormationMode
''',
)
replace_once(
    SCENE,
    '''    property bool unlocking: false
    property bool entered: false

    readonly property real uiScale:''',
    '''    property bool unlocking: false
    property bool entered: false
    property int entryTransitionReplayToken: 0
    property real entryTransitionProgress: 0
    property bool entryTransitionRunning: false

    readonly property int entryTileColumns: 24
    readonly property int entryTileRows: 14
    readonly property real securePasswordEntryOpacity: root.unlocking ? 0
        : !root.entered ? 0
        : root.entryTransitionMode() === "fade" ? root.entryTransitionProgress
        : root.entryTransitionRunning ? 0 : 1

    readonly property real uiScale:''',
)
replace_once(
    SCENE,
    '''    function wallpaperGeometry() {
''',
    '''    function entryTransitionMode() {
        const key = String(root.entryTransition || "fade");
        return ["fade", "pixel", "iris", "edges", "wipe"].indexOf(key) >= 0
            ? key : "fade";
    }

    function entryTransitionDuration() {
        const mode = entryTransitionMode();
        if (mode === "pixel" || mode === "iris") return 560;
        if (mode === "edges") return 460;
        if (mode === "wipe") return 380;
        return 220;
    }

    function replayEntryTransition() {
        entryTransitionAnimation.stop();
        entryTransitionProgress = 0;
        entryTransitionRunning = true;
        if (!entered || unlocking)
            return;
        entryTransitionAnimation.restart();
    }

    onEntryTransitionReplayTokenChanged: {
        if (entered && !unlocking)
            replayEntryTransition();
    }

    function wallpaperGeometry() {
''',
)
replace_once(
    SCENE,
    '''        opacity: root.unlocking ? 0 : root.entered ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: root.unlocking ? 160 : 220
''',
    '''        opacity: root.unlocking ? 0
            : root.entryTransitionMode() === "fade" ? root.entryTransitionProgress
            : root.entered ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: root.unlocking ? 160 : 80
''',
)
entry_cover = r'''

    Item {
        id: entryTransitionCover
        anchors.fill: parent
        z: 500
        visible: !root.unlocking && root.entryTransitionRunning
            && root.entryTransitionMode() !== "fade"

        Repeater {
            model: entryTransitionCover.visible
                && (root.entryTransitionMode() === "pixel"
                    || root.entryTransitionMode() === "iris")
                ? root.entryTileColumns * root.entryTileRows : 0

            Rectangle {
                readonly property int tileColumn: index % root.entryTileColumns
                readonly property int tileRow: Math.floor(index / root.entryTileColumns)
                readonly property real centerX: (tileColumn + 0.5) / root.entryTileColumns
                readonly property real centerY: (tileRow + 0.5) / root.entryTileRows
                readonly property real distanceFromCenter: Math.min(1,
                    Math.sqrt(Math.pow((centerX - 0.5) * 2, 2)
                        + Math.pow((centerY - 0.5) * 2, 2)) / Math.sqrt(2))
                readonly property real pixelThreshold: 0.08
                    + (((index * 73 + 19) % 337) / 336) * 0.84
                readonly property real irisThreshold: 0.10
                    + (1 - distanceFromCenter) * 0.82

                x: tileColumn * entryTransitionCover.width / root.entryTileColumns
                y: tileRow * entryTransitionCover.height / root.entryTileRows
                width: Math.ceil(entryTransitionCover.width / root.entryTileColumns) + 1
                height: Math.ceil(entryTransitionCover.height / root.entryTileRows) + 1
                color: "#000000"
                visible: root.entryTransitionMode() === "pixel"
                    ? root.entryTransitionProgress < pixelThreshold
                    : root.entryTransitionProgress < irisThreshold
            }
        }

        Rectangle {
            visible: root.entryTransitionMode() === "edges"
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: parent.height * 0.5 * (1 - root.entryTransitionProgress)
            color: "#000000"
        }
        Rectangle {
            visible: root.entryTransitionMode() === "edges"
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: parent.height * 0.5 * (1 - root.entryTransitionProgress)
            color: "#000000"
        }
        Rectangle {
            visible: root.entryTransitionMode() === "edges"
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width * 0.5 * (1 - root.entryTransitionProgress)
            color: "#000000"
        }
        Rectangle {
            visible: root.entryTransitionMode() === "edges"
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width * 0.5 * (1 - root.entryTransitionProgress)
            color: "#000000"
        }

        Rectangle {
            visible: root.entryTransitionMode() === "wipe"
            x: parent.width * root.entryTransitionProgress
            y: 0
            width: Math.max(0, parent.width * (1 - root.entryTransitionProgress))
            height: parent.height
            color: "#000000"
        }
        Rectangle {
            visible: root.entryTransitionMode() === "wipe"
                && root.entryTransitionProgress > 0
                && root.entryTransitionProgress < 1
            x: Math.max(0, parent.width * root.entryTransitionProgress - width)
            y: 0
            width: Math.max(2, Math.round(6 * root.uiScale))
            height: parent.height
            color: root.theme.lockAccent
            opacity: 0.65
        }
    }

    NumberAnimation {
        id: entryTransitionAnimation
        target: root
        property: "entryTransitionProgress"
        from: 0
        to: 1
        duration: root.entryTransitionDuration()
        easing.type: Easing.OutCubic
        onFinished: {
            root.entryTransitionProgress = 1;
            root.entryTransitionRunning = false;
        }
    }
'''
replace_once(
    SCENE,
    '''    Timer {
        id: cursorFadeDelay
''',
    entry_cover + '''
    Timer {
        id: cursorFadeDelay
''',
)
replace_once(
    SCENE,
    '''    Component.onCompleted: {
        root.updateClockText();
        root.entered = true;
    }
}''',
    '''    Component.onCompleted: {
        root.updateClockText();
        root.entered = true;
        Qt.callLater(() => root.replayEntryTransition());
    }
}''',
)
# Keep the preview scene byte-identical by construction.
(ROOT / PREVIEW).write_text((ROOT / SCENE).read_text(encoding="utf-8"), encoding="utf-8")

# Editor state, history, replay and controls.
replace_once(
    EDITOR,
    '''    property var draftVisualizer: defaultVisualizer()
    property int draftBackgroundOpacity: 100
''',
    '''    property var draftVisualizer: defaultVisualizer()
    property int draftBackgroundOpacity: 100
    property string draftEntryTransition: "fade"
    property int entryTransitionReplayToken: 0
''',
)
replace_once(
    EDITOR,
    '''            backgroundOpacity: draftBackgroundOpacity,
            wallpaperPath: draftWallpaperPath,
''',
    '''            backgroundOpacity: draftBackgroundOpacity,
            entryTransition: draftEntryTransition,
            wallpaperPath: draftWallpaperPath,
''',
)
replace_once(
    EDITOR,
    '''        draftBackgroundOpacity = Number.isFinite(backgroundOpacity)
            ? Math.max(0, Math.min(100, Math.round(backgroundOpacity))) : 100;
        draftWallpaperPath = typeof snapshot.wallpaperPath === "string"
''',
    '''        draftBackgroundOpacity = Number.isFinite(backgroundOpacity)
            ? Math.max(0, Math.min(100, Math.round(backgroundOpacity))) : 100;
        const entryTransition = String(snapshot.entryTransition || "fade");
        draftEntryTransition = ["fade", "pixel", "iris", "edges", "wipe"].indexOf(entryTransition) >= 0
            ? entryTransition : "fade";
        draftWallpaperPath = typeof snapshot.wallpaperPath === "string"
''',
)
replace_once(
    EDITOR,
    '''    function resetDraft() {
''',
    '''    function setDraftEntryTransition(value) {
        const key = String(value || "");
        if (["fade", "pixel", "iris", "edges", "wipe"].indexOf(key) < 0)
            return;
        if (draftEntryTransition === key) {
            replayEntryTransition();
            return;
        }
        recordUndoBeforeChange();
        draftEntryTransition = key;
        replayEntryTransition();
    }

    function replayEntryTransition() {
        entryTransitionReplayToken = entryTransitionReplayToken >= 2147483646
            ? 1 : entryTransitionReplayToken + 1;
        statusMessage = "Replaying " + draftEntryTransition + " transition";
    }

    function resetDraft() {
''',
)
replace_once(
    EDITOR,
    '''        draftVisualizer = defaultVisualizer();
        draftBackgroundOpacity = 100;
        draftVisibility = defaultVisibility();
''',
    '''        draftVisualizer = defaultVisualizer();
        draftBackgroundOpacity = 100;
        draftEntryTransition = "fade";
        draftVisibility = defaultVisibility();
''',
)
replace_once(
    EDITOR,
    '''        draftVisualizer = cloneVisualizer(BarState.lockscreenVisualizer());
        draftBackgroundOpacity = BarState.lockscreenBackgroundOpacity();
        draftVisibility = cloneVisibility(({
''',
    '''        draftVisualizer = cloneVisualizer(BarState.lockscreenVisualizer());
        draftBackgroundOpacity = BarState.lockscreenBackgroundOpacity();
        draftEntryTransition = BarState.lockscreenEntryTransition();
        draftVisibility = cloneVisibility(({
''',
)
replace_once(
    EDITOR,
    '''            JSON.stringify(draftVisualizer),
            String(draftBackgroundOpacity)
        ]);
''',
    '''            JSON.stringify(draftVisualizer),
            String(draftBackgroundOpacity),
            String(draftEntryTransition)
        ]);
''',
)
replace_once(
    EDITOR,
    '''                animationPreference: BarState.lockscreenAnimationPreference()
                randomFormationMode: 3
''',
    '''                animationPreference: BarState.lockscreenAnimationPreference()
                entryTransition: root.draftEntryTransition
                entryTransitionReplayToken: root.entryTransitionReplayToken
                randomFormationMode: 3
''',
)
transition_editor_ui = '''

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 7
                        visible: root.activeDrawer === "background"

                        Text { text: "Entry Transition"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 9 }
                        SettingsButton { label: "Fade"; active: root.draftEntryTransition === "fade"; textSize: 9; onClicked: root.setDraftEntryTransition("fade") }
                        SettingsButton { label: "Pixel"; active: root.draftEntryTransition === "pixel"; textSize: 9; onClicked: root.setDraftEntryTransition("pixel") }
                        SettingsButton { label: "Reverse Iris"; active: root.draftEntryTransition === "iris"; textSize: 9; onClicked: root.setDraftEntryTransition("iris") }
                        SettingsButton { label: "Edges"; active: root.draftEntryTransition === "edges"; textSize: 9; onClicked: root.setDraftEntryTransition("edges") }
                        SettingsButton { label: "Wipe"; active: root.draftEntryTransition === "wipe"; textSize: 9; onClicked: root.setDraftEntryTransition("wipe") }
                        SettingsButton { label: "Replay Transition"; textSize: 9; onClicked: root.replayEntryTransition() }
                        Item { Layout.fillWidth: true }
                    }
'''
replace_once(
    EDITOR,
    '''                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 7
                        visible: root.activeDrawer === "weather"

                        Text { text: "Weather units";''',
    transition_editor_ui + '''
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 7
                        visible: root.activeDrawer === "weather"

                        Text { text: "Weather units";''',
)

# Quick Settings: explicit options as requested by the maintainer.
quick_transition_ui = '''
                                        Text { Layout.fillWidth: true; text: "Entry Transition"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: root.scaledText(9) }
                                        Flow {
                                            Layout.fillWidth: true
                                            spacing: 5
                                            SettingsButton { label: "Fade"; active: BarState.lockscreenEntryTransition() === "fade"; textSize: root.scaledText(9); onClicked: root.queueStateCommand(["set-lockscreen-entry-transition", "fade"]) }
                                            SettingsButton { label: "Pixel"; active: BarState.lockscreenEntryTransition() === "pixel"; textSize: root.scaledText(9); onClicked: root.queueStateCommand(["set-lockscreen-entry-transition", "pixel"]) }
                                            SettingsButton { label: "Reverse Iris"; active: BarState.lockscreenEntryTransition() === "iris"; textSize: root.scaledText(9); onClicked: root.queueStateCommand(["set-lockscreen-entry-transition", "iris"]) }
                                            SettingsButton { label: "Edges"; active: BarState.lockscreenEntryTransition() === "edges"; textSize: root.scaledText(9); onClicked: root.queueStateCommand(["set-lockscreen-entry-transition", "edges"]) }
                                            SettingsButton { label: "Wipe"; active: BarState.lockscreenEntryTransition() === "wipe"; textSize: root.scaledText(9); onClicked: root.queueStateCommand(["set-lockscreen-entry-transition", "wipe"]) }
                                        }
'''
replace_once(
    QUICK,
    '''                                        Text { Layout.fillWidth: true; text: "Visualizer"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: root.scaledText(9) }
''',
    quick_transition_ui + '''                                        Text { Layout.fillWidth: true; text: "Visualizer"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: root.scaledText(9) }
''',
)

print("lockscreen entry transition patch applied")
