import QtQuick

// Mango does not implement Hyprland's focus-grab-v1 protocol.
// This object preserves the QML contract but does NOT provide click-away grabs.
// Proper popup focus behavior remains a migration validation blocker.
QtObject {
    id: root
    property bool active: false
    property var windows: []
    signal cleared()
}
