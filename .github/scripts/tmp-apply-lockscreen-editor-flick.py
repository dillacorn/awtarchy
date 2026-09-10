#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EDITOR = ROOT / "config/quickshell/awtarchy/LockscreenEditor.qml"
SCENES = [
    ROOT / "config/quickshell/awtarchy/LockPreviewScene.qml",
    ROOT / "config/quickshell/awtarchy-lock/LockScene.qml",
]


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


editor = EDITOR.read_text()

editor = replace_once(
    editor,
    '    property bool contrastRefreshPending: false\n',
    '''    property bool contrastRefreshPending: false
    property string heldElement: ""
    property real heldScaleBoost: 1.0

    readonly property real flickThreshold: 0.80
    readonly property real flickVelocityCap: 2.50
    readonly property real flickFriction: 0.86
    readonly property real flickBounceDamping: 0.38
    readonly property real flickStopSpeed: 0.04
    readonly property int flickReleaseFreshnessMs: 80
''',
    "editor interaction properties",
)

old_point = '''    function setDraftPoint(name, x, y) {
        if (elementNames.indexOf(name) < 0)
            return;
        const next = cloneLayout(draftLayout);
        const point = clampPoint(name, Number(x), Number(y));
        next[name] = ({
            x: point.x,
            y: point.y,
            scale: next[name].scale,
            color: next[name].color
        });
        draftLayout = next;
        selectedElement = name;
        scheduleContrastRefresh();
    }
'''
new_point = '''    function writeDraftPoint(name, x, y, selectElement) {
        if (elementNames.indexOf(name) < 0)
            return;
        const next = cloneLayout(draftLayout);
        const point = clampPoint(name, Number(x), Number(y));
        next[name] = ({
            x: point.x,
            y: point.y,
            scale: next[name].scale,
            color: next[name].color
        });
        draftLayout = next;
        if (selectElement)
            selectedElement = name;
        scheduleContrastRefresh();
    }

    function setDraftPoint(name, x, y) {
        writeDraftPoint(name, x, y, true);
    }

    function setDraftPointSilently(name, x, y) {
        writeDraftPoint(name, x, y, false);
    }

    function cappedFlickVelocity(value) {
        const numeric = Number(value);
        const safe = Number.isFinite(numeric) ? numeric : 0;
        return Math.max(-flickVelocityCap, Math.min(flickVelocityCap, safe));
    }

    function shouldStartFlick(vx, vy) {
        return Math.sqrt(vx * vx + vy * vy) >= flickThreshold;
    }

    function animateHeldScale(targetScale, durationMs) {
        heldScaleAnimation.stop();
        heldScaleAnimation.from = heldScaleBoost;
        heldScaleAnimation.to = targetScale;
        heldScaleAnimation.duration = durationMs;
        heldScaleAnimation.start();
    }

    function beginEditorHold(name) {
        if (elementNames.indexOf(name) < 0)
            return;
        heldReleaseClear.stop();
        heldSettle.stop();
        heldElement = name;
        animateHeldScale(1.10, 65);
        heldSettle.restart();
    }

    function endEditorHold(name) {
        if (heldElement !== name)
            return;
        heldSettle.stop();
        animateHeldScale(1.0, 90);
        heldReleaseClear.restart();
    }
'''
editor = replace_once(editor, old_point, new_point, "editor point/flick helpers")

old_close = '''    function close() {
        FlyoutManager.releaseOverlay("lockscreen-editor");
        editorWindow.visible = false;
        loadPersistedDraft();
    }
'''
new_close = '''    function close() {
        heldSettle.stop();
        heldReleaseClear.stop();
        heldScaleAnimation.stop();
        heldElement = "";
        heldScaleBoost = 1.0;
        FlyoutManager.releaseOverlay("lockscreen-editor");
        editorWindow.visible = false;
        loadPersistedDraft();
    }
'''
editor = replace_once(editor, old_close, new_close, "editor close cleanup")

old_timer_anchor = '''    Timer {
        id: closeAfterSave
        interval: 180
        repeat: false
        onTriggered: root.close()
    }

    LockPreviewWallpaperState {
'''
new_timer_anchor = '''    Timer {
        id: closeAfterSave
        interval: 180
        repeat: false
        onTriggered: root.close()
    }

    NumberAnimation {
        id: heldScaleAnimation
        target: root
        property: "heldScaleBoost"
        duration: 70
        easing.type: Easing.OutCubic
    }

    Timer {
        id: heldSettle
        interval: 70
        repeat: false
        onTriggered: {
            if (root.heldElement.length > 0)
                root.animateHeldScale(1.045, 70);
        }
    }

    Timer {
        id: heldReleaseClear
        interval: 110
        repeat: false
        onTriggered: {
            if (root.heldScaleBoost <= 1.005)
                root.heldElement = "";
        }
    }

    LockPreviewWallpaperState {
'''
editor = replace_once(editor, old_timer_anchor, new_timer_anchor, "pickup animation objects")

old_preview_props = '''                editorMode: true
                editorVisibility: root.draftVisibility
            }
'''
new_preview_props = '''                editorMode: true
                editorVisibility: root.draftVisibility
                editorHeldElement: root.heldElement
                editorHoldScale: root.heldScaleBoost
            }
'''
editor = replace_once(editor, old_preview_props, new_preview_props, "preview pickup bindings")

old_delegate_props = '''                    opacity: 0.92
                    z: 200

                    MouseArea {
'''
new_delegate_props = '''                    opacity: 0.92
                    z: 200
                    property real lastSampleTime: 0
                    property real lastSampleX: 0
                    property real lastSampleY: 0
                    property real flickVelocityX: 0
                    property real flickVelocityY: 0
                    property bool inertiaActive: false

                    MouseArea {
'''
editor = replace_once(editor, old_delegate_props, new_delegate_props, "drag delegate physics properties")

old_mouse = '''                    MouseArea {
                        id: dragArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.SizeAllCursor
                        preventStealing: true
                        property real pressOffsetX: 0
                        property real pressOffsetY: 0

                        onPressed: mouse => {
                            root.selectedElement = parent.elementName;
                            pressOffsetX = mouse.x;
                            pressOffsetY = mouse.y;
                        }

                        onPositionChanged: mouse => {
                            if (!pressed || editorFocus.width <= 0 || editorFocus.height <= 0)
                                return;
                            const scenePoint = parent.mapToItem(editorFocus,
                                mouse.x - pressOffsetX + parent.width / 2,
                                mouse.y - pressOffsetY + parent.height / 2);
                            root.setDraftPoint(parent.elementName,
                                scenePoint.x / editorFocus.width,
                                scenePoint.y / editorFocus.height);
                        }
                    }
'''
new_mouse = '''                    MouseArea {
                        id: dragArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.SizeAllCursor
                        preventStealing: true
                        property real pressOffsetX: 0
                        property real pressOffsetY: 0

                        onPressed: mouse => {
                            parent.inertiaActive = false;
                            parent.flickVelocityX = 0;
                            parent.flickVelocityY = 0;
                            root.selectedElement = parent.elementName;
                            pressOffsetX = mouse.x;
                            pressOffsetY = mouse.y;
                            const point = root.draftLayout[parent.elementName]
                                || root.defaultLayout()[parent.elementName];
                            parent.lastSampleX = Number(point.x);
                            parent.lastSampleY = Number(point.y);
                            parent.lastSampleTime = Date.now();
                            root.beginEditorHold(parent.elementName);
                        }

                        onPositionChanged: mouse => {
                            if (!pressed || editorFocus.width <= 0 || editorFocus.height <= 0)
                                return;
                            const scenePoint = parent.mapToItem(editorFocus,
                                mouse.x - pressOffsetX + parent.width / 2,
                                mouse.y - pressOffsetY + parent.height / 2);
                            const clamped = root.clampPoint(parent.elementName,
                                scenePoint.x / editorFocus.width,
                                scenePoint.y / editorFocus.height);
                            const now = Date.now();
                            if (parent.lastSampleTime > 0 && now > parent.lastSampleTime) {
                                const dt = Math.max(8, now - parent.lastSampleTime) / 1000;
                                const sampleVX = (clamped.x - parent.lastSampleX) / dt;
                                const sampleVY = (clamped.y - parent.lastSampleY) / dt;
                                parent.flickVelocityX = parent.flickVelocityX * 0.30 + sampleVX * 0.70;
                                parent.flickVelocityY = parent.flickVelocityY * 0.30 + sampleVY * 0.70;
                            }
                            parent.lastSampleX = clamped.x;
                            parent.lastSampleY = clamped.y;
                            parent.lastSampleTime = now;
                            root.setDraftPoint(parent.elementName, clamped.x, clamped.y);
                        }

                        onReleased: mouse => {
                            root.endEditorHold(parent.elementName);
                            if (Date.now() - parent.lastSampleTime > root.flickReleaseFreshnessMs) {
                                parent.flickVelocityX = 0;
                                parent.flickVelocityY = 0;
                            }
                            parent.flickVelocityX = root.cappedFlickVelocity(parent.flickVelocityX);
                            parent.flickVelocityY = root.cappedFlickVelocity(parent.flickVelocityY);
                            if (root.shouldStartFlick(parent.flickVelocityX, parent.flickVelocityY))
                                parent.inertiaActive = true;
                            else {
                                parent.flickVelocityX = 0;
                                parent.flickVelocityY = 0;
                                parent.inertiaActive = false;
                            }
                        }

                        onCanceled: {
                            parent.inertiaActive = false;
                            parent.flickVelocityX = 0;
                            parent.flickVelocityY = 0;
                            root.endEditorHold(parent.elementName);
                        }
                    }

                    Timer {
                        id: inertiaTimer
                        interval: 16
                        repeat: true
                        running: root.open && parent.inertiaActive
                        onRunningChanged: {
                            if (!root.open && !running) {
                                parent.inertiaActive = false;
                                parent.flickVelocityX = 0;
                                parent.flickVelocityY = 0;
                            }
                        }
                        onTriggered: {
                            const point = root.draftLayout[parent.elementName]
                                || root.defaultLayout()[parent.elementName];
                            const dt = interval / 1000;
                            const proposedX = Number(point.x) + parent.flickVelocityX * dt;
                            const proposedY = Number(point.y) + parent.flickVelocityY * dt;
                            const clamped = root.clampPoint(parent.elementName, proposedX, proposedY);

                            if (Math.abs(clamped.x - proposedX) > 0.000001)
                                parent.flickVelocityX = -parent.flickVelocityX * root.flickBounceDamping;
                            if (Math.abs(clamped.y - proposedY) > 0.000001)
                                parent.flickVelocityY = -parent.flickVelocityY * root.flickBounceDamping;

                            root.setDraftPointSilently(parent.elementName, clamped.x, clamped.y);
                            parent.flickVelocityX *= root.flickFriction;
                            parent.flickVelocityY *= root.flickFriction;

                            if (Math.sqrt(parent.flickVelocityX * parent.flickVelocityX
                                    + parent.flickVelocityY * parent.flickVelocityY) < root.flickStopSpeed) {
                                parent.inertiaActive = false;
                                parent.flickVelocityX = 0;
                                parent.flickVelocityY = 0;
                            }
                        }
                    }
'''
editor = replace_once(editor, old_mouse, new_mouse, "drag/flick handler")

EDITOR.write_text(editor)

for scene_path in SCENES:
    scene = scene_path.read_text()
    scene = replace_once(
        scene,
        '    property var editorVisibility: ({})\n',
        '''    property var editorVisibility: ({})
    property string editorHeldElement: ""
    property real editorHoldScale: 1.0
''',
        f"{scene_path.name} editor pickup properties",
    )
    old_scale = '''    function elementScale(name) {
        const point = normalizedPoint(name);
        const value = point ? Number(point.scale === undefined ? 1 : point.scale) : 1;
        return Number.isFinite(value) ? Math.max(0.50, Math.min(2.00, value)) : 1;
    }
'''
    new_scale = '''    function elementScale(name) {
        const point = normalizedPoint(name);
        const value = point ? Number(point.scale === undefined ? 1 : point.scale) : 1;
        const baseScale = Number.isFinite(value) ? Math.max(0.50, Math.min(2.00, value)) : 1;
        const holdScale = root.editorMode && name === editorHeldElement ? editorHoldScale : 1.0;
        const safeHoldScale = Number.isFinite(Number(holdScale))
            ? Math.max(1.0, Math.min(1.12, Number(holdScale))) : 1.0;
        return baseScale * safeHoldScale;
    }
'''
    scene = replace_once(scene, old_scale, new_scale, f"{scene_path.name} transient held scale")
    scene_path.write_text(scene)

if SCENES[0].read_bytes() != SCENES[1].read_bytes():
    raise SystemExit("secure and preview scenes diverged")
