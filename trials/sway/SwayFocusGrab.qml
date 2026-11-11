import QtQuick

// Sway lacks hyprland_focus_grab_v1. We emulate focus loss for ordinary
// application toplevels without injecting pointer events or stealing focus.
// Layer-shell-only clicks remain a known limitation pending a native protocol.
QtObject {
    id: root

    property bool active: false
    property bool armed: false
    property var windows: []
    signal cleared()

    onActiveChanged: {
        armed = false;
        if (active)
            arming.restart();
        else
            arming.stop();
    }

    property Timer arming: Timer {
        interval: 120
        repeat: false
        onTriggered: root.armed = root.active
    }

    property Connections focusWatch: Connections {
        target: SwayBridge

        function onRawEvent(event) {
            if (!root.active || !root.armed || !event || event.name !== "activewindow")
                return;
            const fields = event.parse(2);
            const title = String(fields[1] || "");
            if (!title)
                return;
            for (const window of root.windows) {
                if (window && String(window.title || "") === title)
                    return;
            }
            root.active = false;
            root.cleared();
        }
    }
}
