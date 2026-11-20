pragma Singleton
import QtQuick
import Quickshell

// Umbriel's portal protocol is different from the Sway xdpw picker.
// Fail closed instead of sending a request to an unrelated compositor.
Singleton {
    function open(requestFile: string): bool {
        console.warn("Umbriel screen sharing requires a verified native portal; Sway picker disabled");
        return false;
    }
}
