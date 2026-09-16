#!/usr/bin/env python3
from pathlib import Path
import re


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count == 0:
        if new in text:
            return text
        raise SystemExit(f"missing patch target: {label}")
    if count != 1:
        raise SystemExit(f"ambiguous patch target ({count}): {label}")
    return text.replace(old, new, 1)


path = Path("config/quickshell/awtarchy/LockscreenEditor.qml")
text = path.read_text()

text = replace_once(
    text,
    '    readonly property real keyboardNudgeLarge: 0.01\n',
    '    readonly property real keyboardNudgeLarge: 0.01\n    readonly property real dragActivationThresholdPx: 5\n',
    "drag threshold property",
)

text = replace_once(
    text,
    '    Shortcut { sequence: "Escape"; context: Qt.ApplicationShortcut; enabled: root.open && !root.pickerSuspended; autoRepeat: false; onActivated: root.close() }\n',
    '    Shortcut { sequence: "Ctrl+S"; context: Qt.ApplicationShortcut; enabled: root.open && !root.pickerSuspended; autoRepeat: false; onActivated: root.save() }\n'
    '    Shortcut { sequence: "Escape"; context: Qt.ApplicationShortcut; enabled: root.open && !root.pickerSuspended; autoRepeat: false; onActivated: root.close() }\n',
    "save shortcut",
)

text = replace_once(
    text,
    '                        SettingsButton { label: "Cancel"; textSize: 9; onClicked: root.close() }\n'
    '                        SettingsButton { label: "Save"; active: true; textSize: 9; available: !saveProcess.running && !contrastPersistProcess.running; onClicked: root.save() }',
    '                        Text { text: "Ctrl+S Save  •  Esc Cancel"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 8 }\n'
    '                        SettingsButton { label: "Cancel"; textSize: 9; onClicked: root.close() }\n'
    '                        SettingsButton { label: "Save"; active: true; textSize: 9; available: !saveProcess.running && !contrastPersistProcess.running; onClicked: root.save() }',
    "shortcut hint",
)

pattern = re.compile(
    r'                    MouseArea \{ id: dragArea;.*?\n                    \}\n\n                    Rectangle \{ id: elementResizeHandle;',
    re.S,
)
replacement = '''                    MouseArea {
                        id: dragArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.SizeAllCursor
                        preventStealing: true
                        property real pressOffsetX: 0
                        property real pressOffsetY: 0
                        property bool dragActivated: false

                        onPressed: mouse => {
                            if (root.inertiaOwner.length > 0) {
                                root.inertiaOwner = "";
                                root.commitHistoryTransaction();
                            }
                            parent.inertiaActive = false;
                            parent.flickVelocityX = 0;
                            parent.flickVelocityY = 0;
                            const additive = !!(mouse.modifiers & (Qt.ShiftModifier | Qt.ControlModifier));
                            if (additive)
                                root.selectElement(parent.elementName, true);
                            else if (!root.selectedContains(parent.elementName))
                                root.selectElement(parent.elementName, false);
                            else
                                root.activeDrawer = "element";
                            if (!root.selectedContains(parent.elementName))
                                return;
                            dragActivated = false;
                            pressOffsetX = mouse.x;
                            pressOffsetY = mouse.y;
                            parent.lastSampleTime = 0;
                        }

                        onPositionChanged: mouse => {
                            if (!pressed || !root.selectedContains(parent.elementName)
                                    || editorFocus.width <= 0 || editorFocus.height <= 0)
                                return;
                            if (!dragActivated) {
                                const deltaX = mouse.x - pressOffsetX;
                                const deltaY = mouse.y - pressOffsetY;
                                if (Math.hypot(deltaX, deltaY) < root.dragActivationThresholdPx)
                                    return;
                                dragActivated = true;
                                root.beginHistoryTransaction();
                                const startPoint = root.elementPoint(parent.elementName);
                                parent.lastSampleX = Number(startPoint.x);
                                parent.lastSampleY = Number(startPoint.y);
                                parent.lastSampleTime = Date.now();
                                root.beginEditorHold(parent.elementName);
                            }
                            const scenePoint = parent.mapToItem(editorFocus,
                                mouse.x - pressOffsetX + parent.width / 2,
                                mouse.y - pressOffsetY + parent.height / 2);
                            const bypassSnap = !!(mouse.modifiers & Qt.AltModifier);
                            const snapped = root.snapPoint(parent.elementName,
                                scenePoint.x / editorFocus.width,
                                scenePoint.y / editorFocus.height,
                                bypassSnap);
                            const current = root.elementPoint(parent.elementName);
                            root.translateSelectedElements(snapped.x - Number(current.x),
                                snapped.y - Number(current.y), true);
                            const moved = root.elementPoint(parent.elementName);
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

                        onReleased: mouse => {
                            root.clearGuides();
                            if (!dragActivated) {
                                parent.inertiaActive = false;
                                parent.flickVelocityX = 0;
                                parent.flickVelocityY = 0;
                                return;
                            }
                            root.endEditorHold(parent.elementName);
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
                            dragActivated = false;
                        }

                        onCanceled: {
                            parent.inertiaActive = false;
                            parent.flickVelocityX = 0;
                            parent.flickVelocityY = 0;
                            if (root.inertiaOwner === parent.elementName)
                                root.inertiaOwner = "";
                            if (dragActivated) {
                                root.endEditorHold(parent.elementName);
                                root.commitHistoryTransaction();
                            }
                            dragActivated = false;
                            root.clearGuides();
                        }
                    }

                    Rectangle { id: elementResizeHandle;'''
text, count = pattern.subn(replacement, text, count=1)
if count != 1:
    if 'property bool dragActivated: false' not in text:
        raise SystemExit("missing/ambiguous patch target: element drag MouseArea")

path.write_text(text)
