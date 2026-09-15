#!/usr/bin/env python3
from __future__ import annotations

import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def replace_once(path: str, old: str, new: str) -> None:
    target = ROOT / path
    text = target.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one match, found {count}: {old[:120]!r}")
    target.write_text(text.replace(old, new, 1))


editor = "config/quickshell/awtarchy/LockscreenEditor.qml"
replace_once(
    editor,
    '    property bool pickerSuspended: false\n    property string activeDrawer: ""',
    '    property bool pickerSuspended: false\n'
    '    property bool lockCaptureSuppressed: false\n'
    '    property bool lockCaptureRestoreEditor: false\n'
    '    property string activeDrawer: ""',
)
replace_once(
    editor,
    '    function openFocused() { openForScreen(focusedScreen()); }\n\n'
    '    function suspendForWallpaperPicker()',
    '''    function openFocused() { openForScreen(focusedScreen()); }

    function suppressForLockCapture() {
        if (lockCaptureSuppressed)
            return true;
        lockCaptureRestoreEditor = root.open && !root.pickerSuspended && editorWindow.visible;
        lockCaptureSuppressed = true;
        if (lockCaptureRestoreEditor) {
            FlyoutManager.releaseOverlay("lockscreen-editor");
            editorWindow.visible = false;
        }
        return true;
    }

    function lockCaptureBackingHidden() {
        if (editorWindow.backingWindowVisible)
            return false;
        for (let i = 0; i < editorPreviewVariants.instances.length; ++i) {
            const previewWindow = editorPreviewVariants.instances[i];
            if (previewWindow && previewWindow.backingWindowVisible)
                return false;
        }
        return true;
    }

    function restoreAfterLockCapture() {
        const shouldRestore = lockCaptureRestoreEditor && root.open && !root.pickerSuspended;
        lockCaptureRestoreEditor = false;
        lockCaptureSuppressed = false;
        if (shouldRestore) {
            editorWindow.visible = true;
            editorEntranceOpacity = 1;
            FlyoutManager.claimOverlay("lockscreen-editor");
            scheduleContrastRefresh();
            Qt.callLater(() => editorFocus.forceActiveFocus());
        }
        return true;
    }

    function suspendForWallpaperPicker()''',
)
replace_once(
    editor,
    '        elementOpacityBeforeOpaque = ({});\n        heldSettle.stop(); heldReleaseClear.stop();',
    '        elementOpacityBeforeOpaque = ({});\n'
    '        lockCaptureSuppressed = false; lockCaptureRestoreEditor = false;\n'
    '        heldSettle.stop(); heldReleaseClear.stop();',
)

shell = "config/quickshell/awtarchy/shell.qml"
replace_once(
    shell,
    '''    IpcHandler {
        target: "control"
        function ping(): string { return "ok"; }
        function reload(): void { Quickshell.reload(false); }
        function hardReload(): void { Quickshell.reload(true); }
        function quit(): void { Qt.quit(); }
        function beginBarDrag(monitor: string): void { root.beginBarDrag(monitor); }
        function previewBarDrag(monitor: string, candidate: string): void { root.previewBarDrag(monitor, candidate); }
        function finishBarDrag(monitor: string, candidate: string): void { root.finishBarDrag(monitor, candidate); }
        function cancelBarDrag(): void { root.cancelBarDrag(); }
        function barDragState(): string { return root.barDragState(); }
        function flyoutWidth(surface: string): int { return root.flyoutWidth(surface); }
        function flyoutHeight(surface: string): int { return root.flyoutHeight(surface); }
        function recentBarMonitor(): string { return FlyoutManager.recentBarMonitor(); }
    }
}''',
    '''    IpcHandler {
        target: "control"
        function ping(): string { return "ok"; }
        function reload(): void { Quickshell.reload(false); }
        function hardReload(): void { Quickshell.reload(true); }
        function quit(): void { Qt.quit(); }
        function beginBarDrag(monitor: string): void { root.beginBarDrag(monitor); }
        function previewBarDrag(monitor: string, candidate: string): void { root.previewBarDrag(monitor, candidate); }
        function finishBarDrag(monitor: string, candidate: string): void { root.finishBarDrag(monitor, candidate); }
        function cancelBarDrag(): void { root.cancelBarDrag(); }
        function barDragState(): string { return root.barDragState(); }
        function flyoutWidth(surface: string): int { return root.flyoutWidth(surface); }
        function flyoutHeight(surface: string): int { return root.flyoutHeight(surface); }
        function recentBarMonitor(): string { return FlyoutManager.recentBarMonitor(); }
    }

    IpcHandler {
        target: "lockcapture"
        function suppressEditor(): bool { return LockscreenEditor.suppressForLockCapture(); }
        function editorHidden(): bool { return LockscreenEditor.lockCaptureBackingHidden(); }
        function restoreEditor(): bool { return LockscreenEditor.restoreAfterLockCapture(); }
    }
}''',
)

surface = "config/quickshell/awtarchy-lock/LockSurface.qml"
replace_once(
    surface,
    '''    readonly property string captureSource: root.captureDirectory.length > 0
        && /^[A-Za-z0-9._-]+$/.test(root.captureOutputName)
        ? "file://" + root.captureDirectory + "/" + root.captureOutputName + ".png"
        : ""
    readonly property bool transitionComplete: !transitionLayer.running''',
    '''    readonly property string captureSource: root.captureDirectory.length > 0
        && /^[A-Za-z0-9._-]+$/.test(root.captureOutputName)
        ? "file://" + root.captureDirectory + "/" + root.captureOutputName + ".png"
        : ""
    readonly property string transitionCaptureSource: root.captureDirectory.length > 0
        && /^[A-Za-z0-9._-]+$/.test(root.captureOutputName)
        ? "file://" + root.captureDirectory + "/" + root.captureOutputName + ".transition.png"
        : ""
    readonly property bool transitionComplete: !transitionLayer.running''',
)
replace_once(
    surface,
    '''    Item {
        id: securePresentation
        anchors.fill: parent

        // This backing is deliberately opaque even when capture loading fails.''',
    '''    // Keep the dirty/current-screen transition source outside the visible
    // secure composition. ShaderEffectSource can sample it, but background
    // transparency in LockScene can only reveal the clean desktop backing.
    Item {
        id: transitionBacking
        x: root.width + 64
        y: 0
        width: root.width
        height: root.height

        Rectangle {
            anchors.fill: parent
            color: "#000000"
        }

        Image {
            anchors.fill: parent
            source: root.transitionCaptureSource
            asynchronous: false
            cache: false
            fillMode: Image.Stretch
            visible: status === Image.Ready
        }
    }

    Item {
        id: securePresentation
        anchors.fill: parent

        // This backing is deliberately opaque even when capture loading fails.''',
)
replace_once(surface, '        startSource: desktopBacking\n', '        startSource: transitionBacking\n')

power = "config/quickshell/awtarchy/PowerMenu.qml"
replace_once(
    power,
    '    id: root\n\n    // Preserve the existing wlogout layout order and keybinds.',
    '''    id: root

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME")
        || (Quickshell.env("HOME") + "/.config")
    readonly property string lockCaptureHelper: configHome + "/hypr/scripts/quickshell_lockscreen_capture.sh"

    // Preserve the existing wlogout layout order and keybinds.''',
)
replace_once(
    power,
    '''    function openFocused() { openForScreen(focusedScreen()); }
    function close() {
        if (actionPending)
            return;
        powerWindow.visible = false;
    }''',
    '''    function openFocused() { openForScreen(focusedScreen()); }
    function discardPreparedCapture() {
        Quickshell.execDetached(["bash", lockCaptureHelper, "discard-prepared"]);
    }
    function close() {
        if (actionPending)
            return;
        powerWindow.visible = false;
        discardPreparedCapture();
    }''',
)
replace_once(
    power,
    '''        actionPending = true;
        closeAfterActionSuccess = action.closeAfterSuccess === true;
        actionProcess.command = ["sh", "-lc", action.command];''',
    '''        actionPending = true;
        closeAfterActionSuccess = action.closeAfterSuccess === true;
        if (action.key !== "l")
            discardPreparedCapture();
        actionProcess.command = ["sh", "-lc", action.command];''',
)

# Append exact current stock hashes for every managed file changed by this pass.
history_path = ROOT / "local/share/awtarchy/quickshell-managed-history.sha256"
history = history_path.read_text()
managed = {
    "config/hypr/scripts/quickshell_lockscreen_capture.sh": ".config/hypr/scripts/quickshell_lockscreen_capture.sh",
    "config/hypr/scripts/quickshell_power_menu.sh": ".config/hypr/scripts/quickshell_power_menu.sh",
    "config/quickshell/awtarchy/shell.qml": ".config/quickshell/awtarchy/shell.qml",
    "config/quickshell/awtarchy/LockscreenEditor.qml": ".config/quickshell/awtarchy/LockscreenEditor.qml",
    "config/quickshell/awtarchy/PowerMenu.qml": ".config/quickshell/awtarchy/PowerMenu.qml",
    "config/quickshell/awtarchy-lock/LockSurface.qml": ".config/quickshell/awtarchy-lock/LockSurface.qml",
}
lines = []
for repo_path, home_path in managed.items():
    digest = hashlib.sha256((ROOT / repo_path).read_bytes()).hexdigest()
    record = f"{digest}\t{home_path}"
    if record not in history:
        lines.append(record)
if lines:
    history_path.write_text(history.rstrip("\n") + "\n" + "\n".join(lines) + "\n")
