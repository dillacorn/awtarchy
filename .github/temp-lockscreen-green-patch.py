from pathlib import Path
import hashlib


def replace_once(path, old, new):
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one match, found {count}: {old[:120]!r}")
    p.write_text(text.replace(old, new, 1))


selector = r'''pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

FocusScope {
    id: root

    property var model: []
    property int currentIndex: 0
    property bool menuOpen: false
    property int highlightedIndex: currentIndex
    property Item popupBoundary: null
    signal activated(int index)

    readonly property string currentLabel: model && currentIndex >= 0 && currentIndex < model.length
        ? String(model[currentIndex].label || model[currentIndex].key || "") : ""
    readonly property bool directClockToggle: model && model.length === 2
        && String(model[0].key || "") === "24h"
        && String(model[1].key || "") === "12h"
    readonly property bool flyoutOpensUpward: {
        if (!popupBoundary)
            return false;
        const controlTop = root.mapToItem(popupBoundary, 0, 0).y;
        const controlBottom = controlTop + root.height;
        const availableBelow = Math.max(0, popupBoundary.height - controlBottom);
        const availableAbove = Math.max(0, controlTop);
        if (availableBelow >= flyout.height)
            return false;
        return availableAbove > availableBelow;
    }

    implicitWidth: 180
    implicitHeight: 28

    function normalizedIndex(index) {
        if (!model || model.length === 0)
            return -1;
        return Math.max(0, Math.min(model.length - 1, Number(index)));
    }

    function activateIndex(index) {
        const next = normalizedIndex(index);
        if (next < 0)
            return;
        currentIndex = next;
        highlightedIndex = next;
        activated(next);
        closeMenu();
    }

    function openMenu() {
        if (!model || model.length === 0)
            return;
        highlightedIndex = normalizedIndex(currentIndex);
        menuOpen = true;
        flyout.anchor.updateAnchor();
        flyout.visible = true;
        Qt.callLater(() => popupFocus.forceActiveFocus());
    }

    function closeMenu() {
        menuOpen = false;
        flyout.visible = false;
        Qt.callLater(() => root.forceActiveFocus());
    }

    function moveHighlight(delta) {
        if (!model || model.length === 0)
            return;
        const base = highlightedIndex >= 0 ? highlightedIndex : normalizedIndex(currentIndex);
        highlightedIndex = (base + delta + model.length) % model.length;
        Qt.callLater(() => optionFlick.ensureVisible(highlightedIndex));
    }

    function activateHighlighted() {
        activateIndex(highlightedIndex);
    }

    function toggleClockFormat() {
        activateIndex(currentIndex === 0 ? 1 : 0);
    }

    onCurrentIndexChanged: {
        if (!menuOpen)
            highlightedIndex = normalizedIndex(currentIndex);
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (directClockToggle)
                toggleClockFormat();
            else
                openMenu();
            event.accepted = true;
        } else if (event.key === Qt.Key_Down) {
            openMenu();
            event.accepted = true;
        }
    }
    Keys.onEscapePressed: event => {
        if (menuOpen) {
            closeMenu();
            event.accepted = true;
        }
    }

    Rectangle {
        id: closedControl
        anchors.fill: parent
        color: closedMouse.containsMouse || root.activeFocus ? Theme.hover : Theme.surface
        border.width: 1
        border.color: root.menuOpen || root.activeFocus ? Theme.focus : Theme.muted
        radius: 4

        Text {
            anchors.left: parent.left
            anchors.right: indicator.left
            anchors.leftMargin: 9
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            text: root.currentLabel
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: 9
            elide: Text.ElideRight
        }

        Text {
            id: indicator
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: root.directClockToggle ? "↔" : (root.menuOpen ? "▴" : "▾")
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: 9
        }

        MouseArea {
            id: closedMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                root.forceActiveFocus();
                if (root.directClockToggle)
                    root.toggleClockFormat();
                else if (root.menuOpen)
                    root.closeMenu();
                else
                    root.openMenu();
            }
        }
    }

    PopupWindow {
        id: flyout
        visible: false
        color: "transparent"
        grabFocus: true
        implicitWidth: Math.max(160, root.width)
        implicitHeight: Math.min(320, Math.max(32,
            (root.model && root.model.length > 0 ? root.model.length : 1) * 28 + 8))

        anchor.item: root
        anchor.edges: root.flyoutOpensUpward
            ? Edges.Top | Edges.Left
            : Edges.Bottom | Edges.Left
        anchor.gravity: root.flyoutOpensUpward
            ? Edges.Top | Edges.Right
            : Edges.Bottom | Edges.Right
        anchor.adjustment: PopupAdjustment.All

        onVisibleChanged: {
            if (!visible && root.menuOpen)
                root.menuOpen = false;
            if (visible)
                Qt.callLater(() => popupFocus.forceActiveFocus());
        }

        Rectangle {
            anchors.fill: parent
            color: Theme.popupBackground
            border.width: 1
            border.color: Theme.muted
            radius: 4

            FocusScope {
                id: popupFocus
                anchors.fill: parent
                focus: flyout.visible

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Up) {
                        root.moveHighlight(-1);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Down) {
                        root.moveHighlight(1);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                        root.activateHighlighted();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Escape) {
                        root.closeMenu();
                        event.accepted = true;
                    }
                }
                Keys.onEscapePressed: event => {
                    root.closeMenu();
                    event.accepted = true;
                }

                Flickable {
                    id: optionFlick
                    anchors.fill: parent
                    anchors.margins: 4
                    clip: true
                    contentWidth: width
                    contentHeight: optionColumn.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds

                    function ensureVisible(index) {
                        const top = index * 28;
                        const bottom = top + 28;
                        if (top < contentY)
                            contentY = top;
                        else if (bottom > contentY + height)
                            contentY = Math.max(0, bottom - height);
                    }

                    Column {
                        id: optionColumn
                        width: optionFlick.width

                        Repeater {
                            model: root.model || []

                            Rectangle {
                                required property int index
                                required property var modelData
                                width: optionColumn.width
                                height: 28
                                color: optionMouse.containsMouse || root.highlightedIndex === index
                                    ? Theme.hover : "transparent"

                                Text {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: String(parent.modelData.label || parent.modelData.key || "")
                                    color: parent.index === root.currentIndex ? Theme.focus : Theme.foreground
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                    elide: Text.ElideRight
                                }

                                MouseArea {
                                    id: optionMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onEntered: root.highlightedIndex = parent.index
                                    onClicked: root.activateIndex(parent.index)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
'''
Path("config/quickshell/awtarchy/LockscreenCompactSelector.qml").write_text(selector)

editor = "config/quickshell/awtarchy/LockscreenEditor.qml"
replace_once(editor, '''    readonly property var timezonePresets: [
        { key: "UTC", label: "UTC" },
        { key: "America/New_York", label: "New York" },
        { key: "America/Los_Angeles", label: "Los Angeles" },
        { key: "Europe/London", label: "London" },
        { key: "Asia/Tokyo", label: "Tokyo" },
        { key: "Australia/Sydney", label: "Sydney" }
    ]''', '''    readonly property var timezonePresets: [
        { key: "UTC", label: "UTC" },
        { key: "America/New_York", label: "New York" },
        { key: "America/Chicago", label: "Chicago" },
        { key: "America/Denver", label: "Denver" },
        { key: "America/Phoenix", label: "Phoenix" },
        { key: "America/Los_Angeles", label: "Los Angeles" },
        { key: "America/Anchorage", label: "Anchorage" },
        { key: "Pacific/Honolulu", label: "Honolulu" },
        { key: "America/Toronto", label: "Toronto" },
        { key: "America/Vancouver", label: "Vancouver" },
        { key: "America/Mexico_City", label: "Mexico City" },
        { key: "America/Sao_Paulo", label: "São Paulo" },
        { key: "America/Argentina/Buenos_Aires", label: "Buenos Aires" },
        { key: "Europe/London", label: "London" },
        { key: "Europe/Paris", label: "Paris" },
        { key: "Europe/Berlin", label: "Berlin" },
        { key: "Europe/Madrid", label: "Madrid" },
        { key: "Europe/Rome", label: "Rome" },
        { key: "Europe/Amsterdam", label: "Amsterdam" },
        { key: "Europe/Stockholm", label: "Stockholm" },
        { key: "Europe/Moscow", label: "Moscow" },
        { key: "Africa/Cairo", label: "Cairo" },
        { key: "Africa/Johannesburg", label: "Johannesburg" },
        { key: "Asia/Jerusalem", label: "Jerusalem" },
        { key: "Asia/Dubai", label: "Dubai" },
        { key: "Asia/Kolkata", label: "Kolkata" },
        { key: "Asia/Bangkok", label: "Bangkok" },
        { key: "Asia/Singapore", label: "Singapore" },
        { key: "Asia/Shanghai", label: "Shanghai" },
        { key: "Asia/Hong_Kong", label: "Hong Kong" },
        { key: "Asia/Tokyo", label: "Tokyo" },
        { key: "Asia/Seoul", label: "Seoul" },
        { key: "Australia/Perth", label: "Perth" },
        { key: "Australia/Adelaide", label: "Adelaide" },
        { key: "Australia/Brisbane", label: "Brisbane" },
        { key: "Australia/Sydney", label: "Sydney" },
        { key: "Pacific/Auckland", label: "Auckland" }
    ]''')
replace_once(editor,
    'result.push(({id:id, timezone:timezone, format:normalizedClockFormat(raw.format), x:Math.max(0.05,Math.min(0.95,Number.isFinite(x)?x:0.5)),',
    'result.push(({id:id, timezone:timezone, format:normalizedClockFormat(raw.format), show_label: raw.show_label !== false, x:Math.max(0.05,Math.min(0.95,Number.isFinite(x)?x:0.5)),')
replace_once(editor,
    'next.push(({id:id,timezone:"UTC",format:"24h",x:0.5,y:0.60,scale:1,stretch_x:1,stretch_y:1,opacity:100,rotation:0,color:"auto",visible:true}));',
    'next.push(({id:id,timezone:"UTC",format:"24h",show_label: true,x:0.5,y:0.60,scale:1,stretch_x:1,stretch_y:1,opacity:100,rotation:0,color:"auto",visible:true}));')
replace_once(editor,
    'function setTimezoneClockFormat(name, format) { const i=timezoneClockIndex(name);if(i<0)return;recordUndoBeforeChange();const next=cloneTimezoneClocks(draftTimezoneClocks);next[i].format=normalizedClockFormat(format);draftTimezoneClocks=next;refreshPreviewTimezoneValues(); }',
    'function setTimezoneClockFormat(name, format) { const i=timezoneClockIndex(name);if(i<0)return;recordUndoBeforeChange();const next=cloneTimezoneClocks(draftTimezoneClocks);next[i].format=normalizedClockFormat(format);draftTimezoneClocks=next;refreshPreviewTimezoneValues(); }\n    function setTimezoneClockShowLabel(name, visible) { const i=timezoneClockIndex(name);if(i<0)return;recordUndoBeforeChange();const next=cloneTimezoneClocks(draftTimezoneClocks);next[i].show_label=!!visible;draftTimezoneClocks=next; }')

old_opacity = '''    function setDraftOpacity(name, opacity) {
        if (!elementExists(name)) return; const numeric = Number(opacity); if (!Number.isFinite(numeric)) return;
        const minimum = name === "password" ? 20 : 0; const value = Math.round(Math.max(minimum, Math.min(100, numeric))); recordUndoBeforeChange();
        if (name === "visualizer") { const next = cloneVisualizer(draftVisualizer); next.opacity = value; draftVisualizer = next; }
        else if (isCustomImage(name)) { const next = cloneCustomImages(draftCustomImages); const index = next.findIndex(image => image.id === name); if (index < 0) return; next[index].opacity = value; draftCustomImages = next; }
        else if(isTimezoneClock(name)){const next=cloneTimezoneClocks(draftTimezoneClocks);next[timezoneClockIndex(name)].opacity=value;draftTimezoneClocks=next;}
        else if(isCustomText(name)){const next=cloneCustomTexts(draftCustomTexts);next[customTextIndex(name)].opacity=value;draftCustomTexts=next;}
        else { const next = cloneLayout(draftLayout); next[name].opacity = value; draftLayout = next; }
        selectElement(name, false);
    }'''
new_opacity = '''    function setDraftOpacitySilently(name, opacity) {
        if (!elementExists(name)) return; const numeric = Number(opacity); if (!Number.isFinite(numeric)) return;
        const minimum = name === "password" ? 20 : 0; const value = Math.round(Math.max(minimum, Math.min(100, numeric)));
        if (name === "visualizer") { const next = cloneVisualizer(draftVisualizer); next.opacity = value; draftVisualizer = next; }
        else if (isCustomImage(name)) { const next = cloneCustomImages(draftCustomImages); const index = next.findIndex(image => image.id === name); if (index < 0) return; next[index].opacity = value; draftCustomImages = next; }
        else if(isTimezoneClock(name)){const next=cloneTimezoneClocks(draftTimezoneClocks);next[timezoneClockIndex(name)].opacity=value;draftTimezoneClocks=next;}
        else if(isCustomText(name)){const next=cloneCustomTexts(draftCustomTexts);next[customTextIndex(name)].opacity=value;draftCustomTexts=next;}
        else { const next = cloneLayout(draftLayout); next[name].opacity = value; draftLayout = next; }
    }

    function setDraftOpacity(name, opacity) {
        if (!elementExists(name)) return; const numeric = Number(opacity); if (!Number.isFinite(numeric)) return;
        recordUndoBeforeChange();
        setDraftOpacitySilently(name, numeric);
        selectElement(name, false);
    }

    function setElementOpacityFromPointer(name, pointerX, trackWidth) {
        const width = Number(trackWidth); if (!elementExists(name) || !Number.isFinite(width) || width <= 0) return;
        const minimum = name === "password" ? 20 : 0;
        const ratio = Math.max(0, Math.min(1, Number(pointerX) / width));
        const value = minimum + ratio * (100 - minimum);
        root.setDraftOpacitySilently(name, value);
    }'''
replace_once(editor, old_opacity, new_opacity)
replace_once(editor, 'opacity: 0.92; z: 200', 'opacity: 0.92; z: root.selectedElement === elementName ? 230 : 200')
replace_once(editor, 'border.color: Theme.focus; z: 40\n                Text { anchors.centerIn: parent; text: "↻";', 'border.color: Theme.focus; z: 240\n                Text { anchors.centerIn: parent; text: "↻";')
replace_once(editor, '''                    RowLayout {
                        Layout.fillWidth: true; spacing: 7; visible: root.activeDrawer === "element" && root.isCustomImage(root.selectedElement)
                        SettingsButton { label: "Reset Position";''', '''                    RowLayout {
                        Layout.fillWidth: true; spacing: 7; visible: root.activeDrawer === "element" && root.isCustomImage(root.selectedElement)
                        Text { text: "Image Opacity"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 9 }
                        Rectangle {
                            id: imageOpacityTrack
                            visible: root.isCustomImage(root.selectedElement)
                            Layout.fillWidth: true
                            Layout.preferredHeight: 14
                            color: Theme.surface
                            border.width: 1
                            border.color: Theme.muted
                            radius: 3
                            Rectangle {
                                anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                                width: parent.width * root.elementOpacity(root.selectedElement) / 100
                                color: Theme.focus; opacity: 0.45; radius: 3
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                preventStealing: true
                                onPressed: mouse => { root.beginHistoryTransaction(); root.setElementOpacityFromPointer(root.selectedElement, mouse.x, width); }
                                onPositionChanged: mouse => { if (pressed) root.setElementOpacityFromPointer(root.selectedElement, mouse.x, width); }
                                onReleased: root.commitHistoryTransaction()
                                onCanceled: root.commitHistoryTransaction()
                            }
                        }
                        Text { text: Number(root.elementOpacity(root.selectedElement)).toFixed(0) + "%"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: 9 }
                    }

                    RowLayout {
                        Layout.fillWidth: true; spacing: 7; visible: root.activeDrawer === "element" && root.isCustomImage(root.selectedElement)
                        SettingsButton { label: "Reset Position";''')
replace_once(editor, '''                        SettingsButton { label: root.elementPoint(root.selectedElement).format === "12h" ? "12-hour" : "24-hour"; active: root.elementPoint(root.selectedElement).format === "12h"; textSize: 9; onClicked: root.setTimezoneClockFormat(root.selectedElement, root.elementPoint(root.selectedElement).format === "12h" ? "24h" : "12h") }
                        Item { Layout.fillWidth: true }
                        Text { text: "Each extra clock has independent timezone, format, position, scale, color, opacity, and rotation.";''', '''                        SettingsButton { label: root.elementPoint(root.selectedElement).format === "12h" ? "12-hour" : "24-hour"; active: root.elementPoint(root.selectedElement).format === "12h"; textSize: 9; onClicked: root.setTimezoneClockFormat(root.selectedElement, root.elementPoint(root.selectedElement).format === "12h" ? "24h" : "12h") }
                        SettingsButton { label: root.elementPoint(root.selectedElement).show_label === false ? "Label Off" : "Label On"; active: root.elementPoint(root.selectedElement).show_label !== false; textSize: 9; onClicked: root.setTimezoneClockShowLabel(root.selectedElement, root.elementPoint(root.selectedElement).show_label === false) }
                        Item { Layout.fillWidth: true }
                        Text { text: "Each extra clock has independent timezone, label, format, position, scale, color, opacity, and rotation.";''')

scene = "config/quickshell/awtarchy-lock/LockScene.qml"
replace_once(scene, '''    function timezoneDisplay(clock) {
        if (!clock) return "--:--";
        const value = String(root.timezoneValues && root.timezoneValues[clock.id] !== undefined ? root.timezoneValues[clock.id] : "--:--");
        return value + "\\n" + timezoneLabel(clock.timezone);
    }''', '''    function timezoneDisplay(clock) {
        if (!clock) return "--:--";
        const value = String(root.timezoneValues && root.timezoneValues[clock.id] !== undefined ? root.timezoneValues[clock.id] : "--:--");
        if (clock.show_label === false)
            return value;
        return value + "\\n" + timezoneLabel(clock.timezone);
    }''')
Path("config/quickshell/awtarchy/LockPreviewScene.qml").write_text(Path(scene).read_text())

lock_shell = "config/quickshell/awtarchy-lock/shell.qml"
replace_once(lock_shell,
    'result.push(({ id:id, timezone:timezone, format:format, x:x, y:y, scale:scale, stretch_x:sx, stretch_y:sy,\n                opacity:opacity, rotation:rotation, color:color, visible:raw.visible }));',
    'result.push(({ id:id, timezone:timezone, format:format, show_label: raw.show_label !== false, x:x, y:y, scale:scale, stretch_x:sx, stretch_y:sy,\n                opacity:opacity, rotation:rotation, color:color, visible:raw.visible }));')

barstate = "config/quickshell/awtarchy/BarState.qml"
replace_once(barstate,
    'result.push(({ id: id, timezone: timezone, format: format, x: x, y: y, scale: scale,\n                stretch_x: sx, stretch_y: sy, opacity: opacity, rotation: rotation, color: color, visible: raw.visible }));',
    'result.push(({ id: id, timezone: timezone, format: format, show_label: raw.show_label !== false, x: x, y: y, scale: scale,\n                stretch_x: sx, stretch_y: sy, opacity: opacity, rotation: rotation, color: color, visible: raw.visible }));')

save = "config/hypr/scripts/quickshell_lockscreen_editor_save.sh"
replace_once(save,
    'format: (if ((.format // "24h") | ascii_downcase) == "12h" then "12h" else "24h" end),\n                x: clamp(.x; 0.5; 0.05; 0.95),',
    'format: (if ((.format // "24h") | ascii_downcase) == "12h" then "12h" else "24h" end),\n                show_label: (if (.show_label | type) == "boolean" then .show_label else true end),\n                x: clamp(.x; 0.5; 0.05; 0.95),')

quick = "config/quickshell/awtarchy/QuickSettings.qml"
replace_once(quick,
    '    property var flyoutScreen: null\n',
    '    property var flyoutScreen: null\n    property int lockscreenHideQuickshellBeforeCaptureOverride: -1\n    readonly property bool lockscreenHideQuickshellBeforeCapture: lockscreenHideQuickshellBeforeCaptureOverride >= 0\n        ? lockscreenHideQuickshellBeforeCaptureOverride === 1\n        : BarState.lockscreenHideQuickshellBeforeCapture()\n')
replace_once(quick, '''    function openFocused() { openForScreen(focusedScreen()); }

    function close() {''', '''    function openFocused() { openForScreen(focusedScreen()); }

    function prepareLockCapture(): bool {
        if (!QuickSettings.lockscreenHideQuickshellBeforeCapture)
            return false;
        QuickSettings.close();
        return true;
    }

    function lockCaptureHidden(): bool {
        return !quickSettingsWindow.backingWindowVisible;
    }

    function close() {''')
replace_once(quick, '''                                        SettingsButton { label: BarState.lockscreenHideQuickshellBeforeCapture() ? "On" : "Off"; active: BarState.lockscreenHideQuickshellBeforeCapture(); textSize: root.scaledText(9); onClicked: root.queueStateCommand(["set-lockscreen-hide-quickshell-before-capture", BarState.lockscreenHideQuickshellBeforeCapture() ? "false" : "true"]) }''', '''                                        SettingsButton {
                                            label: QuickSettings.lockscreenHideQuickshellBeforeCapture ? "On" : "Off"
                                            active: QuickSettings.lockscreenHideQuickshellBeforeCapture
                                            textSize: root.scaledText(9)
                                            onClicked: {
                                                const next = !QuickSettings.lockscreenHideQuickshellBeforeCapture;
                                                root.lockscreenHideQuickshellBeforeCaptureOverride = next ? 1 : 0;
                                                root.queueStateCommand(["set-lockscreen-hide-quickshell-before-capture", next ? "true" : "false"]);
                                            }
                                        }''')
replace_once(quick, '''        function close(): void { root.close(); }
        function refresh(): void { root.refreshStatus(); }''', '''        function close(): void { root.close(); }
        function refresh(): void { root.refreshStatus(); }
        function prepareLockCapture(): bool { return root.prepareLockCapture(); }
        function lockCaptureHidden(): bool { return root.lockCaptureHidden(); }''')

lock = "config/hypr/scripts/awtarchy_lock.sh"
replace_once(lock, '''hide_quick_settings_before_capture() {
    hide_quick_settings_before_capture_enabled || return 0

    # This is an opt-in presentation fallback only. The secure backing remains
    # a frozen pre-lock capture and the lock still fails closed if capture fails.
    "$QS_BIN" -c "$SHELL_CONFIG_NAME" ipc call quicksettings close \\
        >>"$LOG_FILE" 2>&1 || true

    case "$CAPTURE_HIDE_DELAY" in
        0|0.[0-9]|0.[0-9][0-9]|0.[0-9][0-9][0-9]|1|1.0|1.00|1.000)
            sleep "$CAPTURE_HIDE_DELAY"
            ;;
        *)
            sleep 0.18
            ;;
    esac
}''', '''hide_quick_settings_before_capture() {
    local live_response="" live_available=false hidden_response=""

    # Consult the in-memory QML preference first so a just-clicked toggle does
    # not race its asynchronous state-file write.
    if live_response="$(
        "$QS_BIN" -c "$SHELL_CONFIG_NAME" ipc call quicksettings prepareLockCapture 2>>"$LOG_FILE" |
            tail -n1
    )"; then
        live_available=true
    fi

    if [[ "$live_available" == true ]]; then
        [[ "$live_response" == true ]] || return 0
    else
        # Fallback: get lockscreen_hide_quickshell_before_capture from persisted cache.
        hide_quick_settings_before_capture_enabled || return 0
        "$QS_BIN" -c "$SHELL_CONFIG_NAME" ipc call quicksettings close \\
            >>"$LOG_FILE" 2>&1 || true
    fi

    # Wait on the real QsWindow backing surface instead of assuming a fixed
    # compositor delay was sufficient. Keep the bounded sleep fallback for an
    # older/unreachable desktop shell so locking itself is never blocked here.
    for _ in {1..25}; do
        if hidden_response="$(
            "$QS_BIN" -c "$SHELL_CONFIG_NAME" ipc call quicksettings lockCaptureHidden 2>>"$LOG_FILE" |
                tail -n1
        )" && [[ "$hidden_response" == true ]]; then
            return 0
        fi
        sleep 0.02
    done

    case "$CAPTURE_HIDE_DELAY" in
        0|0.[0-9]|0.[0-9][0-9]|0.[0-9][0-9][0-9]|1|1.0|1.00|1.000)
            sleep "$CAPTURE_HIDE_DELAY"
            ;;
        *)
            sleep 0.18
            ;;
    esac
}''')
replace_once(lock, '''start_lock() {
    local state capture_dir=""
''', '''start_lock() {
    local state capture_dir="" capture_helper="$CAPTURE_HELPER"
''')
replace_once(lock, '''    if [[ -f "$CAPTURE_HELPER" ]]; then
        capture_dir="$(bash "$CAPTURE_HELPER" prepare 2>>"$LOG_FILE")" || capture_dir=""
    fi''', '''    if [[ -f "$capture_helper" ]]; then
        capture_dir="$(bash "$capture_helper" prepare 2>>"$LOG_FILE")" || capture_dir=""
    fi''')

history = Path("local/share/awtarchy/quickshell-managed-history.sha256")
managed = {
    "config/quickshell/awtarchy/BarState.qml": ".config/quickshell/awtarchy/BarState.qml",
    "config/quickshell/awtarchy/QuickSettings.qml": ".config/quickshell/awtarchy/QuickSettings.qml",
    "config/quickshell/awtarchy/LockscreenEditor.qml": ".config/quickshell/awtarchy/LockscreenEditor.qml",
    "config/quickshell/awtarchy/LockPreviewScene.qml": ".config/quickshell/awtarchy/LockPreviewScene.qml",
    "config/quickshell/awtarchy-lock/shell.qml": ".config/quickshell/awtarchy-lock/shell.qml",
    "config/quickshell/awtarchy-lock/LockScene.qml": ".config/quickshell/awtarchy-lock/LockScene.qml",
}
text = history.read_text()
additions = []
for source, installed in managed.items():
    digest = hashlib.sha256(Path(source).read_bytes()).hexdigest()
    line = f"{digest}\t{installed}"
    if line not in text.splitlines():
        additions.append(line)
if additions:
    history.write_text(text.rstrip("\n") + "\n" + "\n".join(additions) + "\n")
