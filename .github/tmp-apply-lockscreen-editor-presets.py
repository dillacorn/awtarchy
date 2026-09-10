#!/usr/bin/env python3

from hashlib import sha256
from pathlib import Path

EDITOR = Path("config/quickshell/awtarchy/LockscreenEditor.qml")
HISTORY = Path("local/share/awtarchy/quickshell-managed-history.sha256")
MANAGED_PATH = ".config/quickshell/awtarchy/LockscreenEditor.qml"

text = EDITOR.read_text()


def replace_once(old: str, new: str, label: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one anchor, found {count}")
    text = text.replace(old, new, 1)


replace_once(
    "    property real heldScaleBoost: 1.0;\n",
    "    property real heldScaleBoost: 1.0;\n"
    "    property bool showEditorGrid: false\n",
    "guide toggle property",
)

preset_functions = r'''    function layoutPreset(name) {
        if (name === "minimal") {
            return ({
                logo: ({ x: 0.50, y: 0.38, scale: 1.0 }),
                time: ({ x: 0.50, y: 0.51, scale: 1.0 }),
                date: ({ x: 0.50, y: 0.555, scale: 1.0 }),
                username: ({ x: 0.50, y: 0.595, scale: 1.0 }),
                weather: ({ x: 0.50, y: 0.635, scale: 1.0 }),
                password: ({ x: 0.50, y: 0.62, scale: 1.0 })
            });
        }
        if (name === "centered") {
            return ({
                logo: ({ x: 0.50, y: 0.30, scale: 1.0 }),
                time: ({ x: 0.50, y: 0.47, scale: 1.0 }),
                date: ({ x: 0.50, y: 0.53, scale: 1.0 }),
                username: ({ x: 0.50, y: 0.58, scale: 1.0 }),
                weather: ({ x: 0.50, y: 0.62, scale: 1.0 }),
                password: ({ x: 0.50, y: 0.66, scale: 1.0 })
            });
        }
        if (name === "information") {
            return ({
                logo: ({ x: 0.50, y: 0.27, scale: 1.0 }),
                time: ({ x: 0.50, y: 0.44, scale: 1.0 }),
                date: ({ x: 0.50, y: 0.50, scale: 1.0 }),
                username: ({ x: 0.50, y: 0.55, scale: 1.0 }),
                weather: ({ x: 0.50, y: 0.60, scale: 1.0 }),
                password: ({ x: 0.50, y: 0.70, scale: 1.0 })
            });
        }
        if (name === "lower-third") {
            return ({
                logo: ({ x: 0.50, y: 0.28, scale: 1.0 }),
                time: ({ x: 0.50, y: 0.62, scale: 1.0 }),
                date: ({ x: 0.50, y: 0.675, scale: 1.0 }),
                username: ({ x: 0.50, y: 0.72, scale: 1.0 }),
                weather: ({ x: 0.50, y: 0.765, scale: 1.0 }),
                password: ({ x: 0.50, y: 0.84, scale: 1.0 })
            });
        }
        return null;
    }

    function presetVisibility(name) {
        const presets = ({
            minimal: ({ logo: true, time: false, date: false, username: false, weather: false, password: true }),
            centered: ({ logo: true, time: true, date: true, username: false, weather: false, password: true }),
            information: ({ logo: true, time: true, date: true, username: true, weather: true, password: true }),
            lowerThird: ({ logo: true, time: true, date: true, username: true, weather: true, password: true })
        });
        const key = name === "lower-third" ? "lowerThird" : String(name || "");
        if (!presets[key])
            return null;
        const visibility = cloneVisibility(presets[key]);
        visibility.password = true;
        return visibility;
    }

    function applyLayoutPreset(name) {
        const preset = layoutPreset(name);
        const visibility = presetVisibility(name);
        if (!preset || !visibility)
            return;
        const previous = editorSnapshot();
        const next = cloneLayout(draftLayout);
        for (const element of elementNames) {
            const current = next[element];
            const target = preset[element];
            next[element] = ({
                x: target.x,
                y: target.y,
                scale: target.scale,
                color: current.color
            });
            next[element].color = current.color;
        }
        draftLayout = next;
        draftVisibility = cloneVisibility(visibility);
        selectedElement = "logo";
        selectedElements = ["logo"];
        clearGuides();
        pushUndoSnapshot(previous);
        statusMessage = "Applied " + (name === "lower-third" ? "Lower Third" : elementLabel(name)) + " preset";
        scheduleContrastRefresh();
    }

'''
replace_once(
    "    function defaultAutoAccents() {\n",
    preset_functions + "    function defaultAutoAccents() {\n",
    "preset functions",
)

guide_overlay = r'''            Item {
                id: editorGridOverlay
                anchors.fill: parent
                visible: root.showEditorGrid
                enabled: false
                z: 175

                Rectangle {
                    id: safeAreaGuide
                    x: parent.width * 0.05
                    y: parent.height * 0.08
                    width: parent.width * 0.90
                    height: parent.height * 0.84
                    color: "transparent"
                    border.width: 1
                    border.color: Theme.muted
                    opacity: 0.72
                }

                Rectangle {
                    x: parent.width / 3
                    y: 0
                    width: 1
                    height: parent.height
                    color: Theme.muted
                    opacity: 0.38
                }
                Rectangle {
                    x: parent.width * 2 / 3
                    y: 0
                    width: 1
                    height: parent.height
                    color: Theme.muted
                    opacity: 0.38
                }
                Rectangle {
                    x: parent.width / 2
                    y: 0
                    width: 1
                    height: parent.height
                    color: Theme.focus
                    opacity: 0.56
                }
                Rectangle {
                    x: 0
                    y: parent.height / 3
                    width: parent.width
                    height: 1
                    color: Theme.muted
                    opacity: 0.38
                }
                Rectangle {
                    x: 0
                    y: parent.height * 2 / 3
                    width: parent.width
                    height: 1
                    color: Theme.muted
                    opacity: 0.38
                }
                Rectangle {
                    x: 0
                    y: parent.height / 2
                    width: parent.width
                    height: 1
                    color: Theme.focus
                    opacity: 0.56
                }
            }

'''
replace_once(
    "            Rectangle {\n                id: wallpaperFocalHandle\n",
    guide_overlay + "            Rectangle {\n                id: wallpaperFocalHandle\n",
    "guide overlay",
)

replace_once(
    "                height: 252 + ((root.elementPaletteOpen || root.backgroundPaletteOpen) ? 150 : 0)\n",
    "                height: 282 + ((root.elementPaletteOpen || root.backgroundPaletteOpen) ? 150 : 0)\n",
    "editor panel height",
)

preset_controls = r'''                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 7

                        Text {
                            text: "Layout"
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                        }
                        SettingsButton {
                            label: "Minimal"
                            textSize: 9
                            onClicked: root.applyLayoutPreset("minimal")
                        }
                        SettingsButton {
                            label: "Centered"
                            textSize: 9
                            onClicked: root.applyLayoutPreset("centered")
                        }
                        SettingsButton {
                            label: "Information"
                            textSize: 9
                            onClicked: root.applyLayoutPreset("information")
                        }
                        SettingsButton {
                            label: "Lower Third"
                            textSize: 9
                            onClicked: root.applyLayoutPreset("lower-third")
                        }
                        SettingsButton {
                            label: "Guides"
                            active: root.showEditorGrid
                            textSize: 9
                            onClicked: root.showEditorGrid = !root.showEditorGrid
                        }

                        Item { Layout.fillWidth: true }

                        Text {
                            text: "Presets change layout and visibility only."
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            elide: Text.ElideRight
                        }
                    }

'''
color_row = '''                    RowLayout {\n                        Layout.fillWidth: true\n                        spacing: 7\n\n                        Text {\n                            text: "Element color"\n'''
replace_once(
    color_row,
    preset_controls + color_row,
    "preset controls",
)

EDITOR.write_text(text)

digest = sha256(text.encode()).hexdigest()
entry = f"{digest}\t{MANAGED_PATH}"
history_lines = HISTORY.read_text().splitlines()
if entry not in history_lines:
    with HISTORY.open("a") as handle:
        if history_lines:
            handle.write("\n" if HISTORY.read_text() and not HISTORY.read_text().endswith("\n") else "")
        handle.write(entry + "\n")
