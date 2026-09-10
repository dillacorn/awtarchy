#!/usr/bin/env python3
from pathlib import Path

ROOT = Path('.')


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly one match, found {count}')
    return text.replace(old, new, 1)


def replace_count(text: str, old: str, new: str, expected: int, label: str) -> str:
    count = text.count(old)
    if count != expected:
        raise SystemExit(f'{label}: expected {expected} matches, found {count}')
    return text.replace(old, new)


# ---------------------------------------------------------------------------
# Lockscreen editor: picker suspension + compact contextual dock.
# ---------------------------------------------------------------------------
editor_path = ROOT / 'config/quickshell/awtarchy/LockscreenEditor.qml'
editor = editor_path.read_text()

editor = replace_once(
    editor,
    '''    readonly property bool open: editorWindow.visible
    readonly property var elementNames: ["logo", "time", "date", "username", "weather", "password"]''',
    '''    property bool editingActive: false
    readonly property bool open: editingActive
    property bool pickerSuspended: false
    property string activeDrawer: ""
    readonly property var elementNames: ["logo", "time", "date", "username", "weather", "password"]''',
    'editor logical open state',
)

editor = replace_once(
    editor,
    '''    function scheduleContrastRefresh() {
        if (!open)
            return;
        contrastRefreshPending = true;
        contrastRefreshDelay.restart();
    }''',
    '''    function scheduleContrastRefresh() {
        if (!open || pickerSuspended)
            return;
        contrastRefreshPending = true;
        contrastRefreshDelay.restart();
    }''',
    'editor contrast suspension',
)

old_lifecycle_start = editor.index('    function openForScreen(target) {')
old_lifecycle_end = editor.index('    function save() {', old_lifecycle_start)
new_lifecycle = '''    function toggleDrawer(name) {
        const allowed = ["element", "layout", "background", "weather"];
        if (allowed.indexOf(String(name || "")) < 0)
            return;
        activeDrawer = activeDrawer === name ? "" : name;
        if (activeDrawer !== "element")
            elementPaletteOpen = false;
        if (activeDrawer !== "background")
            backgroundPaletteOpen = false;
    }

    function openForScreen(target) {
        if (target)
            editorWindow.screen = target;
        loadPersistedDraft();
        undoStack = [];
        redoStack = [];
        historyTransactionActive = false;
        historyTransactionSnapshot = null;
        inertiaOwner = "";
        activeDrawer = "";
        pickerSuspended = false;
        editingActive = true;
        editorWindow.visible = true;
        FlyoutManager.claimOverlay("lockscreen-editor");
        scheduleContrastRefresh();
        Qt.callLater(() => editorFocus.forceActiveFocus());
    }

    function openFocused() {
        openForScreen(focusedScreen());
    }

    function suspendForWallpaperPicker() {
        if (!open || pickerSuspended || wallpaperPickerProcess.running)
            return;
        if (historyTransactionActive)
            commitHistoryTransaction();
        inertiaOwner = "";
        pickerSuspended = true;
        statusMessage = "Opening lockscreen wallpaper picker…";
        FlyoutManager.releaseOverlay("lockscreen-editor");
        editorWindow.visible = false;
        wallpaperPickerProcess.exec(["bash", wallpaperPickerBackend]);
    }

    function resumeAfterWallpaperPicker() {
        if (!open || !pickerSuspended)
            return;
        pickerSuspended = false;
        editorWindow.visible = true;
        FlyoutManager.claimOverlay("lockscreen-editor");
        scheduleContrastRefresh();
        Qt.callLater(() => editorFocus.forceActiveFocus());
    }

    function close() {
        heldSettle.stop();
        heldReleaseClear.stop();
        heldScaleAnimation.stop();
        heldElement = "";
        heldScaleBoost = 1.0;
        inertiaOwner = "";
        historyTransactionActive = false;
        historyTransactionSnapshot = null;
        clearGuides();
        activeDrawer = "";
        elementPaletteOpen = false;
        backgroundPaletteOpen = false;
        pickerSuspended = false;
        editingActive = false;
        FlyoutManager.releaseOverlay("lockscreen-editor");
        editorWindow.visible = false;
        loadPersistedDraft();
    }

'''
editor = editor[:old_lifecycle_start] + new_lifecycle + editor[old_lifecycle_end:]

editor = replace_once(
    editor,
    '''        onExited: (exitCode, exitStatus) => {
            if (root.open && exitCode !== 0 && root.statusMessage.length === 0)
                root.statusMessage = "Lockscreen wallpaper picker closed";
        }''',
    '''        onExited: (exitCode, exitStatus) => {
            if (root.open && exitCode !== 0)
                root.statusMessage = "Lockscreen wallpaper picker closed without a selection";
            else if (root.open
                    && root.statusMessage === "Opening lockscreen wallpaper picker…")
                root.statusMessage = "No wallpaper selected.";
            root.resumeAfterWallpaperPicker();
        }''',
    'picker resume callback',
)

editor = replace_once(
    editor,
    '        enabled: root.open\n        autoRepeat: false\n        onActivated: root.close()',
    '        enabled: root.open && !root.pickerSuspended\n        autoRepeat: false\n        onActivated: root.close()',
    'escape suspension guard',
)
editor = replace_once(
    editor,
    '        enabled: root.open && root.undoStack.length > 0',
    '        enabled: root.open && !root.pickerSuspended && root.undoStack.length > 0',
    'undo suspension guard',
)
editor = replace_count(
    editor,
    '        enabled: root.open && root.redoStack.length > 0',
    '        enabled: root.open && !root.pickerSuspended && root.redoStack.length > 0',
    2,
    'redo suspension guards',
)
editor = replace_once(
    editor,
    '                        running: root.open && parent.inertiaActive\n                            && root.inertiaOwner === parent.elementName',
    '                        running: root.open && !root.pickerSuspended && parent.inertiaActive\n                            && root.inertiaOwner === parent.elementName',
    'inertia suspension guard',
)

panel_marker = '''            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 282 + ((root.elementPaletteOpen || root.backgroundPaletteOpen) ? 150 : 0)'''
panel_start = editor.index(panel_marker)
panel_end = editor.rfind('\n        }\n    }\n}')
if panel_end <= panel_start:
    raise SystemExit('editor dock: could not locate final panel boundary')

new_panel = '''            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: editorDockContent.implicitHeight + 18
                color: Theme.popupBackground
                border.width: 1
                border.color: Theme.muted
                z: 300

                ColumnLayout {
                    id: editorDockContent
                    anchors.fill: parent
                    anchors.margins: 9
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 7

                        Text {
                            text: root.elementLabel(root.selectedElement)
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.bold: true
                        }

                        SettingsButton {
                            label: root.selectedElement === "logo"
                                ? (root.elementEnabled("logo") ? "Logo visible" : "Logo hidden")
                                : root.elementCanHide(root.selectedElement)
                                    ? (root.elementEnabled(root.selectedElement) ? "Visible" : "Hidden")
                                    : "Always visible"
                            active: root.elementEnabled(root.selectedElement)
                            available: root.elementCanHide(root.selectedElement)
                            textSize: 9
                            onClicked: root.setDraftVisible(root.selectedElement,
                                !root.elementEnabled(root.selectedElement))
                        }

                        Text { text: "Scale"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 9 }
                        SettingsButton {
                            label: "−"
                            available: root.elementScale(root.selectedElement) > 0.50
                            textSize: 10
                            onClicked: root.setDraftScale(root.selectedElement,
                                root.elementScale(root.selectedElement) - 0.10)
                        }
                        Text {
                            text: Math.round(root.elementScale(root.selectedElement) * 100) + "%"
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            Layout.preferredWidth: 42
                            horizontalAlignment: Text.AlignHCenter
                        }
                        SettingsButton {
                            label: "+"
                            available: root.elementScale(root.selectedElement) < 2.00
                            textSize: 10
                            onClicked: root.setDraftScale(root.selectedElement,
                                root.elementScale(root.selectedElement) + 0.10)
                        }

                        Text { text: "X"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 9 }
                        TextField {
                            id: positionXField
                            Layout.preferredWidth: 54
                            text: Number(root.primaryPoint().x * 100).toFixed(1)
                            validator: DoubleValidator { bottom: 0; top: 100; decimals: 1 }
                            selectByMouse: true
                            font.pixelSize: 9
                            onEditingFinished: root.setSelectedCoordinate("x", text)
                        }
                        Text { text: "Y"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 9 }
                        TextField {
                            id: positionYField
                            Layout.preferredWidth: 54
                            text: Number(root.primaryPoint().y * 100).toFixed(1)
                            validator: DoubleValidator { bottom: 0; top: 100; decimals: 1 }
                            selectByMouse: true
                            font.pixelSize: 9
                            onEditingFinished: root.setSelectedCoordinate("y", text)
                        }

                        SettingsButton { label: "Undo"; textSize: 9; available: root.undoStack.length > 0; onClicked: root.undo() }
                        SettingsButton { label: "Redo"; textSize: 9; available: root.redoStack.length > 0; onClicked: root.redo() }

                        SettingsButton { label: "Element"; active: root.activeDrawer === "element"; textSize: 9; onClicked: root.toggleDrawer("element") }
                        SettingsButton { label: "Layout"; active: root.activeDrawer === "layout"; textSize: 9; onClicked: root.toggleDrawer("layout") }
                        SettingsButton { label: "Background"; active: root.activeDrawer === "background"; textSize: 9; onClicked: root.toggleDrawer("background") }
                        SettingsButton { label: "Weather"; active: root.activeDrawer === "weather"; textSize: 9; onClicked: root.toggleDrawer("weather") }

                        Item { Layout.fillWidth: true }

                        Text {
                            visible: root.statusMessage.length > 0
                            text: root.statusMessage.length > 0 ? root.statusMessage : "Password cannot be hidden."
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            elide: Text.ElideRight
                            Layout.maximumWidth: 260
                        }

                        SettingsButton { label: "Cancel"; textSize: 9; onClicked: root.close() }
                        SettingsButton {
                            label: "Save"
                            active: true
                            textSize: 9
                            available: !saveProcess.running && !contrastPersistProcess.running
                            onClicked: root.save()
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 7
                        visible: root.activeDrawer === "element"

                        SettingsButton {
                            label: "Reset Position"
                            textSize: 9
                            onClicked: root.resetElementPosition(root.selectedElement)
                        }
                        Text { text: "Element color"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 9 }
                        SettingsButton { label: "Auto"; active: root.elementColor(root.selectedElement) === "auto"; textSize: 9; onClicked: root.setDraftColor(root.selectedElement, "auto") }
                        SettingsButton { label: "White"; active: root.elementColor(root.selectedElement) === "#ffffff"; textSize: 9; onClicked: root.setDraftColor(root.selectedElement, "#ffffff") }
                        SettingsButton { label: "Black"; active: root.elementColor(root.selectedElement) === "#000000"; textSize: 9; onClicked: root.setDraftColor(root.selectedElement, "#000000") }
                        SettingsButton {
                            label: "Custom"
                            active: root.elementPaletteOpen
                            textSize: 9
                            onClicked: {
                                root.elementPaletteOpen = !root.elementPaletteOpen;
                                if (root.elementPaletteOpen)
                                    root.backgroundPaletteOpen = false;
                            }
                        }
                        Text { text: "All:"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 9 }
                        SettingsButton { label: "Auto All"; textSize: 9; onClicked: root.setAllDraftColors("auto") }
                        SettingsButton { label: "White All"; textSize: 9; onClicked: root.setAllDraftColors("#ffffff") }
                        SettingsButton { label: "Black All"; textSize: 9; onClicked: root.setAllDraftColors("#000000") }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: "Password cannot be hidden. Auto samples each element independently."
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            elide: Text.ElideRight
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 7
                        visible: root.activeDrawer === "layout"

                        SettingsButton { label: "Minimal"; textSize: 9; onClicked: root.applyLayoutPreset("minimal") }
                        SettingsButton { label: "Centered"; textSize: 9; onClicked: root.applyLayoutPreset("centered") }
                        SettingsButton { label: "Information"; textSize: 9; onClicked: root.applyLayoutPreset("information") }
                        SettingsButton { label: "Lower Third"; textSize: 9; onClicked: root.applyLayoutPreset("lower-third") }
                        SettingsButton { label: "Guides"; active: root.showEditorGrid; textSize: 9; onClicked: root.showEditorGrid = !root.showEditorGrid }
                        SettingsButton { label: "Restore Defaults"; textSize: 9; onClicked: root.resetDraft() }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: "Presets change layout and visibility only."
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            elide: Text.ElideRight
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 7
                        visible: root.activeDrawer === "background"

                        SettingsButton { label: "Black"; active: root.draftBackgroundMode === "black"; textSize: 9; onClicked: root.setDraftBackgroundMode("black") }
                        SettingsButton {
                            label: "Wallpaper"
                            active: root.draftBackgroundMode === "wallpaper"
                            textSize: 9
                            onClicked: {
                                if (root.draftWallpaperPath.length > 0)
                                    root.setDraftBackgroundMode("wallpaper");
                                else
                                    root.suspendForWallpaperPicker();
                            }
                        }
                        SettingsButton {
                            label: "Choose Wallpaper"
                            textSize: 9
                            available: !wallpaperPickerProcess.running
                            onClicked: root.suspendForWallpaperPicker()
                        }
                        SettingsButton {
                            label: "Color"
                            active: root.draftBackgroundMode === "color"
                            textSize: 9
                            onClicked: {
                                root.setDraftBackgroundMode("color");
                                root.backgroundPaletteOpen = true;
                                root.elementPaletteOpen = false;
                            }
                        }
                        SettingsButton {
                            label: "Palette"
                            active: root.backgroundPaletteOpen
                            textSize: 9
                            onClicked: {
                                root.backgroundPaletteOpen = !root.backgroundPaletteOpen;
                                if (root.backgroundPaletteOpen)
                                    root.elementPaletteOpen = false;
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: root.draftWallpaperPath.length > 0
                                ? "Lockscreen wallpaper: " + root.draftWallpaperPath.split("/").pop()
                                : "Lockscreen wallpaper is independent from the desktop."
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            elide: Text.ElideMiddle
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 7
                        visible: root.activeDrawer === "background"

                        Text { text: "Fit"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 9 }
                        SettingsButton { label: "Cover"; active: root.draftWallpaperFit === "cover"; available: root.draftWallpaperPath.length > 0; textSize: 9; onClicked: root.setDraftWallpaperFit("cover") }
                        SettingsButton { label: "Contain"; active: root.draftWallpaperFit === "contain"; available: root.draftWallpaperPath.length > 0; textSize: 9; onClicked: root.setDraftWallpaperFit("contain") }
                        Text { text: "Overlay"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 9 }
                        SettingsButton { label: "None"; active: root.draftOverlayMode === "none"; textSize: 9; onClicked: root.setDraftOverlay("none", root.draftOverlayStrength) }
                        SettingsButton { label: "Darken"; active: root.draftOverlayMode === "dark"; textSize: 9; onClicked: root.setDraftOverlay("dark", root.draftOverlayStrength > 0 ? root.draftOverlayStrength : 35) }
                        SettingsButton { label: "Lighten"; active: root.draftOverlayMode === "light"; textSize: 9; onClicked: root.setDraftOverlay("light", root.draftOverlayStrength > 0 ? root.draftOverlayStrength : 35) }
                        Slider {
                            id: overlaySlider
                            Layout.preferredWidth: 120
                            from: 0; to: 100; stepSize: 1
                            value: root.draftOverlayStrength
                            onPressedChanged: { if (pressed) root.beginHistoryTransaction(); else root.commitHistoryTransaction(); }
                            onMoved: root.setDraftOverlay(root.draftOverlayMode, value)
                        }
                        Text { text: root.draftOverlayStrength + "%"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: 9; Layout.preferredWidth: 34 }
                        Text { text: "Blur"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 9 }
                        Slider {
                            id: blurSlider
                            Layout.preferredWidth: 110
                            from: 0; to: 100; stepSize: 1
                            value: root.draftWallpaperBlur
                            enabled: root.draftBackgroundMode === "wallpaper"
                            onPressedChanged: { if (pressed) root.beginHistoryTransaction(); else root.commitHistoryTransaction(); }
                            onMoved: root.setDraftWallpaperBlur(value)
                        }
                        Text { text: root.draftWallpaperBlur + "%"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: 9; Layout.preferredWidth: 34 }
                        Item { Layout.fillWidth: true }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 7
                        visible: root.activeDrawer === "weather"

                        Text { text: "Weather units"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 9 }
                        SettingsButton { label: "Auto"; active: root.draftWeatherUnits === "auto"; textSize: 9; onClicked: root.setDraftWeatherUnits("auto") }
                        SettingsButton { label: "°F"; active: root.draftWeatherUnits === "fahrenheit"; textSize: 9; onClicked: root.setDraftWeatherUnits("fahrenheit") }
                        SettingsButton { label: "°C"; active: root.draftWeatherUnits === "celsius"; textSize: 9; onClicked: root.setDraftWeatherUnits("celsius") }
                        Item { Layout.fillWidth: true }
                        Text { text: "Auto follows the system measurement locale."; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 9; elide: Text.ElideRight }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: visible ? 142 : 0
                        spacing: 12
                        visible: (root.activeDrawer === "element" && root.elementPaletteOpen)
                            || (root.activeDrawer === "background" && root.backgroundPaletteOpen)

                        InlineColorPicker {
                            id: elementColorPicker
                            visible: root.activeDrawer === "element" && root.elementPaletteOpen
                            Layout.preferredWidth: 320
                            Layout.preferredHeight: visible ? 142 : 0
                            colorValue: root.elementColor(root.selectedElement) === "auto"
                                ? String(root.draftAutoAccents[root.selectedElement] || "#ffffff")
                                : root.elementColor(root.selectedElement)
                            onColorEdited: hex => root.setDraftColor(root.selectedElement, hex)
                        }

                        InlineColorPicker {
                            id: backgroundColorPicker
                            visible: root.activeDrawer === "background" && root.backgroundPaletteOpen
                            Layout.preferredWidth: 320
                            Layout.preferredHeight: visible ? 142 : 0
                            colorValue: root.draftBackgroundColor
                            onColorEdited: hex => root.setDraftBackgroundColor(hex)
                        }

                        Item { Layout.fillWidth: true }
                    }
                }
            }'''

editor = editor[:panel_start] + new_panel + editor[panel_end:]
editor_path.write_text(editor)


# ---------------------------------------------------------------------------
# Quick Settings: one compact Awtarchy edit hub with Cursor + Lockscreen menus.
# ---------------------------------------------------------------------------
quick_path = ROOT / 'config/quickshell/awtarchy/QuickSettings.qml'
quick = quick_path.read_text()
quick = replace_once(
    quick,
    '''    property bool barVisibilityOpen: false
    property bool lockscreenSectionExpanded: false''',
    '''    property bool barVisibilityOpen: false
    property bool awtarchyEditMode: false
    property bool cursorSectionExpanded: false
    property bool lockscreenSectionExpanded: false''',
    'Awtarchy edit state',
)

awt_start_marker = '''                        Rectangle {
                            Layout.row: root.quickSettingsSectionRow("awtarchy")'''
awt_end_marker = '''                        Rectangle {
                            Layout.row: root.quickSettingsSectionRow("smtty")'''
awt_start = quick.index(awt_start_marker)
awt_end = quick.index(awt_end_marker, awt_start)
new_awtarchy_section = '''                        Rectangle {
                            Layout.row: root.quickSettingsSectionRow("awtarchy")
                            visible: root.quickSettingsSectionVisible("awtarchy")
                            Layout.fillWidth: true
                            Layout.preferredHeight: awtarchyContent.implicitHeight + 16
                            color: Theme.popupButton
                            border.width: 1
                            border.color: Theme.active

                            ColumnLayout {
                                id: awtarchyContent
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 5

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Awtarchy"
                                        color: Theme.foreground
                                        font.family: Theme.fontFamily
                                        font.pixelSize: root.scaledText(11)
                                        font.bold: true
                                    }
                                    SettingsButton {
                                        label: "Awtarchy Tips"
                                        textSize: root.scaledText(9)
                                        onClicked: root.openAwtarchyTips()
                                    }
                                    SettingsButton {
                                        label: root.awtarchyEditMode ? "Done" : "Edit"
                                        active: root.awtarchyEditMode
                                        textSize: root.scaledText(9)
                                        onClicked: {
                                            root.awtarchyEditMode = !root.awtarchyEditMode;
                                            if (!root.awtarchyEditMode) {
                                                root.cursorSectionExpanded = false;
                                                root.lockscreenSectionExpanded = false;
                                            }
                                        }
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    visible: !root.awtarchyEditMode
                                    text: "Built-in manual and Awtarchy desktop preferences."
                                    color: Theme.muted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: root.scaledText(8)
                                    wrapMode: Text.Wrap
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    visible: root.awtarchyEditMode

                                    Text {
                                        Layout.fillWidth: true
                                        text: "Cursor"
                                        color: Theme.foreground
                                        font.family: Theme.fontFamily
                                        font.pixelSize: root.scaledText(9)
                                        font.bold: true
                                    }
                                    SettingsButton {
                                        label: root.cursorSectionExpanded ? "Collapse" : "Expand"
                                        active: root.cursorSectionExpanded
                                        textSize: root.scaledText(9)
                                        onClicked: root.cursorSectionExpanded = !root.cursorSectionExpanded
                                    }
                                }

                                CursorThemeSettings {
                                    id: awtarchyCursorThemeSection
                                    Layout.fillWidth: true
                                    visible: root.awtarchyEditMode && root.cursorSectionExpanded
                                    active: visible && quickSettingsWindow.visible
                                        && !root.settingsOpen
                                        && root.quickSettingsSectionVisible("awtarchy")
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    visible: root.awtarchyEditMode

                                    Text {
                                        Layout.fillWidth: true
                                        text: "Lockscreen"
                                        color: Theme.foreground
                                        font.family: Theme.fontFamily
                                        font.pixelSize: root.scaledText(9)
                                        font.bold: true
                                    }
                                    Text {
                                        text: BarState.lockscreenAnimationPreference()
                                        color: Theme.muted
                                        font.family: Theme.fontFamily
                                        font.pixelSize: root.scaledText(8)
                                    }
                                    SettingsButton {
                                        label: root.lockscreenSectionExpanded ? "Collapse" : "Expand"
                                        active: root.lockscreenSectionExpanded
                                        textSize: root.scaledText(9)
                                        onClicked: root.lockscreenSectionExpanded = !root.lockscreenSectionExpanded
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    visible: root.awtarchyEditMode && root.lockscreenSectionExpanded
                                    spacing: 5

                                    Text {
                                        Layout.fillWidth: true
                                        text: "Lockscreen Animation"
                                        color: Theme.foreground
                                        font.family: Theme.fontFamily
                                        font.pixelSize: root.scaledText(9)
                                        font.bold: true
                                    }

                                    Flow {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: childrenRect.height
                                        spacing: 5

                                        Repeater {
                                            model: BarState.lockscreenAnimationPresets

                                            SettingsButton {
                                                required property var modelData
                                                label: String(modelData.label)
                                                active: BarState.lockscreenAnimationPreference()
                                                    === String(modelData.key)
                                                textSize: root.scaledText(9)
                                                onClicked: root.queueStateCommand([
                                                    "set-lockscreen-animation", String(modelData.key)
                                                ])
                                            }
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6
                                        SettingsButton {
                                            label: "Edit Layout"
                                            active: true
                                            textSize: root.scaledText(9)
                                            onClicked: root.openLockscreenEditor()
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: "Drag, resize, show/hide, recolor, and compose the lockscreen on the focused display"
                                            color: Theme.muted
                                            font.family: Theme.fontFamily
                                            font.pixelSize: root.scaledText(8)
                                            wrapMode: Text.Wrap
                                        }
                                    }

                                    Text { Layout.fillWidth: true; text: "Background"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: root.scaledText(9) }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 5
                                        SettingsButton {
                                            label: "Black"
                                            active: BarState.lockscreenBackground() === "black"
                                            textSize: root.scaledText(9)
                                            onClicked: root.queueStateCommand(["set-lockscreen-background", "black"])
                                        }
                                        SettingsButton {
                                            label: "Wallpaper"
                                            active: BarState.lockscreenBackground() === "wallpaper"
                                            textSize: root.scaledText(9)
                                            onClicked: root.queueStateCommand(["set-lockscreen-background", "wallpaper"])
                                        }
                                        Item { Layout.fillWidth: true }
                                    }

                                    GridLayout {
                                        Layout.fillWidth: true
                                        columns: 2
                                        columnSpacing: 8
                                        rowSpacing: 4

                                        Text { Layout.fillWidth: true; text: "Mouse Interaction"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: root.scaledText(9) }
                                        SettingsButton { label: BarState.lockscreenMouseInteractiveEnabled() ? "On" : "Off"; active: BarState.lockscreenMouseInteractiveEnabled(); textSize: root.scaledText(9); onClicked: root.queueStateCommand(["set-lockscreen-mouse-interactive", BarState.lockscreenMouseInteractiveEnabled() ? "false" : "true"]) }
                                        Text { Layout.fillWidth: true; text: "Audio Reactive"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: root.scaledText(9) }
                                        SettingsButton { label: BarState.lockscreenAudioReactiveEnabled() ? "On" : "Off"; active: BarState.lockscreenAudioReactiveEnabled(); textSize: root.scaledText(9); onClicked: root.queueStateCommand(["set-lockscreen-audio-reactive", BarState.lockscreenAudioReactiveEnabled() ? "false" : "true"]) }
                                    }

                                    Text { Layout.fillWidth: true; text: "Location override (optional)"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: root.scaledText(9); font.bold: true }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 5
                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 28
                                            color: Theme.popupBackground
                                            border.width: 1
                                            border.color: lockscreenWeatherLocationInput.activeFocus ? Theme.focus : Theme.active
                                            TextInput {
                                                id: lockscreenWeatherLocationInput
                                                anchors.fill: parent
                                                anchors.margins: 6
                                                text: root.lockscreenWeatherLocationDraft
                                                maximumLength: 96
                                                color: Theme.foreground
                                                selectionColor: Theme.focus
                                                selectedTextColor: Theme.background
                                                font.family: Theme.fontFamily
                                                font.pixelSize: root.scaledText(9)
                                                clip: true
                                                onTextChanged: root.lockscreenWeatherLocationDraft = text
                                                Keys.onReturnPressed: event => { root.saveLockscreenWeatherLocation(); event.accepted = true; }
                                            }
                                        }
                                        SettingsButton { label: "Save Location"; textSize: root.scaledText(9); onClicked: root.saveLockscreenWeatherLocation() }
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        visible: root.lockscreenWeatherLocationError.length > 0
                                        text: root.lockscreenWeatherLocationError
                                        color: Theme.error
                                        font.family: Theme.fontFamily
                                        font.pixelSize: root.scaledText(8)
                                        wrapMode: Text.Wrap
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Automatic location uses your approximate public-IP location from ipwho.is, then sends coordinates to Open-Meteo. Enter a location above only to override it."
                                        color: Theme.muted
                                        font.family: Theme.fontFamily
                                        font.pixelSize: root.scaledText(8)
                                        wrapMode: Text.Wrap
                                    }
                                    SettingsButton { label: "Restore Awtarchy Defaults"; textSize: root.scaledText(9); onClicked: root.resetLockscreenPresentation() }
                                }
                            }
                        }

'''
quick = quick[:awt_start] + new_awtarchy_section + quick[awt_end:]
quick_path.write_text(quick)


# ---------------------------------------------------------------------------
# Generic Quick Settings cog: remove duplicate cursor controls.
# ---------------------------------------------------------------------------
flyout_path = ROOT / 'config/quickshell/awtarchy/FlyoutSettings.qml'
flyout = flyout_path.read_text()
flyout = replace_once(
    flyout,
    '''    implicitHeight: inlineCopy
        ? 139 + displayScaleSection.implicitHeight
            + cursorThemeSection.implicitHeight
            + quickSettingsSectionControls.implicitHeight + 3 + (copyOpen ? 31 : 0)
        : (copyOpen ? 104 : 139)''',
    '''    implicitHeight: inlineCopy
        ? 139 + displayScaleSection.implicitHeight
            + quickSettingsSectionControls.implicitHeight + 3 + (copyOpen ? 31 : 0)
        : (copyOpen ? 104 : 139)''',
    'generic settings cursor height',
)
flyout = replace_once(
    flyout,
    '''        CursorThemeSettings {
            id: cursorThemeSection
            Layout.fillWidth: true
            visible: root.surfaceLabel === "Quick Settings"
            active: visible
        }

''',
    '',
    'generic settings cursor block',
)
flyout_path.write_text(flyout)


# ---------------------------------------------------------------------------
# Logo interaction: per-block local deformation + soft orthogonal cohesion.
# Keep connected groups for formation-readiness and audio only.
# ---------------------------------------------------------------------------
scene_paths = [
    ROOT / 'config/quickshell/awtarchy-lock/LockScene.qml',
    ROOT / 'config/quickshell/awtarchy/LockPreviewScene.qml',
]
if scene_paths[0].read_text() != scene_paths[1].read_text():
    raise SystemExit('secure and preview scenes diverged before runtime-polish patch')

scene = scene_paths[0].read_text()
scene = replace_once(
    scene,
    '''    readonly property int pointerResponseDurationMs: 100
    readonly property int pointerReturnDurationMs: 180
    readonly property var logoCohesionGroups: buildLogoCohesionGroups()''',
    '''    readonly property int pointerResponseDurationMs: 100
    readonly property int pointerReturnDurationMs: 180
    readonly property real pointerNeighborCohesion: 0.30
    readonly property var logoCohesionGroups: buildLogoCohesionGroups()''',
    'neighbor cohesion property',
)

physics_start = scene.index('    function radialFieldOffset(group, fieldX, fieldY, strength, radius, cap) {')
physics_end = scene.index('    function logoGroupAudioOffset(group) {', physics_start)
new_physics = '''    function radialPointOffset(centerX, centerY, seed, fieldX, fieldY, strength, radius, cap) {
        if (strength <= 0 || radius <= 0 || cap <= 0)
            return ({ x: 0, y: 0 });

        let dx = centerX - fieldX;
        let dy = centerY - fieldY;
        let distance = Math.sqrt(dx * dx + dy * dy);
        if (distance >= radius)
            return ({ x: 0, y: 0 });
        if (distance < 0.001) {
            const angle = (seed + 1) * 2.399963229728653;
            dx = Math.cos(angle);
            dy = Math.sin(angle);
            distance = 1;
        }

        const raw = Math.max(0, Math.min(1, 1 - distance / radius));
        const proximity = raw * raw * (3 - 2 * raw);
        const magnitude = cap * proximity * Math.max(0, Math.min(1, strength));
        return ({
            x: dx / distance * magnitude,
            y: dy / distance * magnitude
        });
    }

    function directCellDeformationOffset(row, column) {
        if (!isFilledWordmarkCell(row, column))
            return ({ x: 0, y: 0 });
        const centerX = (column + 0.5) * wordmarkCellWidth;
        const centerY = (row + 0.5) * wordmarkCellHeight;
        const seed = row * wordmarkColumns + column;
        const pointer = pointerEffectsEnabled
            ? radialPointOffset(centerX, centerY, seed,
                pointerFieldX, pointerFieldY, pointerFieldStrength,
                pointerInfluenceRadius, pointerDisplacementCap)
            : ({ x: 0, y: 0 });
        const click = mouseInteractive
            ? radialPointOffset(centerX, centerY, seed,
                clickFieldX, clickFieldY, clickFieldStrength,
                clickInfluenceRadius, clickDisplacementCap)
            : ({ x: 0, y: 0 });
        return ({
            x: Math.max(-clickDisplacementCap,
                Math.min(clickDisplacementCap, pointer.x + click.x)),
            y: Math.max(-clickDisplacementCap,
                Math.min(clickDisplacementCap, pointer.y + click.y))
        });
    }

    function neighborCellDeformationOffset(row, column) {
        const neighbors = [
            ({ row: row, column: column - 1 }),
            ({ row: row, column: column + 1 }),
            ({ row: row - 1, column: column }),
            ({ row: row + 1, column: column })
        ];
        let sumX = 0;
        let sumY = 0;
        let count = 0;
        for (let i = 0; i < neighbors.length; ++i) {
            const neighbor = neighbors[i];
            if (!isFilledWordmarkCell(neighbor.row, neighbor.column))
                continue;
            const offset = directCellDeformationOffset(neighbor.row, neighbor.column);
            sumX += offset.x;
            sumY += offset.y;
            ++count;
        }
        if (count === 0)
            return ({ x: 0, y: 0 });
        return ({
            x: sumX / count * pointerNeighborCohesion,
            y: sumY / count * pointerNeighborCohesion
        });
    }

    function logoCellDeformationOffset(row, column) {
        const direct = directCellDeformationOffset(row, column);
        const neighbor = neighborCellDeformationOffset(row, column);
        return ({
            x: Math.max(-clickDisplacementCap,
                Math.min(clickDisplacementCap, direct.x + neighbor.x)),
            y: Math.max(-clickDisplacementCap,
                Math.min(clickDisplacementCap, direct.y + neighbor.y))
        });
    }

'''
scene = scene[:physics_start] + new_physics + scene[physics_end:]
scene = replace_once(
    scene,
    '''                            readonly property var pointerTarget: cohesionReady
                                ? root.logoDeformationOffset(cohesionGroup) : ({ x: 0, y: 0 })''',
    '''                            readonly property var pointerTarget: cohesionReady
                                ? root.logoCellDeformationOffset(wordmarkRow.rowIndex, columnIndex)
                                : ({ x: 0, y: 0 })''',
    'per-cell pointer target',
)
for path in scene_paths:
    path.write_text(scene)


# ---------------------------------------------------------------------------
# Tests: align intentional ownership/physics changes.
# ---------------------------------------------------------------------------
bibata_path = ROOT / 'tests/test-bibata-cursor-migration.sh'
bibata = bibata_path.read_text()
bibata = replace_once(
    bibata,
    '''# Quick Settings must expose the Bibata selector in both supported settings surfaces.
contains "$FLYOUT" 'CursorThemeSettings {' \\
  'Quick Settings settings panel does not host the cursor selector'
contains "$FLYOUT" 'cursorThemeSection.implicitHeight' \\
  'Quick Settings cursor selector height is not included in panel sizing' ''',
    '''# Cursor preferences belong to the Awtarchy card only; the generic Quick
# Settings cog must not duplicate them.
not_contains "$FLYOUT" 'CursorThemeSettings {' \\
  'generic Quick Settings settings panel still duplicates the cursor selector'
not_contains "$FLYOUT" 'cursorThemeSection.implicitHeight' \\
  'generic Quick Settings settings panel still reserves cursor-selector height' ''',
    'cursor ownership regression',
)
bibata_path.write_text(bibata)

cohesion_path = ROOT / 'tests/test-quickshell-lockscreen-logo-cohesion.sh'
cohesion = cohesion_path.read_text()
cohesion = replace_once(
    cohesion,
    '''# The connector experiment still exposed every rectangular cell while moving.
# The corrected model keeps connected glyph regions moving coherently instead.''',
    '''# Pointer interaction is intentionally softer than rigid connected-letter
# motion: each filled block gets a local target and neighboring blocks contribute
# a smaller cohesion term so the wordmark stretches and reforms without bridges.''',
    'logo cohesion test description',
)
cohesion = replace_once(
    cohesion,
    '''require_text "$SCENE" 'function logoDeformationOffset(' \\
    'logo does not calculate a shared radial deformation target' ''',
    '''require_text "$SCENE" 'function directCellDeformationOffset(row, column)' \\
    'logo does not calculate direct per-block pointer deformation'
require_text "$SCENE" 'function neighborCellDeformationOffset(row, column)' \\
    'logo does not blend neighboring block deformation'
require_text "$SCENE" 'function logoCellDeformationOffset(row, column)' \\
    'logo does not calculate the final gooey per-block deformation target'
require_text "$SCENE" 'root.logoCellDeformationOffset(wordmarkRow.rowIndex, columnIndex)' \\
    'wordmark blocks do not consume their local deformation target'
reject_text "$SCENE" 'root.logoDeformationOffset(cohesionGroup)' \\
    'wordmark blocks still share one rigid connected-group pointer target' ''',
    'logo local deformation contract',
)
cohesion_path.write_text(cohesion)


# ---------------------------------------------------------------------------
# Managed-history: append exact new stock bytes for every changed managed file.
# ---------------------------------------------------------------------------
history_path = ROOT / 'local/share/awtarchy/quickshell-managed-history.sha256'
history = history_path.read_text()
managed = [
    ('config/quickshell/awtarchy/QuickSettings.qml', '.config/quickshell/awtarchy/QuickSettings.qml'),
    ('config/quickshell/awtarchy/FlyoutSettings.qml', '.config/quickshell/awtarchy/FlyoutSettings.qml'),
    ('config/quickshell/awtarchy/LockscreenEditor.qml', '.config/quickshell/awtarchy/LockscreenEditor.qml'),
    ('config/quickshell/awtarchy/LockPreviewScene.qml', '.config/quickshell/awtarchy/LockPreviewScene.qml'),
    ('config/quickshell/awtarchy-lock/LockScene.qml', '.config/quickshell/awtarchy-lock/LockScene.qml'),
]
import hashlib
for source, installed in managed:
    digest = hashlib.sha256((ROOT / source).read_bytes()).hexdigest()
    entry = f'{digest}\t{installed}'
    if entry not in history.splitlines():
        if history and not history.endswith('\n'):
            history += '\n'
        history += entry + '\n'
history_path.write_text(history)
