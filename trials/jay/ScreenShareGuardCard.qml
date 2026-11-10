import QtQuick
import QtQuick.Layouts

// No verified per-window capture shielding controls in Jay. This card must
// never imply that Hyprland's Screen Share Guard is active in another compositor.
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
            font.pixelSize: Math.max(9, Math.round(12 * root.textScale / 100))
            font.bold: true
        }
        Text {
            Layout.fillWidth: true
            text: "Jay trial: per-application capture protection is not available."
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Math.max(8, Math.round(9 * root.textScale / 100))
            wrapMode: Text.Wrap
        }
        Text {
            Layout.fillWidth: true
            text: "No protection toggles are exposed. Verify actual sharing and avoid displaying sensitive content during testing."
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Math.max(8, Math.round(8 * root.textScale / 100))
            wrapMode: Text.Wrap
        }
    }
}
