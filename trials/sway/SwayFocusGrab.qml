import QtQuick

// The Hyprland focus-grab protocol has no equivalent in standard Sway.
// Do not infer outside clicks from foreign-toplevel title events: those can
// refer to the previously focused application while a flyout is mapping,
// which incorrectly dismisses Quickshell immediately after opening.
//
// Explicit close, Escape, menu toggling, and workspace-change handling remain
// active in the Awtarchy shell. Outside-click dismissal is disabled until a
// reliable compositor-supported implementation is available.
QtObject {
    id: root
    property bool active: false
    property var windows: []
    signal cleared()
}
