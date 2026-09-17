#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EDITOR = ROOT / "config/quickshell/awtarchy/LockscreenEditor.qml"


def replace_once(text, old, new, label):
    if new in text:
        return text
    if old not in text:
        raise SystemExit(f"missing anchor: {label}")
    return text.replace(old, new, 1)


text = EDITOR.read_text(encoding="utf-8")

text = replace_once(
    text,
    '''    property var draftSavedProfiles: []
    property string activeMonitorName: ""
''',
    '''    property var draftSavedProfiles: []
    property string selectedSavedConfigurationId: ""
    property string savedConfigurationNameDialogMode: ""
    property string savedConfigurationNameDraft: ""
    property string savedConfigurationConfirmMode: ""
    property string activeMonitorName: ""
''',
    "saved configuration editor state",
)

text = replace_once(
    text,
    '''        draftSavedProfiles = cloneSnapshot(savedProfiles) || [];
        draftSharedProfile = cloneSnapshot(shared) || ({});
''',
    '''        draftSavedProfiles = cloneSnapshot(savedProfiles) || [];
        selectedSavedConfigurationId = draftSavedProfiles.length > 0
            ? String(draftSavedProfiles[0].id || "") : "";
        savedConfigurationNameDialogMode = "";
        savedConfigurationNameDraft = "";
        savedConfigurationConfirmMode = "";
        draftSharedProfile = cloneSnapshot(shared) || ({});
''',
    "saved configuration session load",
)

functions = r'''    function savedConfigurationIndex(id) {
        const key = String(id || "");
        for (let i = 0; i < draftSavedProfiles.length; ++i) {
            if (String(draftSavedProfiles[i].id || "") === key)
                return i;
        }
        return -1;
    }

    function savedConfigurationSelectorModel() {
        const result = [];
        for (const entry of draftSavedProfiles)
            result.push(({ key: String(entry.id || ""), label: String(entry.name || "") }));
        return result;
    }

    function selectedSavedConfigurationIndex() {
        return savedConfigurationIndex(selectedSavedConfigurationId);
    }

    function savedConfigurationNameValid(value, ignoredId) {
        const name = String(value || "").trim();
        const points = Array.from(name);
        if (points.length < 1 || points.length > 64 || /[\u0000-\u001f\u007f-\u009f]/.test(name))
            return false;
        const lower = name.toLowerCase();
        const ignore = String(ignoredId || "");
        for (const entry of draftSavedProfiles) {
            if (String(entry.id || "") === ignore)
                continue;
            if (String(entry.name || "").toLowerCase() === lower)
                return false;
        }
        return true;
    }

    function nextSavedConfigurationId() {
        const stem = "profile-" + Date.now().toString(36);
        let candidate = stem;
        let suffix = 0;
        while (savedConfigurationIndex(candidate) >= 0) {
            suffix++;
            candidate = stem + "-" + suffix;
        }
        return candidate;
    }

    function openSaveCurrentConfigurationDialog() {
        if (draftSavedProfiles.length >= 32) {
            statusMessage = "Saved configuration limit reached";
            return;
        }
        savedConfigurationNameDraft = "";
        savedConfigurationNameDialogMode = "create";
    }

    function confirmSaveCurrentConfiguration() {
        if (savedConfigurationNameDialogMode !== "create")
            return;
        const name = String(savedConfigurationNameDraft || "").trim();
        if (!savedConfigurationNameValid(name, "")) {
            statusMessage = "Configuration name must be unique and non-empty";
            return;
        }
        const profile = cloneSnapshot(profileFromDraftScalars());
        if (!profile) {
            statusMessage = "Could not snapshot current configuration";
            return;
        }
        const id = nextSavedConfigurationId();
        const next = cloneSnapshot(draftSavedProfiles) || [];
        next.push(({ id: id, name: name, profile: profile }));
        draftSavedProfiles = next;
        selectedSavedConfigurationId = id;
        savedConfigurationNameDialogMode = "";
        savedConfigurationNameDraft = "";
        statusMessage = "Saved configuration added. Ctrl+S to persist.";
    }

    function openRenameSavedConfigurationDialog() {
        const index = selectedSavedConfigurationIndex();
        if (index < 0)
            return;
        savedConfigurationNameDraft = String(draftSavedProfiles[index].name || "");
        savedConfigurationNameDialogMode = "rename";
    }

    function confirmRenameSavedConfiguration() {
        if (savedConfigurationNameDialogMode !== "rename")
            return;
        const index = selectedSavedConfigurationIndex();
        if (index < 0) {
            savedConfigurationNameDialogMode = "";
            return;
        }
        const id = String(draftSavedProfiles[index].id || "");
        const name = String(savedConfigurationNameDraft || "").trim();
        if (!savedConfigurationNameValid(name, id)) {
            statusMessage = "Configuration name must be unique and non-empty";
            return;
        }
        const next = cloneSnapshot(draftSavedProfiles) || [];
        next[index].name = name;
        draftSavedProfiles = next;
        savedConfigurationNameDialogMode = "";
        savedConfigurationNameDraft = "";
        statusMessage = "Configuration renamed. Ctrl+S to persist.";
    }

    function cancelSavedConfigurationNameDialog() {
        savedConfigurationNameDialogMode = "";
        savedConfigurationNameDraft = "";
    }

    function requestDeleteSavedConfiguration() {
        if (selectedSavedConfigurationIndex() < 0)
            return;
        savedConfigurationConfirmMode = "delete";
    }

    function confirmDeleteSavedConfiguration() {
        if (savedConfigurationConfirmMode !== "delete")
            return;
        const index = selectedSavedConfigurationIndex();
        if (index < 0) {
            savedConfigurationConfirmMode = "";
            return;
        }
        const next = cloneSnapshot(draftSavedProfiles) || [];
        next.splice(index, 1);
        draftSavedProfiles = next;
        selectedSavedConfigurationId = next.length > 0
            ? String(next[Math.min(index, next.length - 1)].id || "") : "";
        savedConfigurationConfirmMode = "";
        statusMessage = "Configuration deleted. Ctrl+S to persist.";
    }

    function requestOverwriteSavedConfiguration() {
        if (selectedSavedConfigurationIndex() < 0)
            return;
        savedConfigurationConfirmMode = "overwrite";
    }

    function confirmOverwriteSavedConfiguration() {
        if (savedConfigurationConfirmMode !== "overwrite")
            return;
        const index = selectedSavedConfigurationIndex();
        if (index < 0) {
            savedConfigurationConfirmMode = "";
            return;
        }
        const profile = cloneSnapshot(profileFromDraftScalars());
        if (!profile) {
            savedConfigurationConfirmMode = "";
            statusMessage = "Could not snapshot current configuration";
            return;
        }
        const next = cloneSnapshot(draftSavedProfiles) || [];
        next[index].profile = profile;
        draftSavedProfiles = next;
        savedConfigurationConfirmMode = "";
        statusMessage = "Saved configuration overwritten. Ctrl+S to persist.";
    }

    function cancelSavedConfigurationConfirm() {
        savedConfigurationConfirmMode = "";
    }

    function moveSavedConfiguration(offset) {
        const index = selectedSavedConfigurationIndex();
        const target = index + Number(offset);
        if (index < 0 || !Number.isInteger(target) || target < 0 || target >= draftSavedProfiles.length)
            return;
        const next = cloneSnapshot(draftSavedProfiles) || [];
        const entry = next[index];
        next.splice(index, 1);
        next.splice(target, 0, entry);
        draftSavedProfiles = next;
        statusMessage = "Saved configuration order changed. Ctrl+S to persist.";
    }

    function applySavedConfigurationToMonitor(id, name) {
        const index = savedConfigurationIndex(id);
        const targetName = String(name || "");
        if (index < 0 || targetName.length === 0 || !connectedScreenByName(targetName))
            return;
        const profile = cloneSnapshot(draftSavedProfiles[index].profile);
        if (!profile)
            return;
        if (historyTransactionActive)
            commitHistoryTransaction();

        const targetIsActive = targetName === activeMonitorName;
        const targetWasIndividual = hasIndividualConfiguration(targetName);
        let before = null;
        if (targetIsActive) {
            before = editorSnapshot();
            stashHistoryForActiveProfile();
            stashAutoAccentsForActiveProfile();
        }
        flushActiveProfile();

        const next = Object.assign({}, draftMonitorOverrides);
        next[targetName] = cloneSnapshot(profile);
        draftMonitorOverrides = next;

        const accents = Object.assign({}, draftMonitorAutoAccents);
        delete accents[targetName];
        draftMonitorAutoAccents = accents;

        const undo = Object.assign({}, profileUndoStacks);
        const redo = Object.assign({}, profileRedoStacks);
        const historyKey = "monitor:" + targetName;
        if (targetIsActive) {
            const targetUndo = targetWasIndividual
                ? (cloneSnapshot(undo[historyKey]) || []) : [];
            undo[historyKey] = appendHistory(targetUndo, before);
            redo[historyKey] = [];
        } else {
            delete undo[historyKey];
            delete redo[historyKey];
        }
        profileUndoStacks = undo;
        profileRedoStacks = redo;

        if (targetIsActive) {
            loadProfileIntoDraft(profile);
            restoreHistoryForActiveProfile();
        }
        statusMessage = "Applied saved configuration to " + targetName + ". Ctrl+S to persist.";
    }

    function applySavedConfigurationToShared(id) {
        const index = savedConfigurationIndex(id);
        if (index < 0)
            return;
        const profile = cloneSnapshot(draftSavedProfiles[index].profile);
        if (!profile)
            return;
        if (historyTransactionActive)
            commitHistoryTransaction();

        const activeUsesShared = !hasIndividualConfiguration(activeMonitorName);
        const before = activeUsesShared ? editorSnapshot() : null;
        if (!activeUsesShared)
            flushActiveProfile();

        draftSharedProfile = cloneSnapshot(profile);
        settledSharedProfile = cloneSnapshot(profile);
        draftSharedAutoAccents = defaultAutoAccents();

        const undo = Object.assign({}, profileUndoStacks);
        const redo = Object.assign({}, profileRedoStacks);
        if (activeUsesShared) {
            undo.shared = appendHistory(cloneSnapshot(undoStack) || [], before);
            redo.shared = [];
        } else {
            delete undo.shared;
            delete redo.shared;
        }
        profileUndoStacks = undo;
        profileRedoStacks = redo;

        if (activeUsesShared) {
            loadProfileIntoDraft(profile);
            restoreHistoryForActiveProfile();
        }
        statusMessage = "Applied saved configuration to Shared. Ctrl+S to persist.";
    }

'''

text = replace_once(
    text,
    '    function copyConfigurationTo(name) {\n',
    functions + '    function copyConfigurationTo(name) {\n',
    "saved configuration actions",
)

modal_anchor = '''        Rectangle {
            id: editorFocus; anchors.fill: parent; color: "transparent"; focus: true; opacity: root.editorEntranceOpacity
'''
modal_block = '''        Rectangle {
            id: savedConfigurationNameDialogLayer
            anchors.fill: parent
            visible: root.savedConfigurationNameDialogMode.length > 0
            color: "#99000000"
            z: 10010

            MouseArea { anchors.fill: parent }

            Rectangle {
                anchors.centerIn: parent
                width: Math.min(parent.width - 40, 480)
                height: 190
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
                        text: root.savedConfigurationNameDialogMode === "rename"
                            ? "Rename Saved Configuration" : "Save Current Configuration"
                        color: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: 15
                        font.bold: true
                    }
                    TextField {
                        id: savedConfigurationNameField
                        Layout.fillWidth: true
                        text: root.savedConfigurationNameDraft
                        maximumLength: 64
                        selectByMouse: true
                        placeholderText: "Configuration name"
                        onTextChanged: root.savedConfigurationNameDraft = text
                    }
                    Item { Layout.fillHeight: true }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Item { Layout.fillWidth: true }
                        SettingsButton { label: "Cancel"; textSize: 9; onClicked: root.cancelSavedConfigurationNameDialog() }
                        SettingsButton {
                            label: root.savedConfigurationNameDialogMode === "rename" ? "Rename" : "Save Configuration"
                            textSize: 9
                            onClicked: {
                                if (root.savedConfigurationNameDialogMode === "rename")
                                    root.confirmRenameSavedConfiguration();
                                else
                                    root.confirmSaveCurrentConfiguration();
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            id: savedConfigurationConfirmLayer
            anchors.fill: parent
            visible: root.savedConfigurationConfirmMode.length > 0
            color: "#99000000"
            z: 10020

            MouseArea { anchors.fill: parent }

            Rectangle {
                anchors.centerIn: parent
                width: Math.min(parent.width - 40, 520)
                height: 210
                radius: 10
                color: Theme.popupBackground
                border.width: 1
                border.color: Theme.active

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 12
                    Text {
                        visible: root.savedConfigurationConfirmMode === "delete"
                        Layout.fillWidth: true
                        text: "Delete Saved Configuration?"
                        color: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: 15
                        font.bold: true
                    }
                    Text {
                        visible: root.savedConfigurationConfirmMode === "overwrite"
                        Layout.fillWidth: true
                        text: "Overwrite Saved Configuration?"
                        color: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: 15
                        font.bold: true
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.savedConfigurationConfirmMode === "delete"
                            ? "This removes the selected reusable configuration when you save."
                            : "This replaces the selected reusable configuration with the current display's complete visual configuration."
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
                        SettingsButton { label: "Cancel"; textSize: 9; onClicked: root.cancelSavedConfigurationConfirm() }
                        SettingsButton {
                            label: root.savedConfigurationConfirmMode === "delete" ? "Delete" : "Overwrite"
                            textSize: 9
                            onClicked: {
                                if (root.savedConfigurationConfirmMode === "delete")
                                    root.confirmDeleteSavedConfiguration();
                                else
                                    root.confirmOverwriteSavedConfiguration();
                            }
                        }
                    }
                }
            }
        }

'''
text = replace_once(text, modal_anchor, modal_block + modal_anchor, "saved configuration dialogs")

layout_old = '''                    RowLayout { Layout.fillWidth: true; spacing: 7; visible: root.activeDrawer === "layout"
                        SettingsButton { label: "Minimal"; textSize: 9; onClicked: root.applyLayoutPreset("minimal") }
                        SettingsButton { label: "Centered"; textSize: 9; onClicked: root.applyLayoutPreset("centered") }
                        SettingsButton { label: "Information"; textSize: 9; onClicked: root.applyLayoutPreset("information") }
                        SettingsButton { label: "Lower Third"; textSize: 9; onClicked: root.applyLayoutPreset("lower-third") }
                        SettingsButton { label: "Guides"; active: root.showEditorGrid; textSize: 9; onClicked: root.showEditorGrid = !root.showEditorGrid }
                        SettingsButton { label: "Restore Defaults"; textSize: 9; onClicked: root.resetDraft() }
                        Item { Layout.fillWidth: true }
                        Text { text: "Presets change layout and visibility only."; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 9; elide: Text.ElideRight }
                    }
'''
layout_new = '''                    RowLayout { Layout.fillWidth: true; spacing: 7; visible: root.activeDrawer === "layout"
                        SettingsButton { label: "Minimal"; textSize: 9; onClicked: root.applyLayoutPreset("minimal") }
                        SettingsButton { label: "Centered"; textSize: 9; onClicked: root.applyLayoutPreset("centered") }
                        SettingsButton { label: "Information"; textSize: 9; onClicked: root.applyLayoutPreset("information") }
                        SettingsButton { label: "Lower Third"; textSize: 9; onClicked: root.applyLayoutPreset("lower-third") }
                        SettingsButton { label: "Guides"; active: root.showEditorGrid; textSize: 9; onClicked: root.showEditorGrid = !root.showEditorGrid }
                        SettingsButton { label: "Restore Defaults"; textSize: 9; onClicked: root.resetDraft() }
                        Item { Layout.fillWidth: true }
                        Text { text: "Built-in presets change layout and visibility only."; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 9; elide: Text.ElideRight }
                    }

                    RowLayout { Layout.fillWidth: true; spacing: 7; visible: root.activeDrawer === "layout"
                        Text { text: "Saved Configurations"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 9 }
                        LockscreenCompactSelector {
                            popupBoundary: editorFocus
                            Layout.preferredWidth: 210
                            model: root.savedConfigurationSelectorModel()
                            enabled: root.draftSavedProfiles.length > 0
                            currentIndex: Math.max(0, root.selectedSavedConfigurationIndex())
                            onActivated: index => {
                                if (index >= 0 && index < root.draftSavedProfiles.length)
                                    root.selectedSavedConfigurationId = String(root.draftSavedProfiles[index].id || "");
                            }
                        }
                        SettingsButton { label: "Save Current Configuration"; textSize: 9; available: root.draftSavedProfiles.length < 32; onClicked: root.openSaveCurrentConfigurationDialog() }
                        SettingsButton { label: "Rename"; textSize: 9; available: root.selectedSavedConfigurationIndex() >= 0; onClicked: root.openRenameSavedConfigurationDialog() }
                        SettingsButton { label: "Delete"; textSize: 9; available: root.selectedSavedConfigurationIndex() >= 0; onClicked: root.requestDeleteSavedConfiguration() }
                        SettingsButton { label: "Move Up"; textSize: 9; available: root.selectedSavedConfigurationIndex() > 0; onClicked: root.moveSavedConfiguration(-1) }
                        SettingsButton { label: "Move Down"; textSize: 9; available: root.selectedSavedConfigurationIndex() >= 0 && root.selectedSavedConfigurationIndex() < root.draftSavedProfiles.length - 1; onClicked: root.moveSavedConfiguration(1) }
                        SettingsButton { label: "Overwrite"; textSize: 9; available: root.selectedSavedConfigurationIndex() >= 0; onClicked: root.requestOverwriteSavedConfiguration() }
                        Item { Layout.fillWidth: true }
                    }

                    RowLayout { Layout.fillWidth: true; spacing: 7; visible: root.activeDrawer === "layout" && root.selectedSavedConfigurationIndex() >= 0
                        Text { text: "Apply To"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 9 }
                        SettingsButton { label: "Shared Configuration"; textSize: 9; onClicked: root.applySavedConfigurationToShared(root.selectedSavedConfigurationId) }
                        Repeater {
                            model: Quickshell.screens
                            SettingsButton {
                                required property var modelData
                                label: String(modelData.name || "")
                                textSize: 9
                                onClicked: root.applySavedConfigurationToMonitor(root.selectedSavedConfigurationId, String(modelData.name || ""))
                            }
                        }
                        Item { Layout.fillWidth: true }
                        Text { text: "Applying to a display creates or replaces its Individual configuration."; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 8; elide: Text.ElideRight }
                    }
'''
text = replace_once(text, layout_old, layout_new, "saved configuration Layout controls")

EDITOR.write_text(text, encoding="utf-8")
