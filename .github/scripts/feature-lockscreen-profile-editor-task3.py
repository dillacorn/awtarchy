#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PATH = ROOT / "config/quickshell/awtarchy/LockscreenEditor.qml"
text = PATH.read_text(encoding="utf-8")


def replace_once(old, new, label):
    global text
    if new in text:
        return
    if old not in text:
        raise SystemExit(f"missing anchor: {label}")
    text = text.replace(old, new, 1)


replace_once(
    '    property bool sharedPreviewHoldActive: false\n',
    '    property bool sharedPreviewHoldActive: false\n'
    '    property bool sharedSwitchConfirmOpen: false\n'
    '    property string sharedSwitchMonitorName: ""\n',
    'Shared switch properties',
)

old_function = '''    function useSharedConfiguration() {
        if (activeMonitorName.length === 0 || !hasIndividualConfiguration(activeMonitorName))
            return;
        if (historyTransactionActive)
            commitHistoryTransaction();
        stashHistoryForActiveProfile();
        stashAutoAccentsForActiveProfile();
        flushActiveProfile();
        const next = Object.assign({}, draftMonitorOverrides);
        delete next[activeMonitorName];
        draftMonitorOverrides = next;
        const nextAccents = Object.assign({}, draftMonitorAutoAccents);
        delete nextAccents[activeMonitorName];
        draftMonitorAutoAccents = nextAccents;
        loadProfileIntoDraft(draftSharedProfile);
        loadAutoAccentsForActiveProfile();
        restoreHistoryForActiveProfile();
        statusMessage = activeMonitorName + " now uses Shared configuration";
    }

'''
new_functions = '''    function useSharedConfiguration() {
        if (activeMonitorName.length === 0 || !hasIndividualConfiguration(activeMonitorName)
                || sharedSwitchConfirmOpen)
            return;
        if (historyTransactionActive)
            commitHistoryTransaction();
        settleSharedPreviewHold();
        stashHistoryForActiveProfile();
        stashAutoAccentsForActiveProfile();
        flushActiveProfile();
        sharedSwitchMonitorName = activeMonitorName;
        sharedSwitchConfirmOpen = true;
        statusMessage = "Choose which configuration should become Shared";
    }

    function confirmUseExistingShared() {
        const targetName = sharedSwitchMonitorName;
        if (targetName.length === 0 || !hasIndividualConfiguration(targetName)) {
            cancelUseSharedConfiguration();
            return;
        }
        const next = Object.assign({}, draftMonitorOverrides);
        delete next[targetName];
        draftMonitorOverrides = next;
        const nextAccents = Object.assign({}, draftMonitorAutoAccents);
        delete nextAccents[targetName];
        draftMonitorAutoAccents = nextAccents;
        settledSharedProfile = cloneSnapshot(draftSharedProfile) || ({});
        sharedSwitchConfirmOpen = false;
        sharedSwitchMonitorName = "";
        if (activeMonitorName === targetName) {
            loadProfileIntoDraft(draftSharedProfile);
            loadAutoAccentsForActiveProfile();
            restoreHistoryForActiveProfile();
        }
        statusMessage = targetName + " now uses the existing Shared configuration";
    }

    function confirmPromoteIndividualToShared() {
        const targetName = sharedSwitchMonitorName;
        if (targetName.length === 0 || targetName !== activeMonitorName
                || !hasIndividualConfiguration(targetName)) {
            cancelUseSharedConfiguration();
            return;
        }
        const promoted = cloneSnapshot(profileFromDraftScalars());
        if (!promoted) {
            cancelUseSharedConfiguration();
            statusMessage = "Could not promote this display configuration";
            return;
        }
        const monitorHistoryKey = "monitor:" + targetName;
        const nextUndo = Object.assign({}, profileUndoStacks);
        const nextRedo = Object.assign({}, profileRedoStacks);
        nextUndo.shared = cloneSnapshot(nextUndo[monitorHistoryKey]) || cloneSnapshot(undoStack) || [];
        nextRedo.shared = cloneSnapshot(nextRedo[monitorHistoryKey]) || cloneSnapshot(redoStack) || [];
        profileUndoStacks = nextUndo;
        profileRedoStacks = nextRedo;
        draftSharedProfile = promoted;
        settledSharedProfile = cloneSnapshot(promoted) || ({});
        draftSharedAutoAccents = cloneAutoAccents(draftAutoAccents);
        const next = Object.assign({}, draftMonitorOverrides);
        delete next[targetName];
        draftMonitorOverrides = next;
        const nextAccents = Object.assign({}, draftMonitorAutoAccents);
        delete nextAccents[targetName];
        draftMonitorAutoAccents = nextAccents;
        sharedSwitchConfirmOpen = false;
        sharedSwitchMonitorName = "";
        loadProfileIntoDraft(promoted);
        loadAutoAccentsForActiveProfile();
        restoreHistoryForActiveProfile();
        statusMessage = targetName + " configuration is now the Shared configuration";
    }

    function cancelUseSharedConfiguration() {
        sharedSwitchConfirmOpen = false;
        sharedSwitchMonitorName = "";
        statusMessage = "Shared configuration switch cancelled";
    }

'''
replace_once(old_function, new_functions, 'useSharedConfiguration')

# Closing the editor discards the pending confirmation together with the rest of
# the unsaved editor session.
old_close = '''        elementOpacityBeforeOpaque = ({});
        lockCaptureSuppressed = false; lockCaptureRestoreEditor = false;
'''
new_close = '''        elementOpacityBeforeOpaque = ({});
        sharedSwitchConfirmOpen = false; sharedSwitchMonitorName = "";
        lockCaptureSuppressed = false; lockCaptureRestoreEditor = false;
'''
replace_once(old_close, new_close, 'close reset')

# The full-screen modal is a sibling of editorFocus with a high z-order. It
# blocks pointer interaction behind the warning while keeping the existing
# window-owned Ctrl+S/Escape shortcut contract unchanged.
focus_anchor = '''        Rectangle {
            id: editorFocus; anchors.fill: parent; color: "transparent"; focus: true; opacity: root.editorEntranceOpacity
'''
modal = '''        Rectangle {
            id: sharedSwitchDialogLayer
            anchors.fill: parent
            visible: root.sharedSwitchConfirmOpen
            color: "#99000000"
            z: 10000

            MouseArea { anchors.fill: parent }

            Rectangle {
                anchors.centerIn: parent
                width: Math.min(parent.width - 40, 620)
                height: 230
                radius: 10
                color: Theme.popupBackground
                border.width: 1
                border.color: Theme.active

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 12

                    Text {
                        Layout.fillWidth: true
                        text: "Switch to Shared Configuration?"
                        color: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: 15
                        font.bold: true
                    }
                    Text {
                        Layout.fillWidth: true
                        text: "Individual configuration will be removed for " + root.sharedSwitchMonitorName
                            + ". Choose which configuration should become the Shared starting point."
                        color: Theme.muted
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        wrapMode: Text.WordWrap
                    }
                    Item { Layout.fillHeight: true }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Item { Layout.fillWidth: true }
                        SettingsButton {
                            label: "Cancel"
                            textSize: 9
                            onClicked: root.cancelUseSharedConfiguration()
                        }
                        SettingsButton {
                            label: "Use Existing Shared"
                            textSize: 9
                            onClicked: root.confirmUseExistingShared()
                        }
                        SettingsButton {
                            label: "Use This Display as Shared"
                            textSize: 9
                            onClicked: root.confirmPromoteIndividualToShared()
                        }
                    }
                }
            }
        }

        Rectangle {
            id: editorFocus; anchors.fill: parent; color: "transparent"; focus: true; opacity: root.editorEntranceOpacity
'''
replace_once(focus_anchor, modal, 'Shared switch modal')

PATH.write_text(text, encoding="utf-8")
