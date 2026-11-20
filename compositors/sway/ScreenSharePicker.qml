pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Isolated Sway screen/window choice overlay. Capture remains portal-owned.
Singleton {
    id: root
    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ""
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME")
        || (Quickshell.env("HOME") + "/.config")
    readonly property string responder: configHome
        + "/sway/awtarchy-trial/portal-chooser.py"
    property string requestPath: ""
    property var choices: []
    property int selectedIndex: 0

    FileView {
        id: requestFile
        path: root.requestPath
        blockLoading: true
        printErrors: false
    }

    function focusedScreen() {
        const monitor = SwayBridge.focusedMonitor;
        const name = monitor && monitor.name ? String(monitor.name) : "";
        const matches = Quickshell.screens.filter(s => s.name === name);
        return matches.length ? matches[0]
            : (Quickshell.screens.length ? Quickshell.screens[0] : null);
    }

    function open(path: string): bool {
        // Only read a request created inside this user's private runtime.
        if (picker.visible || !runtimeDir ||
                !path.startsWith(runtimeDir + "/awtarchy-screencast-"))
            return false;
        const relative = path.slice(runtimeDir.length + 1);
        if (!/^awtarchy-screencast-[a-z0-9_]+\/request\.json$/.test(relative))
            return false;
        root.requestPath = path;
        requestFile.reload();
        try {
            const data = JSON.parse(requestFile.text());
            if (!data || !Array.isArray(data.choices)
                    || data.choices.length < 1 || data.choices.length > 64
                    || !data.choices.every(v => typeof v === "string"
                        && v.length > 0)) {
                root.requestPath = "";
                return false;
            }
            root.choices = data.choices;
        } catch (error) {
            root.requestPath = "";
            return false;
        }
        root.selectedIndex = 0;
        const screen = focusedScreen();
        if (screen)
            picker.screen = screen;
        picker.visible = true;
        Qt.callLater(() => {
            if (picker.visible) {
                picker.requestActivate();
                keyInput.forceActiveFocus();
            }
        });
        return true;
    }

    function finish(index: int) {
        if (!picker.visible)
            return;
        const request = root.requestPath;
        picker.visible = false;
        root.requestPath = "";
        root.choices = [];
        if (request)
            Quickshell.execDetached([
                "python3", root.responder, "respond", request, String(index)
            ]);
    }

    PanelWindow {
        id: picker
        visible: false
        focusable: true
        aboveWindows: true
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.namespace: "awtarchy-sway-screencast-picker"
        anchors {
            left: true
            right: true
            top: true
            bottom: true
        }
        color: Qt.rgba(Theme.dark.r, Theme.dark.g, Theme.dark.b, 0.83)

        FocusScope {
            id: keyInput
            anchors.fill: parent
            focus: true

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    root.finish(-1);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Up) {
                    root.selectedIndex = (root.selectedIndex +
                        root.choices.length - 1) % root.choices.length;
                    sourceList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Down) {
                    root.selectedIndex = (root.selectedIndex + 1) % root.choices.length;
                    sourceList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Return ||
                           event.key === Qt.Key_Enter) {
                    root.finish(root.selectedIndex);
                    event.accepted = true;
                }
            }

            Rectangle {
                id: panel
                anchors.centerIn: parent
                width: Math.min(590, Math.max(280, parent.width - 32))
                height: Math.min(parent.height - 32,
                    166 + Math.min(root.choices.length, 9) * 46)
                radius: 8
                color: Theme.popupBackground
                border.color: Theme.focus
                border.width: 1

                Column {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 12

                    Text {
                        text: "Share a screen or window"
                        color: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: 19
                        font.bold: true
                    }
                    Text {
                        text: "Choose what OBS or your application may capture"
                        color: Theme.foreground
                        opacity: 0.72
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                    }

                    ListView {
                        id: sourceList
                        width: parent.width
                        height: Math.max(40, panel.height - 156)
                        clip: true
                        model: root.choices
                        spacing: 4
                        currentIndex: root.selectedIndex

                        delegate: Rectangle {
                            required property int index
                            required property string modelData
                            width: sourceList.width
                            height: 42
                            radius: 4
                            color: index === root.selectedIndex
                                ? Theme.focus
                                : (hit.containsMouse ? Theme.hover : Theme.active)
                            border.color: index === root.selectedIndex
                                ? Theme.foreground : Theme.muted
                            border.width: index === root.selectedIndex ? 1 : 0
                            Text {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                verticalAlignment: Text.AlignVCenter
                                text: modelData
                                elide: Text.ElideRight
                                color: Theme.foreground
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                            }
                            MouseArea {
                                id: hit
                                anchors.fill: parent
                                hoverEnabled: true
                                onEntered: root.selectedIndex = index
                                onClicked: root.finish(index)
                            }
                        }
                    }
                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Theme.muted
                    }
                    Row {
                        width: parent.width
                        height: 26
                        spacing: 18
                        Text {
                            text: "↑ ↓ Navigate     Enter Share     Esc Cancel"
                            color: Theme.foreground
                            opacity: 0.7
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }
                        Text {
                            text: "Cancel"
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.finish(-1)
                            }
                        }
                    }
                }
            }
        }
    }
}
