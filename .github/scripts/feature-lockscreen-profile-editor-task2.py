#!/usr/bin/env python3
from pathlib import Path
import re

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
    '    property var draftMonitorAutoAccents: ({})\n',
    '    property var draftMonitorAutoAccents: ({})\n'
    '    property var settledSharedProfile: ({})\n'
    '    property bool sharedPreviewHoldActive: false\n',
    'settled Shared properties',
)

anchor = '''    function activeProfileKey() {
'''
helpers = '''    function beginSharedPreviewHold() {
        if (hasIndividualConfiguration(activeMonitorName) || sharedPreviewHoldActive)
            return;
        settledSharedProfile = cloneSnapshot(profileFromDraftScalars())
            || cloneSnapshot(draftSharedProfile) || ({});
        sharedPreviewHoldActive = true;
    }

    function settleSharedPreviewHold() {
        if (!sharedPreviewHoldActive)
            return;
        sharedPreviewHoldActive = false;
        if (!hasIndividualConfiguration(activeMonitorName))
            settledSharedProfile = cloneSnapshot(profileFromDraftScalars())
                || cloneSnapshot(draftSharedProfile) || ({});
    }

    function activeProfileKey() {
'''
replace_once(anchor, helpers, 'Shared preview helpers')

old_effective = '''        if (!hasIndividualConfiguration(activeMonitorName))
            return profileFromDraftScalars();
        return cloneSnapshot(draftSharedProfile);
'''
new_effective = '''        if (!hasIndividualConfiguration(activeMonitorName)) {
            if (sharedPreviewHoldActive)
                return cloneSnapshot(settledSharedProfile);
            return profileFromDraftScalars();
        }
        return cloneSnapshot(draftSharedProfile);
'''
replace_once(old_effective, new_effective, 'effective Shared profile gate')

old_load = '''        draftSharedProfile = cloneSnapshot(shared) || ({});
        draftMonitorOverrides = cloneSnapshot(overrides) || ({});
'''
new_load = '''        draftSharedProfile = cloneSnapshot(shared) || ({});
        settledSharedProfile = cloneSnapshot(draftSharedProfile) || ({});
        sharedPreviewHoldActive = false;
        draftMonitorOverrides = cloneSnapshot(overrides) || ({});
'''
replace_once(old_load, new_load, 'persisted Shared snapshot initialization')

# Rotation lifecycle.
pattern = r'(function beginRotateElement\(name, sceneX, sceneY\)\s*\{.*?\n\s*beginHistoryTransaction\(\);)(\n\s*\})'
match = re.search(pattern, text, re.S)
if not match:
    raise SystemExit('could not locate beginRotateElement')
if 'beginSharedPreviewHold();' not in match.group(0):
    text, count = re.subn(pattern, r'\1\n        beginSharedPreviewHold();\2', text, count=1, flags=re.S)
    if count != 1:
        raise SystemExit('could not patch beginRotateElement')

old_end_rotate = '''        rotationElementName = "";
        commitHistoryTransaction();
        scheduleContrastRefresh();
'''
new_end_rotate = '''        rotationElementName = "";
        commitHistoryTransaction();
        settleSharedPreviewHold();
        scheduleContrastRefresh();
'''
replace_once(old_end_rotate, new_end_rotate, 'endRotateElement')

# Resize lifecycle. Freeze before the optional group-resize early return so both
# group and single-element resize use the same passive-preview behavior.
old_begin_resize = '''    function beginResizeElement(name, sceneX, sceneY) {
        if (!elementExists(name) || editorFocus.width<=0 || editorFocus.height<=0) return;
        if (selectedContains(name) && selectedElements.length>1 && beginGroupResize(sceneX,sceneY)) return;
'''
new_begin_resize = '''    function beginResizeElement(name, sceneX, sceneY) {
        if (!elementExists(name) || editorFocus.width<=0 || editorFocus.height<=0) return;
        beginSharedPreviewHold();
        if (selectedContains(name) && selectedElements.length>1 && beginGroupResize(sceneX,sceneY)) return;
'''
replace_once(old_begin_resize, new_begin_resize, 'beginResizeElement')

old_end_resize = '''    function endResizeElement() {
        if (resizeElementName.length===0) return;
        resizeElementName=""; resizeGroupSnapshot=[]; commitHistoryTransaction();
    }
'''
new_end_resize = '''    function endResizeElement() {
        if (resizeElementName.length===0) return;
        resizeElementName=""; resizeGroupSnapshot=[]; commitHistoryTransaction();
        settleSharedPreviewHold();
    }
'''
replace_once(old_end_resize, new_end_resize, 'endResizeElement')

old_begin_visualizer = '''        visualizerWidthResizeActive = true;
        beginHistoryTransaction();
'''
new_begin_visualizer = '''        visualizerWidthResizeActive = true;
        beginHistoryTransaction();
        beginSharedPreviewHold();
'''
replace_once(old_begin_visualizer, new_begin_visualizer, 'beginVisualizerWidthResize')

old_end_visualizer = '''        visualizerWidthResizeActive = false;
        commitHistoryTransaction();
        scheduleContrastRefresh();
'''
new_end_visualizer = '''        visualizerWidthResizeActive = false;
        commitHistoryTransaction();
        settleSharedPreviewHold();
        scheduleContrastRefresh();
'''
replace_once(old_end_visualizer, new_end_visualizer, 'endVisualizerWidthResize')

# Element drag starts only after the threshold, so selection clicks still do not
# freeze or publish Shared previews.
old_drag_start = '''                                dragActivated = true;
                                root.beginHistoryTransaction();
'''
new_drag_start = '''                                dragActivated = true;
                                root.beginHistoryTransaction();
                                root.beginSharedPreviewHold();
'''
replace_once(old_drag_start, new_drag_start, 'drag threshold hold')

# Non-flick release publishes immediately.
old_release = '''                                parent.inertiaActive = false;
                                root.commitHistoryTransaction();
                            }
                            dragActivated = false;
'''
new_release = '''                                parent.inertiaActive = false;
                                root.commitHistoryTransaction();
                                root.settleSharedPreviewHold();
                            }
                            dragActivated = false;
'''
replace_once(old_release, new_release, 'drag release settle')

# Cancelling an active inertia transaction before a new press publishes its last
# settled position before the next gesture begins.
old_press_inertia = '''                            if (root.inertiaOwner.length > 0) {
                                root.inertiaOwner = "";
                                root.commitHistoryTransaction();
                            }
'''
new_press_inertia = '''                            if (root.inertiaOwner.length > 0) {
                                root.inertiaOwner = "";
                                root.commitHistoryTransaction();
                                root.settleSharedPreviewHold();
                            }
'''
replace_once(old_press_inertia, new_press_inertia, 'interrupt inertia settle')

# Pointer cancellation should not leave passive Shared previews frozen.
old_cancel = '''                            if (dragActivated) {
                                root.endEditorHold(parent.elementName);
                                root.commitHistoryTransaction();
                            }
                            dragActivated = false;
'''
new_cancel = '''                            if (dragActivated) {
                                root.endEditorHold(parent.elementName);
                                root.commitHistoryTransaction();
                                root.settleSharedPreviewHold();
                            }
                            dragActivated = false;
'''
replace_once(old_cancel, new_cancel, 'drag cancel settle')

# Inertia completion is the true final drag position. Keep the hold active until
# velocity falls below the stop threshold, then publish once.
old_inertia_tail = 'if (root.inertiaOwner === parent.elementName) root.inertiaOwner = ""; root.commitHistoryTransaction(); } }\n'
new_inertia_tail = 'if (root.inertiaOwner === parent.elementName) root.inertiaOwner = ""; root.commitHistoryTransaction(); root.settleSharedPreviewHold(); } }\n'
replace_once(old_inertia_tail, new_inertia_tail, 'inertia settle')

# Saving during an active transaction must not strand passive previews.
save_anchor = '''        if (historyTransactionActive)
            commitHistoryTransaction();
        stashHistoryForActiveProfile();
        flushActiveProfile();
        saveErrorMessage = "";
'''
save_replacement = '''        if (historyTransactionActive)
            commitHistoryTransaction();
        settleSharedPreviewHold();
        stashHistoryForActiveProfile();
        flushActiveProfile();
        saveErrorMessage = "";
'''
replace_once(save_anchor, save_replacement, 'save defensive settle')

PATH.write_text(text, encoding="utf-8")
