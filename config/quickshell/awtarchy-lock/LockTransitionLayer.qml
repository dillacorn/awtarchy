import QtQuick
import QtQuick.Effects

Item {
    id: root

    property Item startSource: null
    property Item endSource: null
    property string mode: "fade"
    property int duration: 1800
    property int replayToken: 0

    property real transitionProgress: 0
    property bool transitionActive: true

    readonly property real progress: transitionProgress
    readonly property bool running: transitionActive
    readonly property string normalizedMode: {
        const value = String(root.mode || "fade");
        return ["fade", "pixel", "iris", "edges", "wipe"].indexOf(value) >= 0
            ? value : "fade";
    }
    readonly property int effectiveDuration: {
        const value = Math.round(Number(root.duration));
        return Number.isFinite(value)
            ? Math.max(800, Math.min(6000, value)) : 1800;
    }
    readonly property real collapseAmount: root.progress < 0.5
        ? root.progress / 0.5 : (1.0 - root.progress) / 0.5
    readonly property real sourceBlend: Math.max(0,
        Math.min(1, (root.progress - 0.45) / 0.10))
    readonly property real coarseFactor: 1
        + 47 * Math.pow(Math.max(0, root.collapseAmount), 1.35)
    readonly property size reducedTextureSize: Qt.size(
        Math.max(1, Math.round(root.width / root.coarseFactor)),
        Math.max(1, Math.round(root.height / root.coarseFactor)))
    readonly property real irisDiameter: Math.sqrt(
        root.width * root.width + root.height * root.height)
        * Math.max(0, Math.min(1, root.progress)) * 1.02

    signal finished()

    visible: root.running
    clip: true

    function restart() {
        transitionAnimation.stop();
        transitionProgress = 0;
        transitionActive = true;
        Qt.callLater(() => transitionAnimation.restart());
    }

    onReplayTokenChanged: restart()

    // Resolution Collapse / Pixelate. Both the frozen desktop and real
    // lockscreen destination are downsampled at the midpoint, so the handoff
    // happens while both frames are maximally blocky instead of through black.
    ShaderEffectSource {
        id: pixelEndSource
        anchors.fill: parent
        z: 1
        sourceItem: root.endSource
        live: true
        recursive: false
        smooth: false
        textureSize: root.reducedTextureSize
        visible: root.running && root.normalizedMode === "pixel"
        opacity: root.sourceBlend
    }

    ShaderEffectSource {
        id: pixelStartSource
        anchors.fill: parent
        z: 2
        sourceItem: root.startSource
        live: true
        recursive: false
        smooth: false
        textureSize: root.reducedTextureSize
        visible: root.running && root.normalizedMode === "pixel"
        opacity: 1 - root.sourceBlend
    }

    // Fade keeps the frozen desktop above the real secure destination and
    // simply removes it. There is no decorative black transition cover.
    ShaderEffectSource {
        id: fadeStartSource
        anchors.fill: parent
        z: 2
        sourceItem: root.startSource
        live: true
        recursive: false
        smooth: true
        visible: root.running && root.normalizedMode === "fade"
        opacity: 1 - root.progress
    }

    // Wipe reveals the destination from left to right while keeping the
    // desktop pixels spatially stable inside the shrinking clip.
    Item {
        id: wipeClip
        z: 2
        x: root.width * root.progress
        y: 0
        width: Math.max(0, root.width * (1 - root.progress))
        height: root.height
        clip: true
        visible: root.running && root.normalizedMode === "wipe"

        ShaderEffectSource {
            x: -wipeClip.x
            y: 0
            width: root.width
            height: root.height
            sourceItem: root.startSource
            live: true
            recursive: false
            smooth: true
        }
    }

    // Edges reveals the lockscreen from the left/right edges only.
    Item {
        id: edgesClip
        z: 2
        width: Math.max(0, root.width * (1 - root.progress))
        height: root.height
        x: (root.width - width) / 2
        y: 0
        clip: true
        visible: root.running && root.normalizedMode === "edges"

        ShaderEffectSource {
            x: -edgesClip.x
            y: 0
            width: root.width
            height: root.height
            sourceItem: root.startSource
            live: true
            recursive: false
            smooth: true
        }
    }

    // Reverse Iris keeps the frozen desktop as the base and directly
    // reveals the real lockscreen destination through an expanding mask.
    ShaderEffectSource {
        id: irisStartSource
        anchors.fill: parent
        z: 2
        sourceItem: root.startSource
        live: true
        recursive: false
        smooth: true
        visible: root.running && root.normalizedMode === "iris"
    }

    Item {
        id: irisMaskShape
        anchors.fill: parent
        visible: false
        layer.enabled: true
        layer.smooth: true
        Rectangle {
            anchors.centerIn: parent
            width: root.irisDiameter
            height: width
            radius: width / 2
            color: "#ffffff"
        }
    }

    MultiEffect {
        id: irisEndEffect
        anchors.fill: parent
        z: 3
        source: root.endSource
        autoPaddingEnabled: false
        maskEnabled: true
        maskInverted: false
        maskSource: irisMaskShape
        maskSpreadAtMin: 0.015
        maskSpreadAtMax: 0.015
        visible: root.running && root.normalizedMode === "iris"
    }

    NumberAnimation {
        id: transitionAnimation
        target: root
        property: "transitionProgress"
        from: 0
        to: 1
        duration: root.effectiveDuration
        easing.type: Easing.InOutCubic
        onFinished: {
            root.transitionProgress = 1;
            root.transitionActive = false;
            root.finished();
        }
    }

    Component.onCompleted: root.restart()
}
