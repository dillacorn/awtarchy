import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    property bool active: false
    property int textScale: 100
    property int iconScale: 100

    readonly property string floatingState: FloatingWindowsState.state
    readonly property bool operationBusy: FloatingWindowsState.busy

    Layout.fillWidth: true
    Layout.preferredHeight: content.implicitHeight + 16
    color: Theme.popupButton
    border.width: root.floatingState === "enabled" ? 2 : 1
    border.color: root.floatingState === "enabled" ? Theme.urgent : Theme.active

    function scaledText(baseSize) {
        return Math.max(8, Math.round(baseSize * textScale / 100));
    }

    function statusLabel() {
        if (floatingState === "enabled")
            return "FLOATING ON";
        if (floatingState === "disabled")
            return "Tiling";
        if (floatingState === "unavailable")
            return "Unavailable";
        return "Checking…";
    }

    function requestToggle() {
        FloatingWindowsState.toggle();
    }

    onActiveChanged: {
        if (!active)
            return;
        FloatingWindowsState.clearFeedback();
        if (!FloatingWindowsState.available)
            Qt.callLater(() => FloatingWindowsState.refresh());
    }

    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: 8
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    Layout.fillWidth: true
                    text: "Window Behavior"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: root.scaledText(12)
                    font.bold: true
                }

                Text {
                    Layout.fillWidth: true
                    text: "Floating Windows"
                    color: Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: root.scaledText(8)
                }
            }

            Text {
                text: root.statusLabel()
                color: root.floatingState === "enabled" ? Theme.urgent : Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: root.scaledText(8)
                font.bold: root.floatingState === "enabled"
            }

            SettingsButton {
                label: root.floatingState === "enabled" ? "Restore tiling" : "Enable floating"
                active: root.floatingState === "enabled"
                textSize: root.scaledText(9)
                enabled: FloatingWindowsState.available && !root.operationBusy
                onClicked: root.requestToggle()
            }
        }

        Text {
            Layout.fillWidth: true
            text: FloatingWindowsState.errorMessage.length > 0
                ? FloatingWindowsState.errorMessage
                : (FloatingWindowsState.message.length > 0
                    ? FloatingWindowsState.message
                    : (root.floatingState === "enabled"
                        ? "GLOBAL MODE ACTIVE: new windows open floating by default. Existing windows keep their current state. Restore tiling here. SUPER+F only changes the focused window."
                        : "New windows use Awtarchy's normal tiling behavior. Use this setting to change the global spawn mode; SUPER+F only changes the focused window."))
            color: (FloatingWindowsState.errorMessage.length > 0 || root.floatingState === "enabled")
                ? Theme.urgent
                : Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: root.scaledText(8)
            wrapMode: Text.Wrap
        }
    }
}
