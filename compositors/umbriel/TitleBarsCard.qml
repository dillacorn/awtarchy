import QtQuick
import QtQuick.Layouts

// This is Umbriel's native negotiated xdg-decoration support, not hyprbars.
// Never offer Hyprland plugin installation from an Umbriel session.
Rectangle {
    id: root
    property bool active: false
    property int textScale: 100
    property int iconScale: 100
    Layout.fillWidth: true
    Layout.preferredHeight: column.implicitHeight + 16
    color: Theme.popupButton
    border.width: 1
    border.color: Theme.active

    ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.margins: 8
        spacing: 6
        Text {
            Layout.fillWidth: true
            text: "Umbriel Native Title Bars"
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Math.max(9, Math.round(12 * root.textScale / 100))
            font.bold: true
        }
        Text {
            Layout.fillWidth: true
            text: "Native server-side title bars are configured in negotiated mode. They appear when applications negotiate server-side decorations, avoiding duplicate client title bars."
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Math.max(8, Math.round(9 * root.textScale / 100))
            wrapMode: Text.Wrap
        }
        Text {
            Layout.fillWidth: true
            text: "Hyprbars is exclusive to Hyprland and is not loaded here."
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Math.max(8, Math.round(8 * root.textScale / 100))
            wrapMode: Text.Wrap
        }
    }
}
