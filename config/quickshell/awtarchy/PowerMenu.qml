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
    readonly property int visualFadeDuration: 120
    readonly property int lockHandoffPollInterval: 10
    readonly property int lockHandoffMaxAttempts: 200

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
    property real visualOpacity: 0.0
    property bool capturePreparing: false
    property bool captureReady: false
    property var queuedAction: null
    property var deferredLockAction: null
    property int lockHandoffAttempts: 0
    property bool lockEditorSuppressed: false

    function focusedScreen() {
        const name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        const matches = Quickshell.screens.filter(screen => screen.name === name);
        return matches.length > 0 ? matches[0] : (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null);
    }

    function focusInputSoon() {
        keyCatcher.forceActiveFocus();
        Qt.callLater(() => keyCatcher.forceActiveFocus());
    }

    function fadeVisualsIn() {
        visualOpacity = 0.0;
        visualReady = true;
        Qt.callLater(() => {
            if (powerWindow.visible && visualReady)
                visualOpacity = 1.0;
        });
    }

    function openForScreen(targetScreen) {
        if (targetScreen)
            powerWindow.screen = targetScreen;
        capturePreparing = false;
        captureReady = false;
        queuedAction = null;
        deferredLockAction = null;
        lockHandoffAttempts = 0;
        lockHandoffTimer.stop();
        actionPending = false;
        closeAfterActionSuccess = false;
        powerWindow.visible = true;
        fadeVisualsIn();
        focusInputSoon();
    }

    // Kept for IPC/backward compatibility with older callers. The normal
    // SUPER+P path no longer arms capture before presenting the menu.
    function armForScreen(targetScreen) {
        if (targetScreen)
            powerWindow.screen = targetScreen;
        capturePreparing = true;
        captureReady = false;
        queuedAction = null;
        visualOpacity = 0.0;
        visualReady = false;
        powerWindow.visible = true;
        focusInputSoon();
    }

    function beginFocused() {
        if (actionPending)
            return false;
        if (powerWindow.visible) {
            close();
            return false;
        }
        openForScreen(focusedScreen());
        return true;
    }

    function openFocused() { openForScreen(focusedScreen()); }
    function discardPreparedCapture() {
        Quickshell.execDetached(["bash", lockCaptureHelper, "discard-prepared"]);
    }
    function restoreSuppressedEditor() {
        if (!lockEditorSuppressed)
            return;
        lockEditorSuppressed = false;
        LockscreenEditor.restoreAfterLockCapture();
    }
    function close() {
        if (actionPending)
            return;
        lockHandoffTimer.stop();
        restoreSuppressedEditor();
        capturePreparing = false;
        captureReady = false;
        queuedAction = null;
        deferredLockAction = null;
        lockHandoffAttempts = 0;
        visualOpacity = 0.0;
        visualReady = false;
        powerWindow.visible = false;
        discardPreparedCapture();
    }
    function finishHandoffClose() {
        lockHandoffTimer.stop();
        restoreSuppressedEditor();
        actionPending = false;
        closeAfterActionSuccess = false;
        capturePreparing = false;
        captureReady = false;
        queuedAction = null;
        deferredLockAction = null;
        lockHandoffAttempts = 0;
        visualOpacity = 0.0;
        visualReady = false;
        powerWindow.visible = false;
    }
    function toggleForScreen(targetScreen) {
        if (actionPending || !FlyoutManager.acceptToggle("power"))
            return;
        powerWindow.visible ? close() : openForScreen(targetScreen);
    }
    function toggleFocused() { toggleForScreen(focusedScreen()); }

    function fastKey(key: string): bool {
        if (!powerWindow.visible)
            return false;

        const normalized = String(key || "").toLowerCase();
        if (normalized === "escape") {
            close();
            return true;
        }

        if (actionPending || queuedAction !== null || deferredLockAction !== null)
            return true;

        for (let i = 0; i < actions.length; ++i) {
            if (normalized === actions[i].key) {
                runAction(actions[i]);
                return true;
            }
        }
        return false;
    }

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
            startAction(action, action.key === "l" ? freshLockCommand : "");
        }
    }

    function reveal() {
        if (!powerWindow.visible || actionPending || queuedAction !== null)
            return;
        fadeVisualsIn();
    }

    function powerMenuBackingHidden() {
        if (powerWindow.backingWindowVisible)
            return false;
        for (let i = 0; i < secondaryShadeVariants.instances.length; ++i) {
            const shadeWindow = secondaryShadeVariants.instances[i];
            if (shadeWindow && shadeWindow.backingWindowVisible)
                return false;
        }
        return true;
    }

    function beginLockAction(action) {
        if (actionPending || deferredLockAction !== null)
            return;

        actionPending = true;
        closeAfterActionSuccess = true;
        capturePreparing = false;
        captureReady = false;
        queuedAction = null;
        deferredLockAction = action;
        lockHandoffAttempts = 0;
        lockEditorSuppressed = LockscreenEditor.suppressForLockCapture();

        // Remove every Power Menu surface before the frozen desktop capture.
        // The timer below waits for the real QsWindow backing objects to unmap;
        // hiding a QML item alone is not sufficient for a secure clean frame.
        visualOpacity = 0.0;
        visualReady = false;
        powerWindow.visible = false;
        lockHandoffTimer.restart();
    }

    function abortLockHandoff() {
        const targetScreen = powerWindow.screen || focusedScreen();
        lockHandoffTimer.stop();
        deferredLockAction = null;
        lockHandoffAttempts = 0;
        actionPending = false;
        closeAfterActionSuccess = false;
        restoreSuppressedEditor();
        openForScreen(targetScreen);
    }

    function startAction(action, commandOverride) {
        actionPending = true;
        closeAfterActionSuccess = action.closeAfterSuccess === true;
        if (action.key !== "l")
            discardPreparedCapture();
        if (commandOverride && commandOverride.length > 0)
            actionProcess.command = ["sh", "-lc", commandOverride];
        else
            actionProcess.command = ["sh", "-lc", action.command];
        actionProcess.running = true;
    }

    function runAction(action) {
        if (actionPending || queuedAction !== null || deferredLockAction !== null)
            return;

        if (action.key === "l") {
            beginLockAction(action);
            return;
        }

        if (capturePreparing) {
            queuedAction = action;
            return;
        }

        startAction(action, "");
    }

    Timer {
        id: lockHandoffTimer
        interval: root.lockHandoffPollInterval
        repeat: true
        onTriggered: {
            if (root.deferredLockAction === null) {
                stop();
                return;
            }

            if (root.powerMenuBackingHidden()
                    && LockscreenEditor.lockCaptureBackingHidden()) {
                const action = root.deferredLockAction;
                root.deferredLockAction = null;
                stop();
                root.startAction(action, root.freshLockCommand);
                return;
            }

            root.lockHandoffAttempts += 1;
            if (root.lockHandoffAttempts >= root.lockHandoffMaxAttempts)
                root.abortLockHandoff();
        }
    }

    Process {
        id: actionProcess

        onExited: exitCode => {
            if (exitCode !== 0) {
                const targetScreen = powerWindow.screen || root.focusedScreen();
                root.actionPending = false;
                root.closeAfterActionSuccess = false;
                root.restoreSuppressedEditor();
                root.openForScreen(targetScreen);
                return;
            }

            if (root.closeAfterActionSuccess)
                root.finishHandoffClose();
        }
    }

    IpcHandler {
        target: "powermenu"
        function begin(): bool { return root.beginFocused(); }
        function fastKey(key: string): bool { return root.fastKey(key); }
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
            opacity: root.visualOpacity
            color: root.shadeColor
            border.width: 0

            Behavior on opacity {
                NumberAnimation { duration: root.visualFadeDuration; easing.type: Easing.OutCubic }
            }
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
            opacity: root.visualOpacity
            columns: 3
            rowSpacing: 34
            columnSpacing: 16

            Behavior on opacity {
                NumberAnimation { duration: root.visualFadeDuration; easing.type: Easing.OutCubic }
            }

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
                opacity: root.visualOpacity
                color: root.shadeColor
                border.width: 0

                Behavior on opacity {
                    NumberAnimation { duration: root.visualFadeDuration; easing.type: Easing.OutCubic }
                }
            }
        }
    }
}
