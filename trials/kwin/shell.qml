// Temporary KWin/Quickshell integration probe. Not the production Awtarchy shell.
import QtQuick
import Quickshell

ShellRoot {
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
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                text: "AWTARCHY  /  KWin trial"
                font.family: "Noto Sans"
                font.pixelSize: 12
                color: "#d6d6d6"
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
