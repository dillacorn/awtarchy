import QtQuick

FocusScope {
    id: root

    property var model: []
    property int currentIndex: 0
    property bool menuOpen: false
    property int highlightedIndex: Math.max(0, currentIndex)
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
    z: menuOpen ? 1000 : 0

    function activateIndex(index) {
        if (!Array.isArray(model) || model.length === 0)
            return;
        const bounded = Math.max(0, Math.min(model.length - 1, Number(index)));
        activated(bounded);
    }

    function openMenu() {
        if (!Array.isArray(model) || model.length === 0)
            return;
        highlightedIndex = Math.max(0, Math.min(model.length - 1, currentIndex));
        menuOpen = true;
        forceActiveFocus();
    }

    function closeMenu() {
        menuOpen = false;
    }

    function activateHighlighted() {
        if (!menuOpen)
            return;
        activateIndex(highlightedIndex);
        closeMenu();
    }

    Keys.onEscapePressed: event => {
        if (root.menuOpen) {
            root.closeMenu();
            event.accepted = true;
        }
    }

    Keys.onPressed: event => {
        if (!root.menuOpen) {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                    || event.key === Qt.Key_Space || event.key === Qt.Key_Down
                    || event.key === Qt.Key_Up) {
                root.openMenu();
                event.accepted = true;
            }
            return;
        }

        if (event.key === Qt.Key_Up) {
            root.highlightedIndex = Math.max(0, root.highlightedIndex - 1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Down) {
            root.highlightedIndex = Math.min(root.model.length - 1, root.highlightedIndex + 1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                || event.key === Qt.Key_Space) {
            root.activateHighlighted();
            event.accepted = true;
        }
    }

    Rectangle {
        id: closedControl
        anchors.fill: parent
        radius: 5
        color: Theme.popupBackground
        border.width: root.activeFocus ? 2 : 1
        border.color: root.activeFocus ? Theme.focus : Theme.active

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.right: disclosure.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: root.selectedLabel
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: 9
            font.bold: true
            horizontalAlignment: Text.AlignLeft
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }

        Text {
            id: disclosure
            anchors.right: parent.right
            anchors.rightMargin: 9
            anchors.verticalCenter: parent.verticalCenter
            text: root.menuOpen ? "▴" : "▾"
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: 10
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPressed: root.forceActiveFocus()
            onClicked: {
                if (root.menuOpen)
                    root.closeMenu();
                else
                    root.openMenu();
            }
        }
    }

    Rectangle {
        id: flyout
        visible: root.menuOpen
        anchors.top: parent.bottom
        anchors.topMargin: 4
        anchors.left: parent.left
        width: parent.width
        height: optionColumn.implicitHeight + 8
        radius: 6
        color: Theme.popupBackground
        border.width: 1
        border.color: Theme.active
        z: 1001

        Column {
            id: optionColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 4
            spacing: 2

            Repeater {
                model: Array.isArray(root.model) ? root.model : []

                delegate: Rectangle {
                    required property int index
                    required property var modelData

                    width: optionColumn.width
                    height: 26
                    radius: 4
                    color: index === root.highlightedIndex
                        ? Theme.hover
                        : (index === root.currentIndex ? Theme.active : "transparent")

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData && modelData.label !== undefined
                            ? String(modelData.label) : String(modelData || "")
                        color: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: 9
                        font.bold: index === root.currentIndex
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.highlightedIndex = index
                        onClicked: {
                            root.highlightedIndex = index;
                            root.activateHighlighted();
                        }
                    }
                }
            }
        }
    }

    onCurrentIndexChanged: {
        if (!menuOpen)
            highlightedIndex = Math.max(0, currentIndex);
    }
    onActiveFocusChanged: {
        if (!activeFocus)
            closeMenu();
    }
}
