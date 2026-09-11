#!/usr/bin/env python3
from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one anchor, found {count}")
    return text.replace(old, new, 1)


def replace_span(text: str, start: str, end: str, replacement: str, label: str) -> str:
    start_index = text.find(start)
    if start_index < 0:
        raise SystemExit(f"{label}: start anchor missing")
    end_index = text.find(end, start_index)
    if end_index < 0:
        raise SystemExit(f"{label}: end anchor missing")
    if text.find(start, start_index + 1) >= 0:
        raise SystemExit(f"{label}: start anchor is not unique")
    return text[:start_index] + replacement + text[end_index:]


# CAVA remains one bounded PipeWire/output-only source; displayed band count is
# resampled in QML so changing the editor setting never restarts CAVA.
cava_path = Path("config/quickshell/awtarchy-lock/cava.conf")
cava = cava_path.read_text()
cava = replace_once(cava, "bars = 8\n", "bars = 64\n", "CAVA band count")
cava_path.write_text(cava)


analyzer = r'''import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    visible: false
    width: 0
    height: 0

    property var bands: []
    property var targetBands: []

    readonly property int maximumBands: 64
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME")
        || (Quickshell.env("HOME") + "/.config")
    readonly property string helper: root.configHome
        + "/hypr/scripts/quickshell_lockscreen_audio.sh"
    readonly property real silenceThreshold: 0.018

    function clampUnit(value) {
        const numeric = Number(value);
        if (!Number.isFinite(numeric))
            return 0;
        return Math.max(0, Math.min(1, numeric));
    }

    function threshold(value) {
        const bounded = clampUnit(value);
        return bounded < silenceThreshold ? 0 : bounded;
    }

    function zeroSpectrum() {
        const values = [];
        for (let i = 0; i < maximumBands; ++i)
            values.push(0);
        return values;
    }

    function normalizedSpectrum(values) {
        const result = [];
        for (let i = 0; i < maximumBands; ++i) {
            const value = i < values.length ? values[i] : 0;
            result.push(threshold(value));
        }
        return result;
    }

    function parseFrame(data) {
        const fields = String(data || "").trim().split(";");
        const values = [];
        for (let i = 0; i < fields.length && values.length < maximumBands; ++i) {
            if (fields[i].length === 0)
                continue;
            values.push(clampUnit(Number(fields[i]) / 1000));
        }
        if (values.length === 0)
            return;
        targetBands = normalizedSpectrum(values);
        ensureSmoothing();
    }

    function smoothed(current, target) {
        const factor = target > current ? 0.42 : 0.16;
        const next = current + (target - current) * factor;
        return Math.abs(next - target) < 0.001 ? target : next;
    }

    function ensureSmoothing() {
        if (!smoothingTimer.running)
            smoothingTimer.start();
    }

    function clearTargets() {
        targetBands = zeroSpectrum();
    }

    function startAnalyzer() {
        if (root.enabled && !audioProcess.running)
            audioProcess.running = true;
    }

    function settled() {
        if (bands.length !== targetBands.length)
            return false;
        for (let i = 0; i < targetBands.length; ++i) {
            if (Math.abs(Number(bands[i] || 0) - Number(targetBands[i] || 0)) >= 0.001)
                return false;
        }
        return true;
    }

    onEnabledChanged: {
        if (enabled) {
            startAnalyzer();
        } else {
            if (audioProcess.running)
                audioProcess.running = false;
            clearTargets();
            ensureSmoothing();
        }
    }

    Component.onCompleted: {
        bands = zeroSpectrum();
        targetBands = zeroSpectrum();
        root.startAnalyzer();
    }

    Process {
        id: audioProcess
        command: [root.helper]
        stdout: SplitParser {
            onRead: data => root.parseFrame(data)
        }
        onExited: {
            root.clearTargets();
            root.ensureSmoothing();
        }
    }

    Timer {
        id: smoothingTimer
        interval: 33
        repeat: true
        running: false
        onTriggered: {
            const next = [];
            for (let i = 0; i < root.maximumBands; ++i) {
                const current = i < root.bands.length ? Number(root.bands[i]) : 0;
                const target = i < root.targetBands.length ? Number(root.targetBands[i]) : 0;
                next.push(root.smoothed(current, target));
            }
            root.bands = next;
            if (root.settled())
                stop();
        }
    }
}
'''
Path("config/quickshell/awtarchy-lock/LockAudioAnalyzer.qml").write_text(analyzer)
Path("config/quickshell/awtarchy/LockPreviewAudioAnalyzer.qml").write_text(analyzer)


shell_path = Path("config/quickshell/awtarchy-lock/shell.qml")
shell = shell_path.read_text()
shell = replace_once(
    shell,
    "    property var lockLayout: defaultLockLayout()\n    property var lockCustomImages: []\n",
    "    property var lockLayout: defaultLockLayout()\n"
    "    property var lockCustomImages: []\n"
    "    property var lockVisualizer: defaultLockVisualizer()\n"
    "    property int lockBackgroundOpacity: 100\n",
    "secure Pass 3 properties",
)

visualizer_helpers = r'''    function defaultLockVisualizer() {
        return ({
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
        });
    }

    function normalizedVisualizer(value) {
        const defaults = defaultLockVisualizer();
        if (!value || typeof value !== "object" || Array.isArray(value))
            return defaults;
        const enabled = typeof value.enabled === "boolean" ? value.enabled : defaults.enabled;
        const x = Number(value.x === undefined ? defaults.x : value.x);
        const y = Number(value.y === undefined ? defaults.y : value.y);
        const scale = Number(value.scale === undefined ? defaults.scale : value.scale);
        const stretchX = Number(value.stretch_x === undefined ? defaults.stretch_x : value.stretch_x);
        const stretchY = Number(value.stretch_y === undefined ? defaults.stretch_y : value.stretch_y);
        const opacity = Number(value.opacity === undefined ? defaults.opacity : value.opacity);
        const color = String(value.color === undefined ? defaults.color : value.color).toLowerCase();
        const bands = Number(value.bands === undefined ? defaults.bands : value.bands);
        const gap = Number(value.gap === undefined ? defaults.gap : value.gap);
        const responseHeight = Number(value.height === undefined ? defaults.height : value.height);
        const sensitivity = Number(value.sensitivity === undefined ? defaults.sensitivity : value.sensitivity);
        const shape = String(value.shape === undefined ? defaults.shape : value.shape);
        const bend = Number(value.bend === undefined ? defaults.bend : value.bend);
        if (!Number.isFinite(x) || x < 0.05 || x > 0.95
                || !Number.isFinite(y) || y < 0.08 || y > 0.92
                || !Number.isFinite(scale) || scale < 0.50 || scale > 2.00
                || !Number.isFinite(stretchX) || stretchX < 0.25 || stretchX > 4.00
                || !Number.isFinite(stretchY) || stretchY < 0.25 || stretchY > 4.00
                || !Number.isFinite(opacity) || opacity < 0 || opacity > 100
                || (color !== "auto" && !/^#[0-9a-f]{6}$/.test(color))
                || !Number.isInteger(bands) || bands < 4 || bands > 64
                || !Number.isInteger(gap) || gap < 0 || gap > 24
                || !Number.isInteger(responseHeight) || responseHeight < 25 || responseHeight > 300
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
            opacity: opacity,
            color: color,
            bands: bands,
            gap: gap,
            height: responseHeight,
            sensitivity: sensitivity,
            shape: shape,
            bend: bend
        });
    }

    function normalizedBackgroundOpacity(value) {
        const numeric = Number(value);
        if (!Number.isFinite(numeric) || !Number.isInteger(numeric)
                || numeric < 0 || numeric > 100)
            return 100;
        return numeric;
    }

'''
shell = replace_once(
    shell,
    "    function defaultLockLayout() {\n",
    visualizer_helpers + "    function defaultLockLayout() {\n",
    "secure visualizer normalizers",
)
shell = replace_once(
    shell,
    "        lockLayout = defaultLockLayout();\n        lockCustomImages = [];\n",
    "        lockLayout = defaultLockLayout();\n"
    "        lockCustomImages = [];\n"
    "        lockVisualizer = defaultLockVisualizer();\n"
    "        lockBackgroundOpacity = 100;\n",
    "secure reset Pass 3",
)
shell = replace_once(
    shell,
    "            lockLayout = normalizedLayout(parsed.lockscreen_layout);\n"
    "            lockCustomImages = normalizedCustomImages(parsed.lockscreen_custom_images);\n",
    "            lockLayout = normalizedLayout(parsed.lockscreen_layout);\n"
    "            lockCustomImages = normalizedCustomImages(parsed.lockscreen_custom_images);\n"
    "            lockVisualizer = normalizedVisualizer(parsed.lockscreen_visualizer);\n"
    "            lockBackgroundOpacity = normalizedBackgroundOpacity(parsed.lockscreen_background_opacity);\n",
    "secure load Pass 3",
)
shell = replace_once(
    shell,
    "    LockContrastCache {\n        id: lockContrastCache\n    }\n\n",
    "    LockContrastCache {\n"
    "        id: lockContrastCache\n"
    "    }\n\n"
    "    LockAudioAnalyzer {\n"
    "        id: lockAudioAnalyzer\n"
    "        enabled: root.lockVisualizer.enabled\n"
    "    }\n\n",
    "secure analyzer owner",
)
shell = replace_once(
    shell,
    "                layout: root.lockLayout\n                customImages: root.lockCustomImages\n",
    "                layout: root.lockLayout\n"
    "                customImages: root.lockCustomImages\n"
    "                visualizer: root.lockVisualizer\n"
    "                audioBands: lockAudioAnalyzer.bands\n"
    "                backgroundOpacity: root.lockBackgroundOpacity\n",
    "secure surface Pass 3 wiring",
)
shell_path.write_text(shell)


surface_path = Path("config/quickshell/awtarchy-lock/LockSurface.qml")
surface = surface_path.read_text()
surface = replace_once(
    surface,
    "    required property var layout\n    required property var customImages\n\n    color: \"#000000\"\n",
    "    required property var layout\n"
    "    required property var customImages\n"
    "    required property var visualizer\n"
    "    required property var audioBands\n"
    "    required property int backgroundOpacity\n\n"
    "    color: \"transparent\"\n",
    "secure surface Pass 3 properties",
)
surface = replace_once(
    surface,
    "        layout: root.layout\n        customImages: root.customImages\n        previewMode: false\n",
    "        layout: root.layout\n"
    "        customImages: root.customImages\n"
    "        visualizer: root.visualizer\n"
    "        audioBands: root.audioBands\n"
    "        backgroundOpacity: root.backgroundOpacity\n"
    "        previewMode: false\n",
    "surface scene Pass 3 wiring",
)
surface_path.write_text(surface)


scene_path = Path("config/quickshell/awtarchy-lock/LockScene.qml")
scene = scene_path.read_text()
scene = replace_once(
    scene,
    "    required property var layout\n    required property var customImages\n\n",
    "    required property var layout\n"
    "    required property var customImages\n"
    "    required property var visualizer\n"
    "    required property var audioBands\n"
    "    required property int backgroundOpacity\n\n",
    "scene Pass 3 properties",
)
scene = replace_once(
    scene,
    "    function presentationPoint(name) {\n        return normalizedPoint(name) || customImageForName(name);\n    }\n",
    "    function presentationPoint(name) {\n"
    "        if (name === \"visualizer\" && root.visualizer\n"
    "                && typeof root.visualizer === \"object\" && !Array.isArray(root.visualizer))\n"
    "            return root.visualizer;\n"
    "        return normalizedPoint(name) || customImageForName(name);\n"
    "    }\n",
    "visualizer generic point",
)
scene = replace_once(
    scene,
    "    function elementColor(name) {\n        const point = normalizedPoint(name);\n",
    "    function elementColor(name) {\n        const point = presentationPoint(name);\n",
    "generic element color",
)

visualizer_functions = r'''    function visualizerNumber(name, fallback, minimum, maximum) {
        const value = root.visualizer && typeof root.visualizer === "object"
            ? Number(root.visualizer[name]) : Number.NaN;
        return Number.isFinite(value)
            ? Math.max(minimum, Math.min(maximum, value)) : fallback;
    }

    function visualizerBandCount() {
        return Math.max(4, Math.min(64,
            Math.round(visualizerNumber("bands", 16, 4, 64))));
    }

    function visualizerGapPx() {
        return visualizerNumber("gap", 4, 0, 24) * 0.60 * root.uiScale;
    }

    function visualizerResponseHeight() {
        return 180 * root.uiScale
            * visualizerNumber("height", 100, 25, 300) / 100;
    }

    function visualizerShape() {
        const value = String(root.visualizer && root.visualizer.shape !== undefined
            ? root.visualizer.shape : "straight");
        return ["straight", "arc", "circle"].indexOf(value) >= 0
            ? value : "straight";
    }

    function visualizerBend() {
        return Math.round(visualizerNumber("bend", 45, -100, 100));
    }

    function visualizerBands() {
        const count = Math.min(64, root.visualizerBandCount());
        const source = Array.isArray(root.audioBands) ? root.audioBands : [];
        const result = [];
        const sensitivity = visualizerNumber("sensitivity", 100, 25, 300) / 100;
        for (let i = 0; i < count; ++i) {
            if (source.length === 0) {
                result.push(0);
                continue;
            }
            const start = Math.floor(i * source.length / count);
            const end = Math.max(start + 1,
                Math.floor((i + 1) * source.length / count));
            let total = 0;
            let used = 0;
            for (let j = start; j < Math.min(source.length, end); ++j) {
                const value = Number(source[j]);
                if (!Number.isFinite(value))
                    continue;
                total += Math.max(0, Math.min(1, value));
                used++;
            }
            const average = used > 0 ? total / used : 0;
            result.push(Math.max(0, Math.min(1, average * sensitivity)));
        }
        return result;
    }

    function visualizerBaseWidth() {
        if (visualizerShape() === "circle")
            return 380 * root.uiScale;
        return 520 * root.uiScale;
    }

    function visualizerBaseHeight() {
        if (visualizerShape() === "circle")
            return 380 * root.uiScale;
        return Math.max(120 * root.uiScale, visualizerResponseHeight() * 1.5);
    }

'''
scene = replace_once(
    scene,
    "    function presentationVisible(name, configuredVisible) {\n",
    visualizer_functions + "    function presentationVisible(name, configuredVisible) {\n",
    "visualizer scene helpers",
)
scene = replace_once(
    scene,
    "    function elementVisualWidth(name) {\n        if (customImageForName(name))\n",
    "    function elementVisualWidth(name) {\n"
    "        if (name === \"visualizer\")\n"
    "            return visualizerBaseWidth() * root.elementScale(name) * root.elementStretchX(name);\n"
    "        if (customImageForName(name))\n",
    "visualizer editor width",
)
scene = replace_once(
    scene,
    "    function elementVisualHeight(name) {\n        if (customImageForName(name))\n",
    "    function elementVisualHeight(name) {\n"
    "        if (name === \"visualizer\")\n"
    "            return visualizerBaseHeight() * root.elementScale(name) * root.elementStretchY(name);\n"
    "        if (customImageForName(name))\n",
    "visualizer editor height",
)

background_start = '''    Rectangle {
        anchors.fill: parent
        color: root.backgroundMode === "color" ? root.backgroundColor : "#000000"
    }
'''
visual_layer_marker = '''    Item {
        id: visualLayer
'''
background_layer = r'''    Item {
        id: backgroundLayer
        anchors.fill: parent
        opacity: Math.max(0, Math.min(100, root.backgroundOpacity)) / 100

        Rectangle {
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
    }

'''
scene = replace_span(
    scene,
    background_start,
    visual_layer_marker,
    background_layer,
    "isolated background layer",
)

visualizer_item = r'''        Item {
            id: visualizerItem
            readonly property bool configuredEnabled: root.visualizer
                && root.visualizer.enabled === true
            readonly property int bandCount: Math.min(64, root.visualizerBandCount())
            readonly property var displayBands: root.visualizerBands()
            readonly property real gapPx: root.visualizerGapPx()
            readonly property string shapeMode: root.visualizerShape()
            readonly property real responseHeight: root.visualizerResponseHeight()
            readonly property real bendAmount: root.visualizerBend()

            visible: configuredEnabled || root.editorMode
            opacity: root.elementOpacity("visualizer")
                * (configuredEnabled ? 1.0 : root.editorMode ? 0.30 : 0.0)
            width: root.visualizerBaseWidth()
            height: root.visualizerBaseHeight()
            x: root.normalizedX("visualizer", 0.50) * parent.width - width / 2
            y: root.normalizedY("visualizer", 0.80) * parent.height - height / 2
            scale: root.elementScale("visualizer")
            transformOrigin: Item.Center
            transform: Scale {
                origin.x: visualizerItem.width / 2
                origin.y: visualizerItem.height / 2
                xScale: root.elementStretchX("visualizer")
                yScale: root.elementStretchY("visualizer")
            }
            z: 8

            Repeater {
                model: visualizerItem.bandCount

                Rectangle {
                    readonly property real amplitude: index < visualizerItem.displayBands.length
                        ? Number(visualizerItem.displayBands[index]) : 0
                    readonly property real safeAmplitude: Number.isFinite(amplitude)
                        ? Math.max(0, Math.min(1, amplitude)) : 0
                    readonly property real availableWidth: Math.max(1,
                        visualizerItem.width - visualizerItem.gapPx
                            * Math.max(0, visualizerItem.bandCount - 1))
                    readonly property real thickness: Math.max(1,
                        availableWidth / Math.max(1, visualizerItem.bandCount))
                    readonly property real barLength: Math.max(2 * root.uiScale,
                        safeAmplitude * visualizerItem.responseHeight)
                    readonly property real unitPosition: visualizerItem.bandCount <= 1 ? 0
                        : index / (visualizerItem.bandCount - 1)
                    readonly property real signedPosition: unitPosition * 2 - 1
                    readonly property real arcOffset: visualizerItem.shapeMode === "arc"
                        ? (1 - signedPosition * signedPosition)
                            * visualizerItem.bendAmount * 0.42 * root.uiScale : 0
                    readonly property real angleRadians: -Math.PI / 2
                        + index * Math.PI * 2 / Math.max(1, visualizerItem.bandCount)
                    readonly property real circleRadius: Math.min(
                        visualizerItem.width, visualizerItem.height) * 0.29

                    width: thickness
                    height: barLength
                    radius: Math.min(width / 2, 2 * root.uiScale)
                    color: root.elementColor("visualizer")
                    antialiasing: true
                    x: visualizerItem.shapeMode === "circle"
                        ? visualizerItem.width / 2 + Math.cos(angleRadians) * circleRadius - width / 2
                        : index * (thickness + visualizerItem.gapPx)
                    y: visualizerItem.shapeMode === "circle"
                        ? visualizerItem.height / 2 + Math.sin(angleRadians) * circleRadius - height / 2
                        : visualizerItem.height - height - arcOffset
                    rotation: visualizerItem.shapeMode === "circle"
                        ? angleRadians * 180 / Math.PI + 90
                        : visualizerItem.shapeMode === "arc"
                            ? -signedPosition * visualizerItem.bendAmount * 0.22 : 0
                    transformOrigin: Item.Center
                }
            }
        }

'''
scene = replace_once(
    scene,
    "        Item {\n            id: wordmarkItem\n",
    visualizer_item + "        Item {\n            id: wordmarkItem\n",
    "visualizer render item",
)
scene_path.write_text(scene)
Path("config/quickshell/awtarchy/LockPreviewScene.qml").write_text(scene)


# The old interaction contract rejected every secure analyzer because audio was
# previously logo-only. Pass 3 permits exactly the analyzer gated by the
# standalone visualizer while continuing to reject audio-reactive logo state.
interactive_path = Path("tests/test-quickshell-lockscreen-interactive-effects.sh")
interactive = interactive_path.read_text()
interactive = replace_once(
    interactive,
    "reject_text \"$SHELL_QML\" 'LockAudioAnalyzer {' \\\n    'secure lock still starts an analyzer solely to move the AWTARCHY logo'\n",
    "require_text \"$SHELL_QML\" 'LockAudioAnalyzer {' \\\n"
    "    'secure lock has no shared analyzer for the standalone visualizer'\n"
    "require_text \"$SHELL_QML\" 'enabled: root.lockVisualizer.enabled' \\\n"
    "    'standalone visualizer does not gate secure analyzer lifecycle'\n",
    "interactive analyzer contract",
)
interactive_path.write_text(interactive)


# Background transparency is presentation-only; WlSessionLockSurface remains
# the lock authority while its compositor base must permit alpha composition.
foundation_path = Path("tests/test-quickshell-lockscreen-foundation.sh")
foundation = foundation_path.read_text()
foundation = replace_once(
    foundation,
    "require_text \"$SURFACE_QML\" 'color: \"#000000\"' \\\n    'lock surface does not use an opaque black compositor-surface base'\n",
    "require_text \"$SURFACE_QML\" 'required property int backgroundOpacity' \\\n"
    "    'lock surface has no presentation-only background opacity input'\n"
    "require_text \"$SCENE_QML\" 'id: backgroundLayer' \\\n"
    "    'shared scene does not isolate background alpha from secure presentation'\n",
    "foundation transparent base contract",
)
foundation_path.write_text(foundation)
