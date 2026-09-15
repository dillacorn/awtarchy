pragma ComponentBehavior: Bound

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
        color: closedMouse.containsMouse || root.activeFocus ? Theme.hover : Theme.background
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
