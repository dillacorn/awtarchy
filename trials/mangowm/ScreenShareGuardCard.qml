import QtQuick
import QtQuick.Layouts

// Mango's shield_when_capture window rules are configured at compositor
// startup. Unlike Hyprland, the trial has no verified per-app live toggle
// API. Do not render controls that could falsely imply changed protection.
Rectangle {
    id: root

    property bool active: false
    property int textScale: 100
    property int iconScale: 100

    Layout.fillWidth: true
    Layout.preferredHeight: content.implicitHeight + 16
    color: Theme.popupButton
    border.width: 1
    border.color: Theme.active

    function scaledText(size) {
        return Math.max(8, Math.round(size * textScale / 100));
    }

    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: 8
        spacing: 6

        Text {
            Layout.fillWidth: true
            text: "Screen Share Guard"
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: root.scaledText(12)
            font.bold: true
        }

        Text {
            Layout.fillWidth: true
            text: "Mango trial: static capture shielding is enabled for protected apps."
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: root.scaledText(9)
            wrapMode: Text.Wrap
        }

        Text {
            Layout.fillWidth: true
            text: "Per-app allow/protect switches are unavailable. Capture policies cannot be changed from this panel; verify screen sharing before exposing sensitive content."
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: root.scaledText(8)
            wrapMode: Text.Wrap
        }
    }
}
