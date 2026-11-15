pragma Singleton
import QtQuick
import Quickshell

// Sway bar drag communicates inside Quickshell rather than through
// Hyprland's layer/pointer Lua API or a subprocess per pointer movement.
Singleton {
    signal beginBarDrag(string monitor)
    signal previewBarDrag(string monitor, string candidate)
    signal finishBarDrag(string monitor, string candidate)
}
