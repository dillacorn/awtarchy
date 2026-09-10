#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EDITOR = ROOT / "config/quickshell/awtarchy/LockscreenEditor.qml"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


text = EDITOR.read_text()

text = replace_once(
    text,
    '''    readonly property int flickReleaseFreshnessMs: 80
''',
    '''    readonly property int flickReleaseFreshnessMs: 80
    readonly property int historyLimit: 50
    readonly property real snapThreshold: 0.008
    readonly property real keyboardNudge: 0.002
    readonly property real keyboardNudgeLarge: 0.01

    property var undoStack: []
    property var redoStack: []
    property bool historyTransactionActive: false
    property var historyTransactionSnapshot: null
    property var selectedElements: ["logo"]
    property real guideX: -1
    property real guideY: -1
    property string inertiaOwner: ""
''',
    "editor tooling properties",
)

anchor = '''    function setAllDraftColors(colorValue) {
'''
helpers = r'''    function cloneSnapshot(snapshot) {
        try {
            return JSON.parse(JSON.stringify(snapshot));
        } catch (error) {
            return null;
        }
    }

    function editorSnapshot() {
        return ({
            layout: cloneLayout(draftLayout),
            visibility: cloneVisibility(draftVisibility),
            backgroundMode: draftBackgroundMode,
            backgroundColor: draftBackgroundColor,
            wallpaperPath: draftWallpaperPath
        });
    }

    function snapshotKey(snapshot) {
        try {
            return JSON.stringify(snapshot);
        } catch (error) {
            return "";
        }
    }

    function appendHistory(stack, snapshot) {
        const copy = cloneSnapshot(snapshot);
        if (!copy)
            return stack.slice();
        const next = stack.slice();
        if (next.length === 0 || snapshotKey(next[next.length - 1]) !== snapshotKey(copy))
            next.push(copy);
        while (next.length > historyLimit)
            next.shift();
        return next;
    }

    function restoreEditorSnapshot(snapshot) {
        if (!snapshot || typeof snapshot !== "object")
            return;
        draftLayout = cloneLayout(snapshot.layout);
        draftVisibility = cloneVisibility(snapshot.visibility);
        draftBackgroundMode = ["black", "wallpaper", "color"].indexOf(String(snapshot.backgroundMode)) >= 0
            ? String(snapshot.backgroundMode) : "black";
        draftBackgroundColor = validHex(snapshot.backgroundColor)
            ? String(snapshot.backgroundColor).toLowerCase() : "#000000";
        draftWallpaperPath = typeof snapshot.wallpaperPath === "string"
            ? snapshot.wallpaperPath : "";
        scheduleContrastRefresh();
    }

    function pushUndoSnapshot(snapshot) {
        if (!snapshot || snapshotKey(snapshot) === snapshotKey(editorSnapshot()))
            return;
        undoStack = appendHistory(undoStack, snapshot);
        redoStack = [];
    }

    function recordUndoBeforeChange() {
        if (!historyTransactionActive)
            pushUndoSnapshot(editorSnapshot());
    }

    function undo() {
        if (historyTransactionActive)
            commitHistoryTransaction();
        if (undoStack.length === 0)
            return;
        const current = editorSnapshot();
        const nextUndo = undoStack.slice();
        const target = nextUndo.pop();
        undoStack = nextUndo;
        redoStack = appendHistory(redoStack, current);
        restoreEditorSnapshot(target);
        statusMessage = "Undone";
    }

    function redo() {
        if (historyTransactionActive)
            commitHistoryTransaction();
        if (redoStack.length === 0)
            return;
        const current = editorSnapshot();
        const nextRedo = redoStack.slice();
        const target = nextRedo.pop();
        redoStack = nextRedo;
        undoStack = appendHistory(undoStack, current);
        restoreEditorSnapshot(target);
        statusMessage = "Redone";
    }

    function beginHistoryTransaction() {
        if (historyTransactionActive)
            commitHistoryTransaction();
        historyTransactionSnapshot = editorSnapshot();
        historyTransactionActive = true;
    }

    function commitHistoryTransaction() {
        if (!historyTransactionActive)
            return;
        const before = historyTransactionSnapshot;
        historyTransactionSnapshot = null;
        historyTransactionActive = false;
        if (before && snapshotKey(before) !== snapshotKey(editorSnapshot())) {
            undoStack = appendHistory(undoStack, before);
            redoStack = [];
        }
    }

    function selectedContains(name) {
        return selectedElements.indexOf(name) >= 0;
    }

    function selectElement(name, additive) {
        if (elementNames.indexOf(name) < 0)
            return;
        if (!additive) {
            selectedElement = name;
            selectedElements = [name];
            return;
        }
        const next = selectedElements.slice();
        const index = next.indexOf(name);
        if (index >= 0) {
            if (next.length > 1)
                next.splice(index, 1);
        } else {
            next.push(name);
        }
        selectedElements = next;
        selectedElement = selectedContains(name) ? name : next[0];
    }

    function primaryPoint() {
        return draftLayout[selectedElement] || defaultLayout()[selectedElement] || defaultLayout().logo;
    }

    function pointBounds(name) {
        const password = name === "password";
        return ({
            minX: password ? 0.15 : 0.05,
            maxX: password ? 0.85 : 0.95,
            minY: password ? 0.20 : 0.08,
            maxY: password ? 0.86 : 0.92
        });
    }

    function clampedGroupDelta(dx, dy) {
        let minDx = -2;
        let maxDx = 2;
        let minDy = -2;
        let maxDy = 2;
        for (const name of selectedElements) {
            const point = draftLayout[name] || defaultLayout()[name];
            const bounds = pointBounds(name);
            minDx = Math.max(minDx, bounds.minX - Number(point.x));
            maxDx = Math.min(maxDx, bounds.maxX - Number(point.x));
            minDy = Math.max(minDy, bounds.minY - Number(point.y));
            maxDy = Math.min(maxDy, bounds.maxY - Number(point.y));
        }
        return ({
            x: Math.max(minDx, Math.min(maxDx, Number(dx) || 0)),
            y: Math.max(minDy, Math.min(maxDy, Number(dy) || 0))
        });
    }

    function translateSelectedElements(dx, dy, selectPrimary) {
        const delta = clampedGroupDelta(dx, dy);
        if (Math.abs(delta.x) < 0.0000001 && Math.abs(delta.y) < 0.0000001)
            return delta;
        const next = cloneLayout(draftLayout);
        for (const name of selectedElements) {
            const point = next[name] || defaultLayout()[name];
            point.x = Number(point.x) + delta.x;
            point.y = Number(point.y) + delta.y;
            next[name] = point;
        }
        draftLayout = next;
        if (selectPrimary && selectedElements.length > 0 && !selectedContains(selectedElement))
            selectedElement = selectedElements[0];
        scheduleContrastRefresh();
        return delta;
    }

    function clearGuides() {
        guideX = -1;
        guideY = -1;
    }

    function snapPoint(name, x, y, bypassSnap) {
        const clamped = clampPoint(name, Number(x), Number(y));
        if (bypassSnap) {
            clearGuides();
            return clamped;
        }
        const xTargets = [0.5];
        const yTargets = [0.5];
        for (const peer of elementNames) {
            if (!root.selectedContains(peer)) {
                const point = draftLayout[peer] || defaultLayout()[peer];
                xTargets.push(Number(point.x));
                yTargets.push(Number(point.y));
            }
        }
        let snappedX = clamped.x;
        let snappedY = clamped.y;
        let bestX = snapThreshold + 1;
        let bestY = snapThreshold + 1;
        for (const target of xTargets) {
            const distance = Math.abs(clamped.x - target);
            if (distance <= snapThreshold && distance < bestX) {
                bestX = distance;
                snappedX = target;
            }
        }
        for (const target of yTargets) {
            const distance = Math.abs(clamped.y - target);
            if (distance <= snapThreshold && distance < bestY) {
                bestY = distance;
                snappedY = target;
            }
        }
        guideX = bestX <= snapThreshold ? snappedX : -1;
        guideY = bestY <= snapThreshold ? snappedY : -1;
        return clampPoint(name, snappedX, snappedY);
    }

    function nudgeSelection(dx, dy) {
        recordUndoBeforeChange();
        translateSelectedElements(dx, dy, true);
        clearGuides();
    }

    function setSelectedCoordinate(axis, percentValue) {
        const numeric = Number(percentValue);
        if (!Number.isFinite(numeric))
            return;
        const target = Math.max(0, Math.min(100, numeric)) / 100;
        const point = primaryPoint();
        recordUndoBeforeChange();
        if (axis === "x")
            translateSelectedElements(target - Number(point.x), 0, true);
        else if (axis === "y")
            translateSelectedElements(0, target - Number(point.y), true);
    }

'''
text = replace_once(text, anchor, helpers + anchor, "editor history/group helpers")

# Record reversible non-pointer edits.
for old, new, label in [
    ('        const next = cloneLayout(draftLayout);\n        for (const name of elementNames)\n            next[name].color = value;\n',
     '        recordUndoBeforeChange();\n        const next = cloneLayout(draftLayout);\n        for (const name of elementNames)\n            next[name].color = value;\n',
     'all colors history'),
    ('        const defaults = defaultLayout();\n        const next = cloneLayout(draftLayout);\n        next[name].x = defaults[name].x;\n',
     '        recordUndoBeforeChange();\n        const defaults = defaultLayout();\n        const next = cloneLayout(draftLayout);\n        next[name].x = defaults[name].x;\n',
     'reset position history'),
    ('        draftBackgroundMode = value;\n        statusMessage = "";\n        scheduleContrastRefresh();\n',
     '        recordUndoBeforeChange();\n        draftBackgroundMode = value;\n        statusMessage = "";\n        scheduleContrastRefresh();\n',
     'background mode history'),
    ('        draftBackgroundColor = value;\n        draftBackgroundMode = "color";\n',
     '        recordUndoBeforeChange();\n        draftBackgroundColor = value;\n        draftBackgroundMode = "color";\n',
     'background color history'),
    ('        draftWallpaperPath = value;\n        draftBackgroundMode = "wallpaper";\n',
     '        recordUndoBeforeChange();\n        draftWallpaperPath = value;\n        draftBackgroundMode = "wallpaper";\n',
     'wallpaper selection history'),
    ('        const next = cloneLayout(draftLayout);\n        const point = clampPoint(name, Number(x), Number(y));\n',
     '        if (selectElement)\n            recordUndoBeforeChange();\n        const next = cloneLayout(draftLayout);\n        const point = clampPoint(name, Number(x), Number(y));\n',
     'point history'),
    ('        const next = cloneLayout(draftLayout);\n        next[name].color = value;\n        draftLayout = next;\n        selectedElement = name;\n',
     '        recordUndoBeforeChange();\n        const next = cloneLayout(draftLayout);\n        next[name].color = value;\n        draftLayout = next;\n        selectElement(name, false);\n',
     'element color history'),
    ('        const next = cloneLayout(draftLayout);\n        const value = Number(scale);\n',
     '        recordUndoBeforeChange();\n        const next = cloneLayout(draftLayout);\n        const value = Number(scale);\n',
     'element scale history'),
    ('        const next = cloneVisibility(draftVisibility);\n        next[name] = !!visible;\n',
     '        recordUndoBeforeChange();\n        const next = cloneVisibility(draftVisibility);\n        next[name] = !!visible;\n',
     'visibility history'),
    ('    function resetDraft() {\n        draftLayout = defaultLayout();\n',
     '    function resetDraft() {\n        recordUndoBeforeChange();\n        draftLayout = defaultLayout();\n',
     'defaults history'),
]:
    text = replace_once(text, old, new, label)

# Avoid selecting from silent inertia writes and keep selection array coherent.
text = replace_once(
    text,
    '''        if (selectElement)
            selectedElement = name;
''',
    '''        if (selectElement)
            selectElement(name, false);
''',
    "point selection helper",
)
text = replace_once(
    text,
    '''        draftLayout = next;
        selectedElement = name;
        statusMessage = "";
    }

    function setDraftScale''',
    '''        draftLayout = next;
        selectElement(name, false);
        statusMessage = "";
    }

    function setDraftScale''',
    "color selection coherence",
)
text = replace_once(
    text,
    '''        next[name].scale = Math.round(Math.max(0.50, Math.min(2.00, value)) * 100) / 100;
        draftLayout = next;
        selectedElement = name;
    }
''',
    '''        next[name].scale = Math.round(Math.max(0.50, Math.min(2.00, value)) * 100) / 100;
        draftLayout = next;
        selectElement(name, false);
    }
''',
    "scale selection coherence",
)
text = replace_once(
    text,
    '''        next[name] = !!visible;
        draftVisibility = next;
        selectedElement = name;
    }
''',
    '''        next[name] = !!visible;
        draftVisibility = next;
        selectElement(name, false);
    }
''',
    "visibility selection coherence",
)

# Reset/open/close transient tooling state.
text = replace_once(
    text,
    '''        selectedElement = "logo";
        elementPaletteOpen = false;
''',
    '''        selectedElement = "logo";
        selectedElements = ["logo"];
        clearGuides();
        elementPaletteOpen = false;
''',
    "reset selection state",
)
text = replace_once(
    text,
    '''        selectedElement = elementNames.indexOf(selectedElement) >= 0 ? selectedElement : "logo";
        elementPaletteOpen = false;
''',
    '''        selectedElement = elementNames.indexOf(selectedElement) >= 0 ? selectedElement : "logo";
        selectedElements = [selectedElement];
        clearGuides();
        elementPaletteOpen = false;
''',
    "load selection state",
)
text = replace_once(
    text,
    '''        loadPersistedDraft();
        editorWindow.visible = true;
''',
    '''        loadPersistedDraft();
        undoStack = [];
        redoStack = [];
        historyTransactionActive = false;
        historyTransactionSnapshot = null;
        inertiaOwner = "";
        editorWindow.visible = true;
''',
    "open history reset",
)
text = replace_once(
    text,
    '''        heldElement = "";
        heldScaleBoost = 1.0;
        FlyoutManager.releaseOverlay("lockscreen-editor");
''',
    '''        heldElement = "";
        heldScaleBoost = 1.0;
        inertiaOwner = "";
        historyTransactionActive = false;
        historyTransactionSnapshot = null;
        clearGuides();
        FlyoutManager.releaseOverlay("lockscreen-editor");
''',
    "close tooling cleanup",
)

# Keyboard shortcuts.
escape = '''    Shortcut {
        sequence: "Escape"
        context: Qt.ApplicationShortcut
        enabled: root.open
        autoRepeat: false
        onActivated: root.close()
    }
'''
shortcuts = escape + '''
    Shortcut {
        sequence: "Ctrl+Z"
        context: Qt.ApplicationShortcut
        enabled: root.open && root.undoStack.length > 0
        autoRepeat: false
        onActivated: root.undo()
    }

    Shortcut {
        sequence: "Ctrl+Shift+Z"
        context: Qt.ApplicationShortcut
        enabled: root.open && root.redoStack.length > 0
        autoRepeat: false
        onActivated: root.redo()
    }

    Shortcut {
        sequence: "Ctrl+Y"
        context: Qt.ApplicationShortcut
        enabled: root.open && root.redoStack.length > 0
        autoRepeat: false
        onActivated: root.redo()
    }
'''
text = replace_once(text, escape, shortcuts, "undo redo shortcuts")

# Arrow keys on the editor focus surface.
text = replace_once(
    text,
    '''            color: "#000000"
            focus: true

            LockPreviewScene {
''',
    '''            color: "#000000"
            focus: true

            Keys.onPressed: event => {
                const step = event.modifiers & Qt.ShiftModifier
                    ? root.keyboardNudgeLarge : root.keyboardNudge;
                if (event.key === Qt.Key_Left) {
                    root.nudgeSelection(-step, 0);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Right) {
                    root.nudgeSelection(step, 0);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Up) {
                    root.nudgeSelection(0, -step);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Down) {
                    root.nudgeSelection(0, step);
                    event.accepted = true;
                }
            }

            LockPreviewScene {
''',
    "keyboard nudging",
)

# Delegate selection border and group drag state.
text = replace_once(
    text,
    '''                    border.width: root.selectedElement === elementName ? 2 : 1
                    border.color: root.selectedElement === elementName ? Theme.focus : Theme.muted
''',
    '''                    border.width: root.selectedContains(elementName) ? 2 : 1
                    border.color: root.selectedContains(elementName) ? Theme.focus : Theme.muted
''',
    "multi-selection border",
)
text = replace_once(
    text,
    '''                    property real flickVelocityY: 0
                    property bool inertiaActive: false
''',
    '''                    property real flickVelocityY: 0
                    property bool inertiaActive: false
''',
    "delegate anchor",
)

old_press = '''                        onPressed: mouse => {
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
'''
new_press = '''                        onPressed: mouse => {
                            if (root.inertiaOwner.length > 0) {
                                root.inertiaOwner = "";
                                root.commitHistoryTransaction();
                            }
                            parent.inertiaActive = false;
                            parent.flickVelocityX = 0;
                            parent.flickVelocityY = 0;
                            const additive = !!(mouse.modifiers & Qt.ShiftModifier);
                            root.selectElement(parent.elementName, additive);
                            if (!root.selectedContains(parent.elementName))
                                return;
                            root.beginHistoryTransaction();
                            pressOffsetX = mouse.x;
                            pressOffsetY = mouse.y;
                            const point = root.draftLayout[parent.elementName]
                                || root.defaultLayout()[parent.elementName];
                            parent.lastSampleX = Number(point.x);
                            parent.lastSampleY = Number(point.y);
                            parent.lastSampleTime = Date.now();
                            root.beginEditorHold(parent.elementName);
                        }
'''
text = replace_once(text, old_press, new_press, "group press selection")

old_position = '''                        onPositionChanged: mouse => {
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
'''
new_position = '''                        onPositionChanged: mouse => {
                            if (!pressed || !root.selectedContains(parent.elementName)
                                    || editorFocus.width <= 0 || editorFocus.height <= 0)
                                return;
                            const scenePoint = parent.mapToItem(editorFocus,
                                mouse.x - pressOffsetX + parent.width / 2,
                                mouse.y - pressOffsetY + parent.height / 2);
                            const bypassSnap = !!(mouse.modifiers & Qt.AltModifier);
                            const snapped = root.snapPoint(parent.elementName,
                                scenePoint.x / editorFocus.width,
                                scenePoint.y / editorFocus.height,
                                bypassSnap);
                            const current = root.draftLayout[parent.elementName]
                                || root.defaultLayout()[parent.elementName];
                            root.translateSelectedElements(
                                snapped.x - Number(current.x),
                                snapped.y - Number(current.y), true);
                            const moved = root.draftLayout[parent.elementName]
                                || root.defaultLayout()[parent.elementName];
                            const now = Date.now();
                            if (parent.lastSampleTime > 0 && now > parent.lastSampleTime) {
                                const dt = Math.max(8, now - parent.lastSampleTime) / 1000;
                                const sampleVX = (Number(moved.x) - parent.lastSampleX) / dt;
                                const sampleVY = (Number(moved.y) - parent.lastSampleY) / dt;
                                parent.flickVelocityX = parent.flickVelocityX * 0.30 + sampleVX * 0.70;
                                parent.flickVelocityY = parent.flickVelocityY * 0.30 + sampleVY * 0.70;
                            }
                            parent.lastSampleX = Number(moved.x);
                            parent.lastSampleY = Number(moved.y);
                            parent.lastSampleTime = now;
                        }
'''
text = replace_once(text, old_position, new_position, "group drag snapping")

old_release = '''                        onReleased: mouse => {
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
'''
new_release = '''                        onReleased: mouse => {
                            root.endEditorHold(parent.elementName);
                            root.clearGuides();
                            if (Date.now() - parent.lastSampleTime > root.flickReleaseFreshnessMs) {
                                parent.flickVelocityX = 0;
                                parent.flickVelocityY = 0;
                            }
                            parent.flickVelocityX = root.cappedFlickVelocity(parent.flickVelocityX);
                            parent.flickVelocityY = root.cappedFlickVelocity(parent.flickVelocityY);
                            if (root.shouldStartFlick(parent.flickVelocityX, parent.flickVelocityY)) {
                                parent.inertiaActive = true;
                                root.inertiaOwner = parent.elementName;
                            } else {
                                parent.flickVelocityX = 0;
                                parent.flickVelocityY = 0;
                                parent.inertiaActive = false;
                                root.commitHistoryTransaction();
                            }
                        }
'''
text = replace_once(text, old_release, new_release, "release history")
text = replace_once(
    text,
    '''                        onCanceled: {
                            parent.inertiaActive = false;
                            parent.flickVelocityX = 0;
                            parent.flickVelocityY = 0;
                            root.endEditorHold(parent.elementName);
                        }
''',
    '''                        onCanceled: {
                            parent.inertiaActive = false;
                            parent.flickVelocityX = 0;
                            parent.flickVelocityY = 0;
                            if (root.inertiaOwner === parent.elementName)
                                root.inertiaOwner = "";
                            root.endEditorHold(parent.elementName);
                            root.clearGuides();
                            root.commitHistoryTransaction();
                        }
''',
    "cancel history",
)

# Preserve the existing single-element flick path verbatim while allowing a
# selected group to translate together. Selection cannot change while this
# delegate owns inertia; a new press clears inertiaOwner first.
text = replace_once(
    text,
    '''                        running: root.open && parent.inertiaActive
''',
    '''                        running: root.open && parent.inertiaActive
                            && root.inertiaOwner === parent.elementName
''',
    "inertia ownership",
)
old_tick = '''                            const point = root.draftLayout[parent.elementName]
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
'''
new_tick = '''                            const point = root.draftLayout[parent.elementName]
                                || root.defaultLayout()[parent.elementName];
                            const dt = interval / 1000;
                            if (root.selectedElements.length <= 1) {
                                const proposedX = Number(point.x) + parent.flickVelocityX * dt;
                                const proposedY = Number(point.y) + parent.flickVelocityY * dt;
                                const clamped = root.clampPoint(parent.elementName, proposedX, proposedY);

                                if (Math.abs(clamped.x - proposedX) > 0.000001)
                                    parent.flickVelocityX = -parent.flickVelocityX * root.flickBounceDamping;
                                if (Math.abs(clamped.y - proposedY) > 0.000001)
                                    parent.flickVelocityY = -parent.flickVelocityY * root.flickBounceDamping;

                                root.setDraftPointSilently(parent.elementName, clamped.x, clamped.y);
                            } else {
                                const proposedDX = parent.flickVelocityX * dt;
                                const proposedDY = parent.flickVelocityY * dt;
                                const moved = root.translateSelectedElements(proposedDX, proposedDY, false);
                                if (Math.abs(moved.x - proposedDX) > 0.000001)
                                    parent.flickVelocityX = -parent.flickVelocityX * root.flickBounceDamping;
                                if (Math.abs(moved.y - proposedDY) > 0.000001)
                                    parent.flickVelocityY = -parent.flickVelocityY * root.flickBounceDamping;
                            }
                            parent.flickVelocityX *= root.flickFriction;
                            parent.flickVelocityY *= root.flickFriction;

                            if (Math.sqrt(parent.flickVelocityX * parent.flickVelocityX
                                    + parent.flickVelocityY * parent.flickVelocityY) < root.flickStopSpeed) {
                                parent.inertiaActive = false;
                                parent.flickVelocityX = 0;
                                parent.flickVelocityY = 0;
                                if (root.inertiaOwner === parent.elementName)
                                    root.inertiaOwner = "";
                                root.commitHistoryTransaction();
                            }
'''
text = replace_once(text, old_tick, new_tick, "group inertia")

# Editor-only alignment guides.
panel_anchor = '''            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
'''
guides = '''            Rectangle {
                visible: root.guideX >= 0
                x: Math.round(root.guideX * parent.width)
                y: 0
                width: 1
                height: parent.height
                color: Theme.focus
                opacity: 0.72
                z: 250
            }

            Rectangle {
                visible: root.guideY >= 0
                x: 0
                y: Math.round(root.guideY * parent.height)
                width: parent.width
                height: 1
                color: Theme.focus
                opacity: 0.72
                z: 250
            }

'''
text = replace_once(text, panel_anchor, guides + panel_anchor, "snap guides")

# Numeric position inputs and undo/redo buttons near the primary element tools.
reset_button = '''                        SettingsButton {
                            label: "Reset Position"
                            textSize: 9
                            onClicked: root.resetElementPosition(root.selectedElement)
                        }

                        Item { Layout.fillWidth: true }
'''
position_controls = '''                        SettingsButton {
                            label: "Reset Position"
                            textSize: 9
                            onClicked: root.resetElementPosition(root.selectedElement)
                        }

                        Text {
                            text: "X"
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                        }
                        TextField {
                            id: positionXField
                            Layout.preferredWidth: 58
                            text: Number(root.primaryPoint().x * 100).toFixed(1)
                            validator: DoubleValidator { bottom: 0; top: 100; decimals: 1 }
                            selectByMouse: true
                            font.pixelSize: 9
                            onEditingFinished: root.setSelectedCoordinate("x", text)
                        }
                        Text {
                            text: "Y"
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                        }
                        TextField {
                            id: positionYField
                            Layout.preferredWidth: 58
                            text: Number(root.primaryPoint().y * 100).toFixed(1)
                            validator: DoubleValidator { bottom: 0; top: 100; decimals: 1 }
                            selectByMouse: true
                            font.pixelSize: 9
                            onEditingFinished: root.setSelectedCoordinate("y", text)
                        }

                        SettingsButton {
                            label: "Undo"
                            textSize: 9
                            available: root.undoStack.length > 0
                            onClicked: root.undo()
                        }
                        SettingsButton {
                            label: "Redo"
                            textSize: 9
                            available: root.redoStack.length > 0
                            onClicked: root.redo()
                        }

                        Item { Layout.fillWidth: true }
'''
text = replace_once(text, reset_button, position_controls, "numeric and history controls")

EDITOR.write_text(text)
