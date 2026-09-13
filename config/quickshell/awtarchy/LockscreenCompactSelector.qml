import QtQuick

FocusScope {
    id: root

    property var model: []
    property int currentIndex: 0
    property string selectedLabel: {
        if (!Array.isArray(model) || currentIndex < 0 || currentIndex >= model.length)
            return "";
        const item = model[currentIndex];
        return item && item.label !== undefined ? String(item.label) : String(item || "");
    }
    signal activated(int index)

    implicitWidth: 220
    implicitHeight: 28
    activeFocusOnTab: true

    function activateIndex(index) {
        if (!Array.isArray(model) || model.length === 0)
            return;
        const wrapped = (Number(index) % model.length + model.length) % model.length;
        activated(wrapped);
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) {
            root.activateIndex(root.currentIndex - 1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down
                || event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                || event.key === Qt.Key_Space) {
            root.activateIndex(root.currentIndex + 1);
            event.accepted = true;
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 5
        color: Theme.popupBackground
        border.width: root.activeFocus ? 2 : 1
        border.color: root.activeFocus ? Theme.focus : Theme.active
    }

    Text {
        anchors.centerIn: parent
        width: Math.max(0, parent.width - 58)
        text: root.selectedLabel
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: 9
        font.bold: true
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    Text {
        anchors.left: parent.left
        anchors.leftMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        text: "‹"
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: 13
    }

    Text {
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        text: "›"
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: 13
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: root.forceActiveFocus()
        onClicked: mouse => {
            if (mouse.x < width * 0.30)
                root.activateIndex(root.currentIndex - 1);
            else
                root.activateIndex(root.currentIndex + 1);
        }
    }
}
