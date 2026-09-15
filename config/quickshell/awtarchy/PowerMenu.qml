pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Singleton {
    id: root

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME")
        || (Quickshell.env("HOME") + "/.config")
    readonly property string lockCaptureHelper: configHome + "/hypr/scripts/quickshell_lockscreen_capture.sh"
    readonly property string freshLockCommand: "~/.config/hypr/scripts/awtarchy_lock.sh lock && ~/.config/hypr/scripts/awtarchy_lock.sh wait-secure 5"

    // Preserve the existing wlogout layout order and keybinds.
    readonly property var actions: [
        { label: "", text: "Lock (L)", key: "l", command: "~/.config/hypr/scripts/awtarchy_lock.sh lock-prepared && ~/.config/hypr/scripts/awtarchy_lock.sh wait-secure 5", closeAfterSuccess: true },
        { label: "", text: "Hibernate (H)", key: "h", command: "~/.config/hypr/scripts/awtarchy_lock.sh hibernate", closeAfterSuccess: true },
        { label: "", text: "Reboot (R)", key: "r", command: "systemctl reboot", closeAfterSuccess: false },
        { label: "", text: "Shutdown (S)", key: "s", command: "systemctl poweroff", closeAfterSuccess: false },
        { label: "", text: "Logout (O)", key: "o", command: "loginctl kill-session \"$XDG_SESSION_ID\"", closeAfterSuccess: false },
        { label: "", text: "Suspend (Z)", key: "z", command: "~/.config/hypr/scripts/awtarchy_lock.sh suspend", closeAfterSuccess: true }
    ]
    readonly property color shadeColor: Qt.rgba(
        Theme.background.r, Theme.background.g, Theme.background.b, 0.85)
    property bool actionPending: false
    property bool closeAfterActionSuccess: false
    property bool visualReady: false
    property bool capturePreparing: false
    property bool captureReady: false
    property var queuedAction: null

    function focusedScreen() {
        const name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        const matches = Quickshell.screens.filter(screen => screen.name === name);
        return matches.length > 0 ? matches[0] : (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null);
    }

    function focusInputSoon() {
        Qt.callLater(() => keyCatcher.forceActiveFocus());
    }

    function openForScreen(targetScreen) {
        if (targetScreen)
            powerWindow.screen = targetScreen;
        capturePreparing = false;
        captureReady = false;
        queuedAction = null;
        visualReady = true;
        powerWindow.visible = true;
        focusInputSoon();
    }

    function armForScreen(targetScreen) {
        if (targetScreen)
            powerWindow.screen = targetScreen;
        capturePreparing = true;
        captureReady = false;
        queuedAction = null;
        visualReady = false;
        powerWindow.visible = true;
        focusInputSoon();
    }

    function beginFocused() {
        if (powerWindow.visible) {
            close();
            return false;
        }
        armForScreen(focusedScreen());
        return true;
    }

    function openFocused() { openForScreen(focusedScreen()); }
    function discardPreparedCapture() {
        Quickshell.execDetached(["bash", lockCaptureHelper, "discard-prepared"]);
    }
    function close() {
        if (actionPending)
            return;
        capturePreparing = false;
        captureReady = false;
        queuedAction = null;
        visualReady = false;
        powerWindow.visible = false;
        discardPreparedCapture();
    }
    function finishHandoffClose() {
        actionPending = false;
        closeAfterActionSuccess = false;
        capturePreparing = false;
        captureReady = false;
        queuedAction = null;
        visualReady = false;
        powerWindow.visible = false;
    }
    function toggleForScreen(targetScreen) {
        if (!FlyoutManager.acceptToggle("power"))
            return;
        powerWindow.visible ? close() : openForScreen(targetScreen);
    }
    function toggleFocused() { toggleForScreen(focusedScreen()); }

    function captureWanted() {
        return powerWindow.visible && capturePreparing;
    }

    function capturePrepared() {
        if (!powerWindow.visible || !capturePreparing)
            return false;

        capturePreparing = false;
        captureReady = true;
        if (queuedAction !== null) {
            const action = queuedAction;
            queuedAction = null;
            startAction(action, "");
        }
        return true;
    }

    function captureFailed() {
        if (!powerWindow.visible || !capturePreparing)
            return;

        capturePreparing = false;
        captureReady = false;
        if (queuedAction !== null) {
            const action = queuedAction;
            queuedAction = null;
            startAction(action, freshLockCommand);
        }
    }

    function reveal() {
        if (!powerWindow.visible || actionPending || queuedAction !== null)
            return;
        visualReady = true;
    }

    function startAction(action, commandOverride) {
        actionPending = true;
        closeAfterActionSuccess = action.closeAfterSuccess === true;
        if (action.key !== "l")
            discardPreparedCapture();
        const selectedCommand = commandOverride && commandOverride.length > 0
            ? commandOverride
            : action.command;
        actionProcess.command = ["sh", "-lc", selectedCommand];
        actionProcess.running = true;
    }

    function runAction(action) {
        if (actionPending || queuedAction !== null)
            return;

        if (capturePreparing && action.key === "l") {
            queuedAction = action;
            return;
        }

        if (capturePreparing)
            capturePreparing = false;
        startAction(action, "");
    }

    Process {
        id: actionProcess

        onExited: exitCode => {
            if (exitCode !== 0) {
                root.actionPending = false;
                root.closeAfterActionSuccess = false;
                root.visualReady = true;
                root.focusInputSoon();
                return;
            }

            if (root.closeAfterActionSuccess)
                root.finishHandoffClose();
        }
    }

    IpcHandler {
        target: "powermenu"
        function begin(): bool { return root.beginFocused(); }
        function captureWanted(): bool { return root.captureWanted(); }
        function capturePrepared(): bool { return root.capturePrepared(); }
        function captureFailed(): void { root.captureFailed(); }
        function reveal(): void { root.reveal(); }
        function toggle(): void { root.toggleFocused(); }
        function open(): void { root.openFocused(); }
        function close(): void { root.close(); }
    }

    PanelWindow {
        id: powerWindow
        visible: false
        color: "transparent"
        focusable: true
        aboveWindows: true
        exclusionMode: ExclusionMode.Ignore
        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true

        MouseArea {
            anchors.fill: parent
            visible: root.visualReady
            onClicked: root.close()
        }

        Rectangle {
            anchors.fill: parent
            visible: root.visualReady
            color: root.shadeColor
            border.width: 0
        }

        Item {
            id: keyCatcher
            anchors.fill: parent
            focus: powerWindow.visible

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    root.close();
                    event.accepted = true;
                    return;
                }

                // Lowercase the typed character so Caps Lock no longer breaks
                // the existing l/h/r/s/o/z shortcuts.
                const typed = event.text ? event.text.toLowerCase() : "";
                for (let i = 0; i < root.actions.length; ++i) {
                    if (typed === root.actions[i].key) {
                        root.runAction(root.actions[i]);
                        event.accepted = true;
                        return;
                    }
                }
            }
        }

        GridLayout {
            anchors.centerIn: parent
            visible: root.visualReady
            columns: 3
            rowSpacing: 34
            columnSpacing: 16

            Repeater {
                model: root.actions

                delegate: Rectangle {
                    id: actionTile
                    required property var modelData

                    Layout.preferredWidth: Math.min(320, Math.max(230, powerWindow.width * 0.17))
                    Layout.preferredHeight: Math.min(220, Math.max(165, powerWindow.height * 0.20))
                    Layout.minimumWidth: Layout.preferredWidth
                    Layout.maximumWidth: Layout.preferredWidth
                    Layout.minimumHeight: Layout.preferredHeight
                    Layout.maximumHeight: Layout.preferredHeight

                    radius: 0
                    color: hover.containsMouse ? Theme.popupButtonHover : Theme.popupButton
                    border.width: 0

                    Column {
                        anchors.centerIn: parent
                        spacing: 14

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: actionTile.modelData.label
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: 54
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: actionTile.modelData.text
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: 17
                            font.weight: Font.Medium
                        }
                    }

                    MouseArea {
                        id: hover
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.runAction(actionTile.modelData)
                    }
                }
            }
        }
    }

    Variants {
        id: secondaryShadeVariants
        model: Quickshell.screens

        PanelWindow {
            id: secondaryShadeWindow
            required property var modelData

            screen: modelData
            visible: root.visualReady
                && powerWindow.visible
                && powerWindow.screen
                && modelData.name !== powerWindow.screen.name
            color: "transparent"
            focusable: false
            aboveWindows: true
            exclusionMode: ExclusionMode.Ignore
            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            MouseArea {
                anchors.fill: parent
                onClicked: root.close()
            }

            Rectangle {
                anchors.fill: parent
                color: root.shadeColor
                border.width: 0
            }
        }
    }
}
