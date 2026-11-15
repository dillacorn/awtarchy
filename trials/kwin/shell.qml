// Private KWin/Quickshell integration probe, not the production Awtarchy UI.
import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root
    property var workspaceState: ({ version: 1, desktops: [], outputs: [] })

    function output(name) {
        const outputs = root.workspaceState.outputs || [];
        for (const item of outputs) {
            if (item.name === name) return item;
        }
        return { active: null, occupied: [] };
    }

    FileView {
        id: stateFile
        path: Quickshell.env("AWTARCHY_KWIN_STATE_FILE")
              ? "file://" + Quickshell.env("AWTARCHY_KWIN_STATE_FILE") : ""
        watchChanges: true
        printErrors: false
        onFileChanged: this.reload()
        onLoaded: {
            try {
                const next = JSON.parse(this.text());
                if (next.version === 1 && Array.isArray(next.outputs) &&
                    Array.isArray(next.desktops)) {
                    root.workspaceState = next;
                }
            } catch (_) {
                // Keep the last known state on partial/invalid updates.
            }
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: panel
            required property var modelData
            screen: modelData
            anchors {
                left: true
                right: true
                top: true
            }
            implicitHeight: 34
            color: "#181a1e"

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: "AWTARCHY  /  KWin"
                font.family: "Noto Sans"
                font.pixelSize: 12
                color: "#d6d6d6"
            }

            Row {
                anchors.centerIn: parent
                spacing: 4

                Repeater {
                    model: root.workspaceState.desktops.length

                    Rectangle {
                        required property int index
                        readonly property string desktopId:
                            root.workspaceState.desktops[index].id
                        readonly property var current: root.output(panel.modelData.name)
                        readonly property bool focused: current.active === desktopId
                        readonly property bool occupied:
                            current.occupied.indexOf(desktopId) >= 0
                        width: 23
                        height: 23
                        radius: 3
                        color: focused ? "#81858c" : (occupied ? "#34373d" : "#181a1e")

                        Text {
                            anchors.centerIn: parent
                            text: (index + 1).toString()
                            font.family: "Noto Sans"
                            font.pixelSize: 11
                            color: focused ? "#101114" : (occupied ? "#d6d6d6" : "#6c7075")
                        }
                    }
                }
            }

            SystemClock {
                id: clock
                precision: SystemClock.Minutes
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDateTime(clock.date, "ddd MMM d  hh:mm")
                font.family: "Noto Sans"
                font.pixelSize: 12
                color: "#d6d6d6"
            }
        }
    }
}
