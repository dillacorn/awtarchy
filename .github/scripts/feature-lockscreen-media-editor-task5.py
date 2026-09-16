#!/usr/bin/env python3
from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    if text.count(old) != 1:
        raise SystemExit(f"missing/ambiguous patch target: {label}")
    return text.replace(old, new, 1)


scene_path = Path("config/quickshell/awtarchy-lock/LockScene.qml")
scene = scene_path.read_text()
scene = replace_once(
    scene,
    '''    property bool externalEntryTransitionRunning: false
    property int presentationReplayToken: 0
''',
    '''    property bool externalEntryTransitionRunning: false
    property bool externalEntryTransitionPending: false
    property int presentationReplayToken: 0
''',
    "pending transition input",
)
scene = replace_once(
    scene,
    '''    readonly property bool effectiveEntryTransitionRunning: externalEntryTransitionRunning
    readonly property bool customImageEntryStarted:
''',
    '''    readonly property bool effectiveEntryTransitionRunning:
        externalEntryTransitionRunning || externalEntryTransitionPending
    readonly property bool backgroundMediaNeedsPreroll:
        root.backgroundMode === "wallpaper" && wallpaperMedia.mediaKind === "video"
    readonly property bool backgroundMediaPlaybackAdvanced:
        !root.backgroundMediaNeedsPreroll || wallpaperMedia.playbackAdvanced
    readonly property bool customImageEntryStarted:
''',
    "pending/media presentation state",
)
scene_path.write_text(scene)
Path("config/quickshell/awtarchy/LockPreviewScene.qml").write_text(scene)

surface_path = Path("config/quickshell/awtarchy-lock/LockSurface.qml")
surface = surface_path.read_text()
surface = replace_once(
    surface,
    '    readonly property bool transitionComplete: !transitionLayer.running\n',
    '    readonly property bool transitionComplete: root.transitionStarted && !transitionLayer.running\n',
    "deferred transition completion",
)
surface = replace_once(
    surface,
    '''    property bool entered: false
    property int submittedMaskCount: 0
''',
    '''    property bool entered: false
    property bool transitionStarted: false
    property bool preRollSchedulingReady: false
    property int submittedMaskCount: 0
''',
    "pre-roll lifecycle state",
)
surface = replace_once(
    surface,
    '''    function focusPasswordWhenReady() {
        if (root.unlocking)
            return;
        Qt.callLater(() => {
            if (!root.unlocking)
                password.forceActiveFocus();
        });
    }
''',
    '''    function focusPasswordWhenReady() {
        if (root.unlocking)
            return;
        Qt.callLater(() => {
            if (!root.unlocking)
                password.forceActiveFocus();
        });
    }

    function startEntryTransition() {
        if (!root.preRollSchedulingReady || root.transitionStarted || root.unlocking)
            return;
        videoPreRollTimeout.stop();
        // Keep the pending scene gate asserted until the transition reports
        // running, then release the frozen pre-roll cover.
        transitionLayer.restart();
        root.transitionStarted = true;
    }

    function scheduleEntryTransition() {
        if (!root.preRollSchedulingReady || root.transitionStarted || root.unlocking)
            return;
        if (!scene.backgroundMediaNeedsPreroll || scene.backgroundMediaPlaybackAdvanced) {
            root.startEntryTransition();
            return;
        }
        if (!videoPreRollTimeout.running)
            videoPreRollTimeout.restart();
    }
''',
    "pre-roll transition functions",
)
surface = replace_once(
    surface,
    '''            previewMode: false
            externalEntryTransitionRunning: transitionLayer.running
        }
''',
    '''            previewMode: false
            externalEntryTransitionRunning: transitionLayer.running
            externalEntryTransitionPending: !root.transitionStarted
        }
''',
    "scene pending transition wiring",
)
surface = replace_once(
    surface,
    '''    // Double the active interaction cadence without adding any idle polling.
''',
    '''    // While a video destination decodes its first frames, keep the secure
    // captured desktop visible. The live destination continues rendering below.
    ShaderEffectSource {
        id: preRollCover
        anchors.fill: parent
        z: 999
        sourceItem: transitionBacking
        live: true
        recursive: false
        smooth: true
        visible: !root.transitionStarted
    }

    Timer {
        id: videoPreRollTimeout
        interval: 750
        repeat: false
        onTriggered: root.startEntryTransition()
    }

    // Double the active interaction cadence without adding any idle polling.
''',
    "pre-roll cover and timeout",
)
surface = replace_once(
    surface,
    '''        function onLogoExplosionActiveChanged() {
            if (!scene.logoExplosionActive && Object.keys(scene.logoParticles).length > 0) {
                scene.logoReturnPending = true;
                scene.logoHoverDirty = true;
            }
        }
''',
    '''        function onLogoExplosionActiveChanged() {
            if (!scene.logoExplosionActive && Object.keys(scene.logoParticles).length > 0) {
                scene.logoReturnPending = true;
                scene.logoHoverDirty = true;
            }
        }

        function onBackgroundMediaNeedsPrerollChanged() {
            root.scheduleEntryTransition();
        }

        function onBackgroundMediaPlaybackAdvancedChanged() {
            root.scheduleEntryTransition();
        }
''',
    "media readiness connections",
)
surface = replace_once(
    surface,
    '''        duration: root.entryTransitionDuration
        replayToken: 0
''',
    '''        duration: root.entryTransitionDuration
        replayToken: 0
        autoStart: false
''',
    "deferred transition auto-start",
)
surface = replace_once(
    surface,
    '''    Component.onCompleted: {
        root.entered = true;
        root.focusPasswordWhenReady();
    }
''',
    '''    Component.onCompleted: {
        root.entered = true;
        root.preRollSchedulingReady = true;
        root.scheduleEntryTransition();
        root.focusPasswordWhenReady();
    }
''',
    "initial pre-roll scheduling",
)
surface_path.write_text(surface)

regression_path = Path("tests/test-quickshell-lockscreen-runtime-regressions.sh")
regression = regression_path.read_text()
regression = replace_once(
    regression,
    '''require_text "$SCENE_QML" 'readonly property bool effectiveEntryTransitionRunning: externalEntryTransitionRunning' \\
    'shared presentation content is not gated by the external transition layer'
''',
    '''require_text "$SCENE_QML" 'externalEntryTransitionRunning || externalEntryTransitionPending' \\
    'shared presentation content is not gated by active or pending external transition state'
''',
    "runtime transition gate expectation",
)
regression_path.write_text(regression)
