pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

Singleton {
    id: root

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME")
        || (Quickshell.env("HOME") + "/.config")
    readonly property string stateBackend: configHome + "/hypr/scripts/quickshell_application_state.sh"
    readonly property string contrastBackend: configHome + "/hypr/scripts/quickshell_lockscreen_contrast.sh"
    readonly property string wallpaperPickerBackend: configHome + "/hypr/scripts/quickshell_lockscreen_wallpaper_picker.sh"
    readonly property bool open: editorWindow.visible
    readonly property var elementNames: ["logo", "time", "date", "username", "weather", "password"]

    property var draftLayout: defaultLayout()
    property var draftVisibility: defaultVisibility()
    property string draftBackgroundMode: "black"
    property string draftBackgroundColor: "#000000"
    property string draftWallpaperPath: ""
    property var draftAutoAccents: defaultAutoAccents()
    property string selectedElement: "logo"
    property string statusMessage: ""
    property bool elementPaletteOpen: false
    property bool backgroundPaletteOpen: false
    property bool contrastRefreshPending: false
    property string heldElement: ""
    property real heldScaleBoost: 1.0

    readonly property real flickThreshold: 0.80
    readonly property real flickVelocityCap: 2.50
    readonly property real flickFriction: 0.86
    readonly property real flickBounceDamping: 0.38
    readonly property real flickStopSpeed: 0.04
    readonly property int flickReleaseFreshnessMs: 80
    readonly property int historyLimit: 50
    readonly property real snapThreshold: 0.008
    readonly property real keyboardNudge: 0.002
    readonly property real keyboardNudgeLarge: 0.01

    property var undoStack: []
    property var redoStack: []
    property bool historyTransactionActive: false
    property var historyTransactionSnapshot: null
    property var selectedElements: ["logo"]
    property real guideX: -1
    property real guideY: -1
    property string inertiaOwner: ""

    function defaultLayout() {
        return ({
            logo: ({ x: 0.50, y: 0.34, scale: 1.0, color: "auto" }),
            time: ({ x: 0.50, y: 0.51, scale: 1.0, color: "auto" }),
            date: ({ x: 0.50, y: 0.555, scale: 1.0, color: "auto" }),
            username: ({ x: 0.50, y: 0.595, scale: 1.0, color: "auto" }),
            weather: ({ x: 0.50, y: 0.635, scale: 1.0, color: "auto" }),
            password: ({ x: 0.50, y: 0.70, scale: 1.0, color: "auto" })
        });
    }

    function defaultVisibility() {
        return ({
            logo: true,
            time: false,
            date: false,
            username: false,
            weather: false,
            password: true
        });
    }

    function defaultAutoAccents() {
        return ({
            logo: "#ffffff",
            time: "#ffffff",
            date: "#ffffff",
            username: "#ffffff",
            weather: "#ffffff",
            password: "#ffffff"
        });
    }

    function validHex(value) {
        return /^#[0-9a-f]{6}$/.test(String(value || "").toLowerCase());
    }

    function cloneSnapshot(snapshot) {
        try {
            return JSON.parse(JSON.stringify(snapshot));
        } catch (error) {
            return null;
        }
    }

    function editorSnapshot() {
        return ({
            layout: cloneLayout(draftLayout),
            visibility: cloneVisibility(draftVisibility),
            backgroundMode: draftBackgroundMode,
            backgroundColor: draftBackgroundColor,
            wallpaperPath: draftWallpaperPath
        });
    }

    function snapshotKey(snapshot) {
        try {
            return JSON.stringify(snapshot);
        } catch (error) {
            return "";
        }
    }

    function appendHistory(stack, snapshot) {
        const copy = cloneSnapshot(snapshot);
        if (!copy)
            return stack.slice();
        const next = stack.slice();
        if (next.length === 0 || snapshotKey(next[next.length - 1]) !== snapshotKey(copy))
            next.push(copy);
        while (next.length > historyLimit)
            next.shift();
        return next;
    }

    function restoreEditorSnapshot(snapshot) {
        if (!snapshot || typeof snapshot !== "object")
            return;
        draftLayout = cloneLayout(snapshot.layout);
        draftVisibility = cloneVisibility(snapshot.visibility);
        draftBackgroundMode = ["black", "wallpaper", "color"].indexOf(String(snapshot.backgroundMode)) >= 0
            ? String(snapshot.backgroundMode) : "black";
        draftBackgroundColor = validHex(snapshot.backgroundColor)
            ? String(snapshot.backgroundColor).toLowerCase() : "#000000";
        draftWallpaperPath = typeof snapshot.wallpaperPath === "string"
            ? snapshot.wallpaperPath : "";
        scheduleContrastRefresh();
    }

    function pushUndoSnapshot(snapshot) {
        if (!snapshot || snapshotKey(snapshot) === snapshotKey(editorSnapshot()))
            return;
        undoStack = appendHistory(undoStack, snapshot);
        redoStack = [];
    }

    function recordUndoBeforeChange() {
        if (!historyTransactionActive)
            pushUndoSnapshot(editorSnapshot());
    }

    function undo() {
        if (historyTransactionActive)
            commitHistoryTransaction();
        if (undoStack.length === 0)
            return;
        const current = editorSnapshot();
        const nextUndo = undoStack.slice();
        const target = nextUndo.pop();
        undoStack = nextUndo;
        redoStack = appendHistory(redoStack, current);
        restoreEditorSnapshot(target);
        statusMessage = "Undone";
    }

    function redo() {
        if (historyTransactionActive)
            commitHistoryTransaction();
        if (redoStack.length === 0)
            return;
        const current = editorSnapshot();
        const nextRedo = redoStack.slice();
        const target = nextRedo.pop();
        redoStack = nextRedo;
        undoStack = appendHistory(undoStack, current);
        restoreEditorSnapshot(target);
        statusMessage = "Redone";
    }

    function beginHistoryTransaction() {
        if (historyTransactionActive)
            commitHistoryTransaction();
        historyTransactionSnapshot = editorSnapshot();
        historyTransactionActive = true;
    }

    function commitHistoryTransaction() {
        if (!historyTransactionActive)
            return;
        const before = historyTransactionSnapshot;
        historyTransactionSnapshot = null;
        historyTransactionActive = false;
        if (before && snapshotKey(before) !== snapshotKey(editorSnapshot())) {
            undoStack = appendHistory(undoStack, before);
            redoStack = [];
        }
    }

    function selectedContains(name) {
        return selectedElements.indexOf(name) >= 0;
    }

    function selectElement(name, additive) {
        if (elementNames.indexOf(name) < 0)
            return;
        if (!additive) {
            selectedElement = name;
            selectedElements = [name];
            return;
        }
        const next = selectedElements.slice();
        const index = next.indexOf(name);
        if (index >= 0) {
            if (next.length > 1)
                next.splice(index, 1);
        } else {
            next.push(name);
        }
        selectedElements = next;
        selectedElement = selectedContains(name) ? name : next[0];
    }

    function primaryPoint() {
        return draftLayout[selectedElement] || defaultLayout()[selectedElement] || defaultLayout().logo;
    }

    function pointBounds(name) {
        const password = name === "password";
        return ({
            minX: password ? 0.15 : 0.05,
            maxX: password ? 0.85 : 0.95,
            minY: password ? 0.20 : 0.08,
            maxY: password ? 0.86 : 0.92
        });
    }

    function clampedGroupDelta(dx, dy) {
        let minDx = -2;
        let maxDx = 2;
        let minDy = -2;
        let maxDy = 2;
        for (const name of selectedElements) {
            const point = draftLayout[name] || defaultLayout()[name];
            const bounds = pointBounds(name);
            minDx = Math.max(minDx, bounds.minX - Number(point.x));
            maxDx = Math.min(maxDx, bounds.maxX - Number(point.x));
            minDy = Math.max(minDy, bounds.minY - Number(point.y));
            maxDy = Math.min(maxDy, bounds.maxY - Number(point.y));
        }
        return ({
            x: Math.max(minDx, Math.min(maxDx, Number(dx) || 0)),
            y: Math.max(minDy, Math.min(maxDy, Number(dy) || 0))
        });
    }

    function translateSelectedElements(dx, dy, selectPrimary) {
        const delta = clampedGroupDelta(dx, dy);
        if (Math.abs(delta.x) < 0.0000001 && Math.abs(delta.y) < 0.0000001)
            return delta;
        const next = cloneLayout(draftLayout);
        for (const name of selectedElements) {
            const point = next[name] || defaultLayout()[name];
            point.x = Number(point.x) + delta.x;
            point.y = Number(point.y) + delta.y;
            next[name] = point;
        }
        draftLayout = next;
        if (selectPrimary && selectedElements.length > 0 && !selectedContains(selectedElement))
            selectedElement = selectedElements[0];
        scheduleContrastRefresh();
        return delta;
    }

    function clearGuides() {
        guideX = -1;
        guideY = -1;
    }

    function snapPoint(name, x, y, bypassSnap) {
        const clamped = clampPoint(name, Number(x), Number(y));
        if (bypassSnap) {
            clearGuides();
            return clamped;
        }
        const xTargets = [0.5];
        const yTargets = [0.5];
        for (const peer of elementNames) {
            if (!root.selectedContains(peer)) {
                const point = draftLayout[peer] || defaultLayout()[peer];
                xTargets.push(Number(point.x));
                yTargets.push(Number(point.y));
            }
        }
        let snappedX = clamped.x;
        let snappedY = clamped.y;
        let bestX = snapThreshold + 1;
        let bestY = snapThreshold + 1;
        for (const target of xTargets) {
            const distance = Math.abs(clamped.x - target);
            if (distance <= snapThreshold && distance < bestX) {
                bestX = distance;
                snappedX = target;
            }
        }
        for (const target of yTargets) {
            const distance = Math.abs(clamped.y - target);
            if (distance <= snapThreshold && distance < bestY) {
                bestY = distance;
                snappedY = target;
            }
        }
        guideX = bestX <= snapThreshold ? snappedX : -1;
        guideY = bestY <= snapThreshold ? snappedY : -1;
        return clampPoint(name, snappedX, snappedY);
    }

    function nudgeSelection(dx, dy) {
        recordUndoBeforeChange();
        translateSelectedElements(dx, dy, true);
        clearGuides();
    }

    function setSelectedCoordinate(axis, percentValue) {
        const numeric = Number(percentValue);
        if (!Number.isFinite(numeric))
            return;
        const target = Math.max(0, Math.min(100, numeric)) / 100;
        const point = primaryPoint();
        recordUndoBeforeChange();
        if (axis === "x")
            translateSelectedElements(target - Number(point.x), 0, true);
        else if (axis === "y")
            translateSelectedElements(0, target - Number(point.y), true);
    }

    function setAllDraftColors(colorValue) {
        const value = String(colorValue || "").trim().toLowerCase();
        if (value !== "auto" && !validHex(value))
            return;
        recordUndoBeforeChange();
        const next = cloneLayout(draftLayout);
        for (const name of elementNames)
            next[name].color = value;
        draftLayout = next;
        statusMessage = value === "auto" ? "All elements use Auto contrast"
            : "All element colors updated";
    }

    function resetElementPosition(name) {
        if (elementNames.indexOf(name) < 0)
            return;
        recordUndoBeforeChange();
        const defaults = defaultLayout();
        const next = cloneLayout(draftLayout);
        next[name].x = defaults[name].x;
        next[name].y = defaults[name].y;
        draftLayout = next;
        selectedElement = name;
        statusMessage = elementLabel(name) + " position reset";
        scheduleContrastRefresh();
    }

    function setDraftBackgroundMode(mode) {
        const value = String(mode || "");
        if (["black", "wallpaper", "color"].indexOf(value) < 0)
            return;
        if (value === "wallpaper" && draftWallpaperPath.length === 0) {
            statusMessage = "Choose a lockscreen wallpaper first";
            return;
        }
        recordUndoBeforeChange();
        draftBackgroundMode = value;
        statusMessage = "";
        scheduleContrastRefresh();
    }

    function setDraftBackgroundColor(colorValue) {
        const value = String(colorValue || "").trim().toLowerCase();
        if (!validHex(value)) {
            statusMessage = "Background color must be #RRGGBB";
            return;
        }
        recordUndoBeforeChange();
        draftBackgroundColor = value;
        draftBackgroundMode = "color";
        statusMessage = "";
        scheduleContrastRefresh();
    }

    function acceptWallpaperSelection(line) {
        if (!open)
            return;
        const value = String(line || "").trim();
        if (!value.startsWith("/") || value.indexOf("://") >= 0) {
            statusMessage = "Awtwall returned an invalid local wallpaper";
            return;
        }
        recordUndoBeforeChange();
        draftWallpaperPath = value;
        draftBackgroundMode = "wallpaper";
        statusMessage = "Wallpaper selected. Save to apply.";
        scheduleContrastRefresh();
    }

    function scheduleContrastRefresh() {
        if (!open)
            return;
        contrastRefreshPending = true;
        contrastRefreshDelay.restart();
    }

    function refreshPreviewContrast() {
        if (!open)
            return;
        if (previewContrastProcess.running) {
            contrastRefreshPending = true;
            return;
        }
        contrastRefreshPending = false;
        previewContrastProcess.exec([
            "bash", contrastBackend, "--stdout",
            "--background", draftBackgroundMode,
            "--background-color", draftBackgroundColor,
            "--wallpaper", draftWallpaperPath,
            "--layout-json", JSON.stringify(draftLayout)
        ]);
    }

    function applyPreviewContrastLine(line) {
        try {
            const payload = JSON.parse(String(line || ""));
            if (!payload || payload.provider !== "awtarchy-local-contrast"
                    || !payload.colors || typeof payload.colors !== "object")
                return;
            const next = defaultAutoAccents();
            for (const name of elementNames) {
                const value = String(payload.colors[name] || "").toLowerCase();
                next[name] = validHex(value) ? value : "#ffffff";
            }
            draftAutoAccents = next;
        } catch (error) {
            // Keep the current safe preview colors on malformed helper output.
        }
    }

    function cloneObject(value, fallback) {
        try {
            const parsed = JSON.parse(JSON.stringify(value));
            return parsed && typeof parsed === "object" ? parsed : fallback();
        } catch (error) {
            return fallback();
        }
    }

    function cloneLayout(value) {
        const cloned = cloneObject(value, defaultLayout);
        const defaults = defaultLayout();
        const result = ({});
        for (const name of elementNames) {
            const raw = cloned[name] || defaults[name];
            const password = name === "password";
            const x = Number(raw.x);
            const y = Number(raw.y);
            const scale = Number(raw.scale === undefined ? 1 : raw.scale);
            const rawColor = String(raw.color === undefined ? "auto" : raw.color);
            const color = rawColor === "auto" || /^#[0-9a-fA-F]{6}$/.test(rawColor)
                ? rawColor.toLowerCase() : "auto";
            result[name] = ({
                x: Math.max(password ? 0.15 : 0.05,
                    Math.min(password ? 0.85 : 0.95,
                        Number.isFinite(x) ? x : defaults[name].x)),
                y: Math.max(password ? 0.20 : 0.08,
                    Math.min(password ? 0.86 : 0.92,
                        Number.isFinite(y) ? y : defaults[name].y)),
                scale: Math.max(0.50, Math.min(2.00,
                    Number.isFinite(scale) ? scale : 1)),
                color: color
            });
        }
        return result;
    }

    function cloneVisibility(value) {
        const defaults = defaultVisibility();
        const cloned = cloneObject(value, defaultVisibility);
        const result = ({});
        for (const name of elementNames)
            result[name] = name === "password" ? true
                : (typeof cloned[name] === "boolean" ? cloned[name] : defaults[name]);
        return result;
    }

    function clampPoint(name, x, y) {
        const password = name === "password";
        return ({
            x: Math.max(password ? 0.15 : 0.05, Math.min(password ? 0.85 : 0.95, x)),
            y: Math.max(password ? 0.20 : 0.08, Math.min(password ? 0.86 : 0.92, y))
        });
    }

    function writeDraftPoint(name, x, y, selectElement) {
        if (elementNames.indexOf(name) < 0)
            return;
        if (selectElement)
            recordUndoBeforeChange();
        const next = cloneLayout(draftLayout);
        const point = clampPoint(name, Number(x), Number(y));
        next[name] = ({
            x: point.x,
            y: point.y,
            scale: next[name].scale,
            color: next[name].color
        });
        draftLayout = next;
        if (selectElement)
            selectElement(name, false);
        scheduleContrastRefresh();
    }

    function setDraftPoint(name, x, y) {
        writeDraftPoint(name, x, y, true);
    }

    function setDraftPointSilently(name, x, y) {
        writeDraftPoint(name, x, y, false);
    }

    function cappedFlickVelocity(value) {
        const numeric = Number(value);
        const safe = Number.isFinite(numeric) ? numeric : 0;
        return Math.max(-flickVelocityCap, Math.min(flickVelocityCap, safe));
    }

    function shouldStartFlick(vx, vy) {
        return Math.sqrt(vx * vx + vy * vy) >= flickThreshold;
    }

    function animateHeldScale(targetScale, durationMs) {
        heldScaleAnimation.stop();
        heldScaleAnimation.from = heldScaleBoost;
        heldScaleAnimation.to = targetScale;
        heldScaleAnimation.duration = durationMs;
        heldScaleAnimation.start();
    }

    function beginEditorHold(name) {
        if (elementNames.indexOf(name) < 0)
            return;
        heldReleaseClear.stop();
        heldSettle.stop();
        heldElement = name;
        animateHeldScale(1.10, 65);
        heldSettle.restart();
    }

    function endEditorHold(name) {
        if (heldElement !== name)
            return;
        heldSettle.stop();
        animateHeldScale(1.0, 90);
        heldReleaseClear.restart();
    }

    function elementScale(name) {
        const point = draftLayout[name] || defaultLayout()[name];
        const value = Number(point.scale === undefined ? 1 : point.scale);
        return Number.isFinite(value) ? Math.max(0.50, Math.min(2.00, value)) : 1;
    }

    function elementColor(name) {
        const point = draftLayout[name] || defaultLayout()[name];
        const value = String(point.color === undefined ? "auto" : point.color);
        return value === "auto" || /^#[0-9a-fA-F]{6}$/.test(value)
            ? value.toLowerCase() : "auto";
    }

    function setDraftColor(name, colorValue) {
        if (elementNames.indexOf(name) < 0)
            return;
        const value = String(colorValue || "").trim().toLowerCase();
        if (value !== "auto" && !/^#[0-9a-f]{6}$/.test(value)) {
            statusMessage = "Color must be Auto or #RRGGBB";
            return;
        }
        recordUndoBeforeChange();
        const next = cloneLayout(draftLayout);
        next[name].color = value;
        draftLayout = next;
        selectElement(name, false);
        statusMessage = "";
    }

    function setDraftScale(name, scale) {
        if (elementNames.indexOf(name) < 0)
            return;
        recordUndoBeforeChange();
        const next = cloneLayout(draftLayout);
        const value = Number(scale);
        if (!Number.isFinite(value))
            return;
        next[name].scale = Math.round(Math.max(0.50, Math.min(2.00, value)) * 100) / 100;
        draftLayout = next;
        selectElement(name, false);
    }

    function elementCanHide(name) {
        return name !== "password";
    }

    function setDraftVisible(name, visible) {
        if (elementNames.indexOf(name) < 0 || !elementCanHide(name))
            return;
        recordUndoBeforeChange();
        const next = cloneVisibility(draftVisibility);
        next[name] = !!visible;
        draftVisibility = next;
        selectElement(name, false);
    }

    function elementEnabled(name) {
        return draftVisibility[name] !== false;
    }

    function resetDraft() {
        recordUndoBeforeChange();
        draftLayout = defaultLayout();
        draftVisibility = defaultVisibility();
        draftBackgroundMode = "black";
        draftBackgroundColor = "#000000";
        draftWallpaperPath = "";
        draftAutoAccents = defaultAutoAccents();
        selectedElement = "logo";
        selectedElements = ["logo"];
        clearGuides();
        elementPaletteOpen = false;
        backgroundPaletteOpen = false;
        statusMessage = "Defaults loaded. Save to apply.";
        scheduleContrastRefresh();
    }

    function loadPersistedDraft() {
        draftLayout = cloneLayout(BarState.lockscreenLayout());
        draftVisibility = cloneVisibility(({
            logo: BarState.lockscreenShowLogo(),
            time: BarState.lockscreenShowTime(),
            date: BarState.lockscreenShowDate(),
            username: BarState.lockscreenShowUsername(),
            weather: BarState.lockscreenShowWeather(),
            password: true
        }));
        draftBackgroundMode = BarState.lockscreenBackground();
        draftBackgroundColor = BarState.lockscreenBackgroundColor();
        draftWallpaperPath = BarState.lockscreenWallpaperPath();
        draftAutoAccents = defaultAutoAccents();
        selectedElement = elementNames.indexOf(selectedElement) >= 0 ? selectedElement : "logo";
        selectedElements = [selectedElement];
        clearGuides();
        elementPaletteOpen = false;
        backgroundPaletteOpen = false;
        statusMessage = "";
    }

    function focusedScreen() {
        const name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        const screens = Quickshell.screens || [];
        for (let i = 0; i < screens.length; ++i) {
            if (screens[i] && screens[i].name === name)
                return screens[i];
        }
        return screens.length > 0 ? screens[0] : null;
    }

    function openForScreen(target) {
        if (target)
            editorWindow.screen = target;
        loadPersistedDraft();
        undoStack = [];
        redoStack = [];
        historyTransactionActive = false;
        historyTransactionSnapshot = null;
        inertiaOwner = "";
        editorWindow.visible = true;
        FlyoutManager.claimOverlay("lockscreen-editor");
        scheduleContrastRefresh();
        Qt.callLater(() => editorFocus.forceActiveFocus());
    }

    function openFocused() {
        openForScreen(focusedScreen());
    }

    function close() {
        heldSettle.stop();
        heldReleaseClear.stop();
        heldScaleAnimation.stop();
        heldElement = "";
        heldScaleBoost = 1.0;
        inertiaOwner = "";
        historyTransactionActive = false;
        historyTransactionSnapshot = null;
        clearGuides();
        FlyoutManager.releaseOverlay("lockscreen-editor");
        editorWindow.visible = false;
        loadPersistedDraft();
    }

    function save() {
        if (saveProcess.running || contrastPersistProcess.running)
            return;
        statusMessage = "Saving…";
        saveProcess.exec([
            "bash",
            stateBackend,
            "save-lockscreen-editor",
            JSON.stringify(draftLayout),
            JSON.stringify(draftVisibility),
            draftBackgroundMode,
            draftBackgroundColor,
            draftWallpaperPath
        ]);
    }

    function elementLabel(name) {
        if (name === "logo") return "Logo";
        if (name === "time") return "Time";
        if (name === "date") return "Date";
        if (name === "username") return "Username";
        if (name === "weather") return "Weather";
        if (name === "password") return "Password";
        return name;
    }

    Process {
        id: saveProcess
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                BarState.refresh();
                root.statusMessage = "Refreshing Auto contrast…";
                contrastPersistProcess.exec(["bash", root.contrastBackend]);
            } else {
                root.statusMessage = "Could not save lockscreen presentation";
            }
        }
    }

    Process {
        id: contrastPersistProcess
        onExited: (exitCode, exitStatus) => {
            root.statusMessage = exitCode === 0 ? "Saved"
                : "Saved; Auto contrast cache could not refresh";
            closeAfterSave.restart();
        }
    }

    Timer {
        id: closeAfterSave
        interval: 180
        repeat: false
        onTriggered: root.close()
    }

    NumberAnimation {
        id: heldScaleAnimation
        target: root
        property: "heldScaleBoost"
        duration: 70
        easing.type: Easing.OutCubic
    }

    Timer {
        id: heldSettle
        interval: 70
        repeat: false
        onTriggered: {
            if (root.heldElement.length > 0)
                root.animateHeldScale(1.045, 70);
        }
    }

    Timer {
        id: heldReleaseClear
        interval: 110
        repeat: false
        onTriggered: {
            if (root.heldScaleBoost <= 1.005)
                root.heldElement = "";
        }
    }

    LockPreviewWallpaperState {
        id: wallpaperState
        path: root.draftWallpaperPath
    }

    Timer {
        id: contrastRefreshDelay
        interval: 120
        repeat: false
        onTriggered: root.refreshPreviewContrast()
    }

    Process {
        id: previewContrastProcess
        stdout: SplitParser {
            onRead: line => root.applyPreviewContrastLine(line)
        }
        onExited: (exitCode, exitStatus) => {
            if (root.contrastRefreshPending)
                contrastRefreshDelay.restart();
        }
    }

    Process {
        id: wallpaperPickerProcess
        stdout: SplitParser {
            onRead: line => root.acceptWallpaperSelection(line)
        }
        onExited: (exitCode, exitStatus) => {
            if (root.open && exitCode !== 0 && root.statusMessage.length === 0)
                root.statusMessage = "Lockscreen wallpaper picker closed";
        }
    }

    Shortcut {
        sequence: "Escape"
        context: Qt.ApplicationShortcut
        enabled: root.open
        autoRepeat: false
        onActivated: root.close()
    }

    Shortcut {
        sequence: "Ctrl+Z"
        context: Qt.ApplicationShortcut
        enabled: root.open && root.undoStack.length > 0
        autoRepeat: false
        onActivated: root.undo()
    }

    Shortcut {
        sequence: "Ctrl+Shift+Z"
        context: Qt.ApplicationShortcut
        enabled: root.open && root.redoStack.length > 0
        autoRepeat: false
        onActivated: root.redo()
    }

    Shortcut {
        sequence: "Ctrl+Y"
        context: Qt.ApplicationShortcut
        enabled: root.open && root.redoStack.length > 0
        autoRepeat: false
        onActivated: root.redo()
    }

    PanelWindow {
        id: editorWindow
        WlrLayershell.namespace: "awtarchy-lockscreen-editor"
        visible: false
        color: "transparent"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        aboveWindows: true
        exclusionMode: ExclusionMode.Ignore
        anchors.top: true
        anchors.left: true
        implicitWidth: Math.max(1, screen ? screen.width : 1920)
        implicitHeight: Math.max(1, screen ? screen.height : 1080)

        Rectangle {
            id: editorFocus
            anchors.fill: parent
            color: "#000000"
            focus: true

            Keys.onPressed: event => {
                const step = event.modifiers & Qt.ShiftModifier
                    ? root.keyboardNudgeLarge : root.keyboardNudge;
                if (event.key === Qt.Key_Left) {
                    root.nudgeSelection(-step, 0);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Right) {
                    root.nudgeSelection(step, 0);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Up) {
                    root.nudgeSelection(0, -step);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Down) {
                    root.nudgeSelection(0, step);
                    event.accepted = true;
                }
            }

            LockPreviewScene {
                id: previewScene
                anchors.fill: parent
                theme: Theme
                animationPreference: BarState.lockscreenAnimationPreference()
                randomFormationMode: 3
                audioReactive: false
                audioLow: 0
                audioMid: 0
                audioHigh: 0
                audioOverall: 0
                mouseInteractive: BarState.lockscreenMouseInteractiveEnabled()
                showLogo: root.draftVisibility.logo
                showTime: root.draftVisibility.time
                showDate: root.draftVisibility.date
                showUsername: root.draftVisibility.username
                showWeather: root.draftVisibility.weather
                weatherText: "72°F · Clear"
                backgroundMode: root.draftBackgroundMode
                wallpaperSource: wallpaperState.source
                backgroundColor: root.draftBackgroundColor
                autoAccents: root.draftAutoAccents
                layout: root.draftLayout
                previewMode: true
                editorMode: true
                editorVisibility: root.draftVisibility
                editorHeldElement: root.heldElement
                editorHoldScale: root.heldScaleBoost
            }

            Repeater {
                model: root.elementNames

                Rectangle {
                    required property string modelData
                    readonly property string elementName: modelData
                    readonly property bool enabledElement: root.elementEnabled(elementName)
                    readonly property var point: root.draftLayout[elementName]
                        || root.defaultLayout()[elementName]
                    width: Math.max(30, previewScene.elementVisualWidth(elementName) + 14)
                    height: Math.max(26, previewScene.elementVisualHeight(elementName) + 12)
                    x: Math.max(0, Math.min(parent.width - width,
                        Number(point.x) * parent.width - width / 2))
                    y: Math.max(0, Math.min(parent.height - height,
                        Number(point.y) * parent.height - height / 2))
                    color: "transparent"
                    border.width: root.selectedContains(elementName) ? 2 : 1
                    border.color: root.selectedContains(elementName) ? Theme.focus : Theme.muted
                    opacity: 0.92
                    z: 200
                    property real lastSampleTime: 0
                    property real lastSampleX: 0
                    property real lastSampleY: 0
                    property real flickVelocityX: 0
                    property real flickVelocityY: 0
                    property bool inertiaActive: false

                    MouseArea {
                        id: dragArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.SizeAllCursor
                        preventStealing: true
                        property real pressOffsetX: 0
                        property real pressOffsetY: 0

                        onPressed: mouse => {
                            if (root.inertiaOwner.length > 0) {
                                root.inertiaOwner = "";
                                root.commitHistoryTransaction();
                            }
                            parent.inertiaActive = false;
                            parent.flickVelocityX = 0;
                            parent.flickVelocityY = 0;
                            const additive = !!(mouse.modifiers & Qt.ShiftModifier);
                            root.selectElement(parent.elementName, additive);
                            if (!root.selectedContains(parent.elementName))
                                return;
                            root.beginHistoryTransaction();
                            pressOffsetX = mouse.x;
                            pressOffsetY = mouse.y;
                            const point = root.draftLayout[parent.elementName]
                                || root.defaultLayout()[parent.elementName];
                            parent.lastSampleX = Number(point.x);
                            parent.lastSampleY = Number(point.y);
                            parent.lastSampleTime = Date.now();
                            root.beginEditorHold(parent.elementName);
                        }

                        onPositionChanged: mouse => {
                            if (!pressed || !root.selectedContains(parent.elementName)
                                    || editorFocus.width <= 0 || editorFocus.height <= 0)
                                return;
                            const scenePoint = parent.mapToItem(editorFocus,
                                mouse.x - pressOffsetX + parent.width / 2,
                                mouse.y - pressOffsetY + parent.height / 2);
                            const bypassSnap = !!(mouse.modifiers & Qt.AltModifier);
                            const snapped = root.snapPoint(parent.elementName,
                                scenePoint.x / editorFocus.width,
                                scenePoint.y / editorFocus.height,
                                bypassSnap);
                            const current = root.draftLayout[parent.elementName]
                                || root.defaultLayout()[parent.elementName];
                            root.translateSelectedElements(
                                snapped.x - Number(current.x),
                                snapped.y - Number(current.y), true);
                            const moved = root.draftLayout[parent.elementName]
                                || root.defaultLayout()[parent.elementName];
                            const now = Date.now();
                            if (parent.lastSampleTime > 0 && now > parent.lastSampleTime) {
                                const dt = Math.max(8, now - parent.lastSampleTime) / 1000;
                                const sampleVX = (Number(moved.x) - parent.lastSampleX) / dt;
                                const sampleVY = (Number(moved.y) - parent.lastSampleY) / dt;
                                parent.flickVelocityX = parent.flickVelocityX * 0.30 + sampleVX * 0.70;
                                parent.flickVelocityY = parent.flickVelocityY * 0.30 + sampleVY * 0.70;
                            }
                            parent.lastSampleX = Number(moved.x);
                            parent.lastSampleY = Number(moved.y);
                            parent.lastSampleTime = now;
                        }

                        onReleased: mouse => {
                            root.endEditorHold(parent.elementName);
                            root.clearGuides();
                            if (Date.now() - parent.lastSampleTime > root.flickReleaseFreshnessMs) {
                                parent.flickVelocityX = 0;
                                parent.flickVelocityY = 0;
                            }
                            parent.flickVelocityX = root.cappedFlickVelocity(parent.flickVelocityX);
                            parent.flickVelocityY = root.cappedFlickVelocity(parent.flickVelocityY);
                            if (root.shouldStartFlick(parent.flickVelocityX, parent.flickVelocityY)) {
                                parent.inertiaActive = true;
                                root.inertiaOwner = parent.elementName;
                            } else {
                                parent.flickVelocityX = 0;
                                parent.flickVelocityY = 0;
                                parent.inertiaActive = false;
                                root.commitHistoryTransaction();
                            }
                        }

                        onCanceled: {
                            parent.inertiaActive = false;
                            parent.flickVelocityX = 0;
                            parent.flickVelocityY = 0;
                            if (root.inertiaOwner === parent.elementName)
                                root.inertiaOwner = "";
                            root.endEditorHold(parent.elementName);
                            root.clearGuides();
                            root.commitHistoryTransaction();
                        }
                    }

                    Timer {
                        id: inertiaTimer
                        interval: 16
                        repeat: true
                        running: root.open && parent.inertiaActive
                            && root.inertiaOwner === parent.elementName
                        onRunningChanged: {
                            if (!root.open && !running) {
                                parent.inertiaActive = false;
                                parent.flickVelocityX = 0;
                                parent.flickVelocityY = 0;
                            }
                        }
                        onTriggered: {
                            const point = root.draftLayout[parent.elementName]
                                || root.defaultLayout()[parent.elementName];
                            const dt = interval / 1000;
                            if (root.selectedElements.length <= 1) {
                                const proposedX = Number(point.x) + parent.flickVelocityX * dt;
                                const proposedY = Number(point.y) + parent.flickVelocityY * dt;
                                const clamped = root.clampPoint(parent.elementName, proposedX, proposedY);

                                if (Math.abs(clamped.x - proposedX) > 0.000001)
                                    parent.flickVelocityX = -parent.flickVelocityX * root.flickBounceDamping;
                                if (Math.abs(clamped.y - proposedY) > 0.000001)
                                    parent.flickVelocityY = -parent.flickVelocityY * root.flickBounceDamping;

                                root.setDraftPointSilently(parent.elementName, clamped.x, clamped.y);
                            } else {
                                const proposedDX = parent.flickVelocityX * dt;
                                const proposedDY = parent.flickVelocityY * dt;
                                const moved = root.translateSelectedElements(proposedDX, proposedDY, false);
                                if (Math.abs(moved.x - proposedDX) > 0.000001)
                                    parent.flickVelocityX = -parent.flickVelocityX * root.flickBounceDamping;
                                if (Math.abs(moved.y - proposedDY) > 0.000001)
                                    parent.flickVelocityY = -parent.flickVelocityY * root.flickBounceDamping;
                            }
                            parent.flickVelocityX *= root.flickFriction;
                            parent.flickVelocityY *= root.flickFriction;

                            if (Math.sqrt(parent.flickVelocityX * parent.flickVelocityX
                                    + parent.flickVelocityY * parent.flickVelocityY) < root.flickStopSpeed) {
                                parent.inertiaActive = false;
                                parent.flickVelocityX = 0;
                                parent.flickVelocityY = 0;
                                if (root.inertiaOwner === parent.elementName)
                                    root.inertiaOwner = "";
                                root.commitHistoryTransaction();
                            }
                        }
                    }
                }
            }

            Rectangle {
                visible: root.guideX >= 0
                x: Math.round(root.guideX * parent.width)
                y: 0
                width: 1
                height: parent.height
                color: Theme.focus
                opacity: 0.72
                z: 250
            }

            Rectangle {
                visible: root.guideY >= 0
                x: 0
                y: Math.round(root.guideY * parent.height)
                width: parent.width
                height: 1
                color: Theme.focus
                opacity: 0.72
                z: 250
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 184 + ((root.elementPaletteOpen || root.backgroundPaletteOpen) ? 150 : 0)
                color: Theme.popupBackground
                border.width: 1
                border.color: Theme.muted
                z: 300

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 9
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 7

                        Text {
                            text: root.elementLabel(root.selectedElement)
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.bold: true
                        }

                        SettingsButton {
                            label: root.selectedElement === "logo"
                                ? (root.elementEnabled("logo") ? "Logo visible" : "Logo hidden")
                                : root.elementCanHide(root.selectedElement)
                                    ? (root.elementEnabled(root.selectedElement) ? "Visible" : "Hidden")
                                    : "Always visible"
                            active: root.elementEnabled(root.selectedElement)
                            available: root.elementCanHide(root.selectedElement)
                            textSize: 9
                            onClicked: root.setDraftVisible(root.selectedElement,
                                !root.elementEnabled(root.selectedElement))
                        }

                        Text {
                            text: "Scale"
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                        }

                        SettingsButton {
                            label: "−"
                            available: root.elementScale(root.selectedElement) > 0.50
                            textSize: 10
                            onClicked: root.setDraftScale(root.selectedElement,
                                root.elementScale(root.selectedElement) - 0.10)
                        }

                        Text {
                            text: Math.round(root.elementScale(root.selectedElement) * 100) + "%"
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            Layout.preferredWidth: 42
                            horizontalAlignment: Text.AlignHCenter
                        }

                        SettingsButton {
                            label: "+"
                            available: root.elementScale(root.selectedElement) < 2.00
                            textSize: 10
                            onClicked: root.setDraftScale(root.selectedElement,
                                root.elementScale(root.selectedElement) + 0.10)
                        }

                        SettingsButton {
                            label: "Reset Position"
                            textSize: 9
                            onClicked: root.resetElementPosition(root.selectedElement)
                        }

                        Text {
                            text: "X"
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                        }
                        TextField {
                            id: positionXField
                            Layout.preferredWidth: 58
                            text: Number(root.primaryPoint().x * 100).toFixed(1)
                            validator: DoubleValidator { bottom: 0; top: 100; decimals: 1 }
                            selectByMouse: true
                            font.pixelSize: 9
                            onEditingFinished: root.setSelectedCoordinate("x", text)
                        }
                        Text {
                            text: "Y"
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                        }
                        TextField {
                            id: positionYField
                            Layout.preferredWidth: 58
                            text: Number(root.primaryPoint().y * 100).toFixed(1)
                            validator: DoubleValidator { bottom: 0; top: 100; decimals: 1 }
                            selectByMouse: true
                            font.pixelSize: 9
                            onEditingFinished: root.setSelectedCoordinate("y", text)
                        }

                        SettingsButton {
                            label: "Undo"
                            textSize: 9
                            available: root.undoStack.length > 0
                            onClicked: root.undo()
                        }
                        SettingsButton {
                            label: "Redo"
                            textSize: 9
                            available: root.redoStack.length > 0
                            onClicked: root.redo()
                        }

                        Item { Layout.fillWidth: true }

                        Text {
                            text: root.statusMessage.length > 0
                                ? root.statusMessage
                                : "Drag the actual lockscreen visuals. Hidden items stay faded so they can be restored."
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            elide: Text.ElideRight
                            Layout.maximumWidth: 470
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 7

                        Text {
                            text: "Element color"
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                        }

                        SettingsButton {
                            label: "Auto"
                            active: root.elementColor(root.selectedElement) === "auto"
                            textSize: 9
                            onClicked: root.setDraftColor(root.selectedElement, "auto")
                        }
                        SettingsButton {
                            label: "White"
                            active: root.elementColor(root.selectedElement) === "#ffffff"
                            textSize: 9
                            onClicked: root.setDraftColor(root.selectedElement, "#ffffff")
                        }
                        SettingsButton {
                            label: "Black"
                            active: root.elementColor(root.selectedElement) === "#000000"
                            textSize: 9
                            onClicked: root.setDraftColor(root.selectedElement, "#000000")
                        }
                        SettingsButton {
                            label: "Custom"
                            active: root.elementPaletteOpen
                            textSize: 9
                            onClicked: {
                                root.elementPaletteOpen = !root.elementPaletteOpen;
                                if (root.elementPaletteOpen)
                                    root.backgroundPaletteOpen = false;
                            }
                        }

                        Text {
                            text: "All:"
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                        }
                        SettingsButton { label: "Auto All"; textSize: 9; onClicked: root.setAllDraftColors("auto") }
                        SettingsButton { label: "White All"; textSize: 9; onClicked: root.setAllDraftColors("#ffffff") }
                        SettingsButton { label: "Black All"; textSize: 9; onClicked: root.setAllDraftColors("#000000") }

                        Item { Layout.fillWidth: true }

                        Text {
                            text: "Auto is calculated independently around each element."
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            elide: Text.ElideRight
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 7

                        Text {
                            text: "Background"
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                        }
                        SettingsButton {
                            label: "Black"
                            active: root.draftBackgroundMode === "black"
                            textSize: 9
                            onClicked: root.setDraftBackgroundMode("black")
                        }
                        SettingsButton {
                            label: "Wallpaper"
                            active: root.draftBackgroundMode === "wallpaper"
                            textSize: 9
                            onClicked: {
                                if (root.draftWallpaperPath.length > 0)
                                    root.setDraftBackgroundMode("wallpaper");
                                else if (!wallpaperPickerProcess.running) {
                                    root.statusMessage = "Opening lockscreen wallpaper picker…";
                                    wallpaperPickerProcess.exec(["bash", root.wallpaperPickerBackend]);
                                }
                            }
                        }
                        SettingsButton {
                            label: "Choose Wallpaper"
                            textSize: 9
                            available: !wallpaperPickerProcess.running
                            onClicked: {
                                root.statusMessage = "Opening lockscreen wallpaper picker…";
                                wallpaperPickerProcess.exec(["bash", root.wallpaperPickerBackend]);
                            }
                        }
                        SettingsButton {
                            label: "Color"
                            active: root.draftBackgroundMode === "color"
                            textSize: 9
                            onClicked: {
                                root.setDraftBackgroundMode("color");
                                root.backgroundPaletteOpen = true;
                                root.elementPaletteOpen = false;
                            }
                        }
                        SettingsButton {
                            label: "Palette"
                            active: root.backgroundPaletteOpen
                            textSize: 9
                            onClicked: {
                                root.backgroundPaletteOpen = !root.backgroundPaletteOpen;
                                if (root.backgroundPaletteOpen)
                                    root.elementPaletteOpen = false;
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: root.draftWallpaperPath.length > 0
                                ? "Lockscreen wallpaper: " + root.draftWallpaperPath.split("/").pop()
                                : "Lockscreen wallpaper is independent from the desktop."
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            elide: Text.ElideMiddle
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: visible ? 142 : 0
                        spacing: 12
                        visible: root.elementPaletteOpen || root.backgroundPaletteOpen

                        InlineColorPicker {
                            id: elementColorPicker
                            visible: root.elementPaletteOpen
                            Layout.preferredWidth: 320
                            Layout.preferredHeight: visible ? 142 : 0
                            colorValue: root.elementColor(root.selectedElement) === "auto"
                                ? String(root.draftAutoAccents[root.selectedElement] || "#ffffff")
                                : root.elementColor(root.selectedElement)
                            onColorEdited: hex => root.setDraftColor(root.selectedElement, hex)
                        }

                        InlineColorPicker {
                            id: backgroundColorPicker
                            visible: root.backgroundPaletteOpen
                            Layout.preferredWidth: 320
                            Layout.preferredHeight: visible ? 142 : 0
                            colorValue: root.draftBackgroundColor
                            onColorEdited: hex => root.setDraftBackgroundColor(hex)
                        }

                        Item { Layout.fillWidth: true }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            Layout.fillWidth: true
                            text: "Changes are live preview only until Save. Password cannot be hidden."
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            elide: Text.ElideRight
                        }

                        SettingsButton {
                            label: "Restore Defaults"
                            textSize: 10
                            onClicked: root.resetDraft()
                        }
                        SettingsButton { label: "Cancel"; textSize: 10; onClicked: root.close() }
                        SettingsButton {
                            label: "Save"
                            active: true
                            textSize: 10
                            available: !saveProcess.running && !contrastPersistProcess.running
                            onClicked: root.save()
                        }
                    }
                }
            }
        }
    }
}
