pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Singleton {
    id: root

    property bool capsLockOn: false
    property bool refreshPending: false

    function refresh() {
        if (devicesProcess.running) {
            refreshPending = true;
            return;
        }

        refreshPending = false;
        devicesProcess.exec(["hyprctl", "devices", "-j"]);
    }

    function parseDevices(text) {
        try {
            const data = JSON.parse(String(text || "").trim());
            const keyboards = data && Array.isArray(data.keyboards) ? data.keyboards : [];
            let enabled = false;

            for (let i = 0; i < keyboards.length; ++i) {
                if (keyboards[i] && keyboards[i].capsLock === true) {
                    enabled = true;
                    break;
                }
            }

            root.capsLockOn = enabled;
        } catch (error) {
            console.warn("Awtarchy Caps Lock state parse failed:", error);
        }
    }

    Component.onCompleted: root.refresh()

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (!event || event.name !== "custom")
                return;
            if (String(event.data || "").trim() === "awtarchy-capslock")
                root.refresh();
        }
    }

    Process {
        id: devicesProcess

        stdout: StdioCollector {
            onStreamFinished: root.parseDevices(text)
        }

        onExited: {
            if (root.refreshPending)
                Qt.callLater(root.refresh);
        }
    }
}
