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
    property bool editingActive: false
    readonly property bool open: editingActive
    property bool pickerSuspended: false
    property string activeDrawer: ""
    readonly property var elementNames: ["logo", "time", "date", "username", "weather", "password"]
    readonly property int customImageMaximum: 12
    readonly property real elementScaleMaximum: 100.0

    property var draftLayout: defaultLayout()
    property var draftCustomImages: []
    property var draftVisualizer: defaultVisualizer()
    property int draftBackgroundOpacity: 100
    property string draftEntryTransition: "fade"
    property int draftEntryTransitionDuration: 1800
    property int entryTransitionReplayToken: 0
    property var draftVisibility: defaultVisibility()
    property string draftBackgroundMode: "black"
    property string draftBackgroundColor: "#000000"
    property string draftWallpaperPath: ""
    property string draftWallpaperFit: "cover"
    property real draftWallpaperFocalX: 0.5
    property real draftWallpaperFocalY: 0.5
    property string draftOverlayMode: "none"
    property int draftOverlayStrength: 0
    property int draftWallpaperBlur: 0
    property bool draftWallpaperBlurExplicit: false
    property string draftWeatherUnits: "auto"
    property var draftAutoAccents: defaultAutoAccents()
    property string selectedElement: "logo"
    property string statusMessage: ""
    property bool elementPaletteOpen: false
    property bool backgroundPaletteOpen: false
    property bool contrastRefreshPending: false
    property string heldElement: ""
    property real heldScaleBoost: 1.0
    property bool showEditorGrid: false

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
    property string resizeElementName: ""
    property real resizeStartDistance: 1
    property real resizeStartScale: 1
    property real resizeCenterX: 0
    property real resizeCenterY: 0
    property bool visualizerWidthResizeActive: false
    property real visualizerWidthStartStretch: 1
    property real visualizerWidthStartDistance: 1
    property real visualizerWidthCenterX: 0
    property string rotationElementName: ""
    property real rotationStartAngle: 0
    property real rotationStartValue: 0
    property real rotationCenterX: 0
    property real rotationCenterY: 0

    function defaultVisualizer() {
        return ({
            enabled: false,
            x: 0.50,
            y: 0.80,
            scale: 1.0,
            stretch_x: 1.0,
            stretch_y: 1.0,
            opacity: 100,
            color: "auto",
            bands: 16,
            gap: 4,
            height: 100,
            sensitivity: 140,
            shape: "straight",
            bend: 45,
            performance: "balanced"
        });
    }

    function cloneVisualizer(value) {
        const defaults = defaultVisualizer();
        const raw = value && typeof value === "object" && !Array.isArray(value)
            ? value : defaults;
        const enabled = typeof raw.enabled === "boolean" ? raw.enabled : defaults.enabled;
        const x = Number(raw.x === undefined ? defaults.x : raw.x);
        const y = Number(raw.y === undefined ? defaults.y : raw.y);
        const scale = Number(raw.scale === undefined ? defaults.scale : raw.scale);
        const stretchX = Number(raw.stretch_x === undefined ? defaults.stretch_x : raw.stretch_x);
        const stretchY = Number(raw.stretch_y === undefined ? defaults.stretch_y : raw.stretch_y);
        const opacity = Number(raw.opacity === undefined ? defaults.opacity : raw.opacity);
        const rawColor = String(raw.color === undefined ? defaults.color : raw.color).toLowerCase();
        const color = rawColor === "auto" || validHex(rawColor) ? rawColor : defaults.color;
        const bands = Number(raw.bands === undefined ? defaults.bands : raw.bands);
        const gap = Number(raw.gap === undefined ? defaults.gap : raw.gap);
        const responseHeight = Number(raw.height === undefined ? defaults.height : raw.height);
        const sensitivity = Number(raw.sensitivity === undefined ? defaults.sensitivity : raw.sensitivity);
        const shape = String(raw.shape === undefined ? defaults.shape : raw.shape);
        const bend = Number(raw.bend === undefined ? defaults.bend : raw.bend);
        const performance = String(raw.performance === undefined ? defaults.performance : raw.performance);
        return ({
            enabled: enabled,
            x: Math.max(0.05, Math.min(0.95, Number.isFinite(x) ? x : defaults.x)),
            y: Math.max(0.08, Math.min(0.92, Number.isFinite(y) ? y : defaults.y)),
            scale: Math.max(0.50, Math.min(elementScaleMaximum, Number.isFinite(scale) ? scale : defaults.scale)),
            stretch_x: Math.max(0.25, Math.min(4.00, Number.isFinite(stretchX) ? stretchX : defaults.stretch_x)),
            stretch_y: Math.max(0.25, Math.min(4.00, Number.isFinite(stretchY) ? stretchY : defaults.stretch_y)),
            opacity: Math.max(0, Math.min(100, Number.isFinite(opacity) ? Math.round(opacity) : defaults.opacity)),
            color: color,
            bands: Number.isInteger(bands) ? Math.max(4, Math.min(64, bands)) : defaults.bands,
            gap: Number.isInteger(gap) ? Math.max(0, Math.min(24, gap)) : defaults.gap,
            height: Number.isInteger(responseHeight) ? Math.max(25, Math.min(300, responseHeight)) : defaults.height,
            sensitivity: Number.isInteger(sensitivity) ? Math.max(25, Math.min(300, sensitivity)) : defaults.sensitivity,
            shape: ["straight", "arc", "circle"].indexOf(shape) >= 0 ? shape : defaults.shape,
            bend: Number.isInteger(bend) ? Math.max(-360, Math.min(360, bend)) : defaults.bend,
            performance: ["balanced", "responsive"].indexOf(performance) >= 0
                ? performance : defaults.performance
        });
    }

    function defaultLayout() {
        return ({
            logo: ({ x: 0.50, y: 0.34, scale: 1.0, stretch_x: 1.0, stretch_y: 1.0, opacity: 100, color: "auto" }),
            time: ({ x: 0.50, y: 0.51, scale: 1.0, stretch_x: 1.0, stretch_y: 1.0, opacity: 100, color: "auto" }),
            date: ({ x: 0.50, y: 0.555, scale: 1.0, stretch_x: 1.0, stretch_y: 1.0, opacity: 100, color: "auto" }),
            username: ({ x: 0.50, y: 0.595, scale: 1.0, stretch_x: 1.0, stretch_y: 1.0, opacity: 100, color: "auto" }),
            weather: ({ x: 0.50, y: 0.635, scale: 1.0, stretch_x: 1.0, stretch_y: 1.0, opacity: 100, color: "auto" }),
            password: ({ x: 0.50, y: 0.70, scale: 1.0, stretch_x: 1.0, stretch_y: 1.0, opacity: 100, color: "auto" })
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

    function layoutPreset(name) {
        if (name === "minimal") {
            return ({
                logo: ({ x: 0.50, y: 0.38, scale: 1.0 }),
                time: ({ x: 0.50, y: 0.51, scale: 1.0 }),
                date: ({ x: 0.50, y: 0.555, scale: 1.0 }),
                username: ({ x: 0.50, y: 0.595, scale: 1.0 }),
                weather: ({ x: 0.50, y: 0.635, scale: 1.0 }),
                password: ({ x: 0.50, y: 0.62, scale: 1.0 })
            });
        }
        if (name === "centered") {
            return ({
                logo: ({ x: 0.50, y: 0.30, scale: 1.0 }),
                time: ({ x: 0.50, y: 0.47, scale: 1.0 }),
                date: ({ x: 0.50, y: 0.53, scale: 1.0 }),
                username: ({ x: 0.50, y: 0.58, scale: 1.0 }),
                weather: ({ x: 0.50, y: 0.62, scale: 1.0 }),
                password: ({ x: 0.50, y: 0.66, scale: 1.0 })
            });
        }
        if (name === "information") {
            return ({
                logo: ({ x: 0.50, y: 0.27, scale: 1.0 }),
                time: ({ x: 0.50, y: 0.44, scale: 1.0 }),
                date: ({ x: 0.50, y: 0.50, scale: 1.0 }),
                username: ({ x: 0.50, y: 0.55, scale: 1.0 }),
                weather: ({ x: 0.50, y: 0.60, scale: 1.0 }),
                password: ({ x: 0.50, y: 0.70, scale: 1.0 })
            });
        }
        if (name === "lower-third") {
            return ({
                logo: ({ x: 0.50, y: 0.28, scale: 1.0 }),
                time: ({ x: 0.50, y: 0.62, scale: 1.0 }),
                date: ({ x: 0.50, y: 0.675, scale: 1.0 }),
                username: ({ x: 0.50, y: 0.72, scale: 1.0 }),
                weather: ({ x: 0.50, y: 0.765, scale: 1.0 }),
                password: ({ x: 0.50, y: 0.84, scale: 1.0 })
            });
        }
        return null;
    }

    function presetVisibility(name) {
        const presets = ({
            minimal: ({ logo: true, time: false, date: false, username: false, weather: false, password: true }),
            centered: ({ logo: true, time: true, date: true, username: false, weather: false, password: true }),
            information: ({ logo: true, time: true, date: true, username: true, weather: true, password: true }),
            lowerThird: ({ logo: true, time: true, date: true, username: true, weather: true, password: true })
        });
        const key = name === "lower-third" ? "lowerThird" : String(name || "");
        if (!presets[key])
            return null;
        const visibility = cloneVisibility(presets[key]);
        visibility.password = true;
        return visibility;
    }

    function applyLayoutPreset(name) {
        const preset = layoutPreset(name);
        const visibility = presetVisibility(name);
        if (!preset || !visibility)
            return;
        const previous = editorSnapshot();
        const next = cloneLayout(draftLayout);
        for (const element of elementNames) {
            const current = next[element];
            const target = preset[element];
            next[element] = ({
                x: target.x,
                y: target.y,
                scale: target.scale,
                stretch_x: current.stretch_x,
                stretch_y: current.stretch_y,
                opacity: current.opacity,
                color: current.color
            });
        }
        draftLayout = next;
        draftVisibility = cloneVisibility(visibility);
        selectedElement = "logo";
        selectedElements = ["logo"];
        clearGuides();
        pushUndoSnapshot(previous);
        statusMessage = "Applied " + (name === "lower-third" ? "Lower Third" : elementLabel(name)) + " preset";
        scheduleContrastRefresh();
    }

    function defaultAutoAccents() {
        return ({
            logo: "#ffffff",
            time: "#ffffff",
            date: "#ffffff",
            username: "#ffffff",
            weather: "#ffffff",
            password: "#ffffff",
            visualizer: "#ffffff"
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
            customImages: cloneCustomImages(draftCustomImages),
            visualizer: cloneSnapshot(draftVisualizer),
            visibility: cloneVisibility(draftVisibility),
            backgroundMode: draftBackgroundMode,
            backgroundColor: draftBackgroundColor,
            backgroundOpacity: draftBackgroundOpacity,
            entryTransition: draftEntryTransition,
            entryTransitionDuration: draftEntryTransitionDuration,
            wallpaperPath: draftWallpaperPath,
            wallpaperFit: draftWallpaperFit,
            wallpaperFocalX: draftWallpaperFocalX,
            wallpaperFocalY: draftWallpaperFocalY,
            overlayMode: draftOverlayMode,
            overlayStrength: draftOverlayStrength,
            wallpaperBlur: draftWallpaperBlur,
            wallpaperBlurExplicit: draftWallpaperBlurExplicit,
            weatherUnits: draftWeatherUnits
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
        draftCustomImages = cloneCustomImages(snapshot.customImages);
        draftVisualizer = cloneVisualizer(snapshot.visualizer);
        draftVisibility = cloneVisibility(snapshot.visibility);
        const validSelection = selectedElements.filter(name => elementExists(name));
        if (!elementExists(selectedElement))
            selectedElement = validSelection.length > 0 ? validSelection[0] : "logo";
        selectedElements = validSelection.length > 0 ? validSelection : [selectedElement];
        draftBackgroundMode = ["black", "wallpaper", "color"].indexOf(String(snapshot.backgroundMode)) >= 0
            ? String(snapshot.backgroundMode) : "black";
        draftBackgroundColor = validHex(snapshot.backgroundColor)
            ? String(snapshot.backgroundColor).toLowerCase() : "#000000";
        const backgroundOpacity = Number(snapshot.backgroundOpacity);
        draftBackgroundOpacity = Number.isFinite(backgroundOpacity)
            ? Math.max(0, Math.min(100, Math.round(backgroundOpacity))) : 100;
        const entryTransition = String(snapshot.entryTransition || "fade");
        draftEntryTransition = ["fade", "pixel", "iris", "edges", "wipe"].indexOf(entryTransition) >= 0
            ? entryTransition : "fade";
        const transitionDuration = Math.round(Number(snapshot.entryTransitionDuration));
        draftEntryTransitionDuration = Number.isFinite(transitionDuration)
            ? Math.max(400, Math.min(4000, transitionDuration)) : 1200;
        draftWallpaperPath = typeof snapshot.wallpaperPath === "string"
            ? snapshot.wallpaperPath : "";
        draftWallpaperFit = ["cover", "contain"].indexOf(String(snapshot.wallpaperFit)) >= 0
            ? String(snapshot.wallpaperFit) : "cover";
        const focalX = Number(snapshot.wallpaperFocalX);
        const focalY = Number(snapshot.wallpaperFocalY);
        draftWallpaperFocalX = Number.isFinite(focalX) ? Math.max(0, Math.min(1, focalX)) : 0.5;
        draftWallpaperFocalY = Number.isFinite(focalY) ? Math.max(0, Math.min(1, focalY)) : 0.5;
        draftOverlayMode = ["none", "dark", "light"].indexOf(String(snapshot.overlayMode)) >= 0
            ? String(snapshot.overlayMode) : "none";
        const overlayStrength = Number(snapshot.overlayStrength);
        const wallpaperBlur = Number(snapshot.wallpaperBlur);
        draftOverlayStrength = Number.isFinite(overlayStrength)
            ? Math.max(0, Math.min(100, Math.round(overlayStrength))) : 0;
        draftWallpaperBlur = Number.isFinite(wallpaperBlur)
            ? Math.max(0, Math.min(100, Math.round(wallpaperBlur))) : 0;
        draftWallpaperBlurExplicit = snapshot.wallpaperBlurExplicit === true;
        draftWeatherUnits = ["auto", "fahrenheit", "celsius"].indexOf(String(snapshot.weatherUnits)) >= 0
            ? String(snapshot.weatherUnits) : "auto";
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
        if (!elementExists(name))
            return;
        if (!additive) {
            selectedElement = name;
            selectedElements = [name];
            return;
        }
        const next = selectedElements.filter(candidate => elementExists(candidate));
        const index = next.indexOf(name);
        if (index >= 0) {
            if (next.length > 1)
                next.splice(index, 1);
        } else {
            next.push(name);
        }
        selectedElements = next;
        selectedElement = next.indexOf(name) >= 0 ? name : next[0];
    }

    function primaryPoint() {
        return elementPoint(selectedElement) || defaultLayout().logo;
    }

    function setDraftScaleSilently(name, scaleValue) {
        if (!elementExists(name))
            return;
        const numeric = Number(scaleValue);
        if (!Number.isFinite(numeric))
            return;
        const value = Math.max(0.50, Math.min(
            elementScaleMaximum, numeric));
        if (name === "visualizer") {
            const next = cloneVisualizer(draftVisualizer);
            next.scale = value;
            draftVisualizer = next;
        } else if (isCustomImage(name)) {
            const next = cloneCustomImages(draftCustomImages);
            const index = customImageIndex(name);
            if (index < 0) return;
            next[index].scale = value;
            draftCustomImages = next;
        } else {
            const next = cloneLayout(draftLayout);
            next[name].scale = value;
            draftLayout = next;
        }
        scheduleContrastRefresh();
    }

    function normalizedRotation(value) {
        const numeric = Number(value);
        if (!Number.isFinite(numeric))
            return 0;
        let normalized = ((numeric + 180) % 360 + 360) % 360 - 180;
        if (normalized === -180 && numeric > 0)
            normalized = 180;
        return normalized;
    }

    function elementRotation(name) {
        const index = customImageIndex(name);
        if (index < 0)
            return 0;
        return normalizedRotation(draftCustomImages[index].rotation === undefined
            ? 0 : draftCustomImages[index].rotation);
    }

    function setDraftRotationSilently(name, rotation) {
        const index = customImageIndex(name);
        if (index < 0)
            return;
        const next = cloneCustomImages(draftCustomImages);
        next[index].rotation = normalizedRotation(rotation);
        draftCustomImages = next;
    }

    function setDraftRotation(name, rotation) {
        if (!isCustomImage(name))
            return;
        const numeric = Number(rotation);
        if (!Number.isFinite(numeric) || numeric < -180 || numeric > 180) {
            statusMessage = "Rotation must be -180 to 180 degrees";
            return;
        }
        recordUndoBeforeChange();
        setDraftRotationSilently(name, numeric);
        selectElement(name, false);
        statusMessage = "Image rotation updated";
    }

    function beginRotateElement(name, sceneX, sceneY) {
        if (!isCustomImage(name) || editorFocus.width <= 0 || editorFocus.height <= 0)
            return;
        selectElement(name, false);
        const point = elementPoint(name);
        rotationElementName = name;
        rotationCenterX = Number(point.x) * editorFocus.width;
        rotationCenterY = Number(point.y) * editorFocus.height;
        rotationStartAngle = Math.atan2(Number(sceneY) - rotationCenterY,
            Number(sceneX) - rotationCenterX) * 180 / Math.PI;
        rotationStartValue = elementRotation(name);
        beginHistoryTransaction();
    }

    function updateRotateElement(sceneX, sceneY) {
        if (rotationElementName.length === 0)
            return;
        const angle = Math.atan2(Number(sceneY) - rotationCenterY,
            Number(sceneX) - rotationCenterX) * 180 / Math.PI;
        let delta = angle - rotationStartAngle;
        if (delta > 180)
            delta -= 360;
        else if (delta < -180)
            delta += 360;
        setDraftRotationSilently(rotationElementName, rotationStartValue + delta);
    }

    function endRotateElement() {
        if (rotationElementName.length === 0)
            return;
        rotationElementName = "";
        commitHistoryTransaction();
        scheduleContrastRefresh();
    }

    function beginResizeElement(name, sceneX, sceneY) {
        if (!elementExists(name) || editorFocus.width <= 0 || editorFocus.height <= 0)
            return;
        selectElement(name, false);
        const point = elementPoint(name);
        resizeElementName = name;
        resizeCenterX = Number(point.x) * editorFocus.width;
        resizeCenterY = Number(point.y) * editorFocus.height;
        resizeStartDistance = Math.max(12, Math.sqrt(
            Math.pow(Number(sceneX) - resizeCenterX, 2)
            + Math.pow(Number(sceneY) - resizeCenterY, 2)));
        resizeStartScale = elementScale(name);
        beginHistoryTransaction();
    }

    function updateResizeElement(sceneX, sceneY) {
        if (resizeElementName.length === 0)
            return;
        const distance = Math.max(1, Math.sqrt(
            Math.pow(Number(sceneX) - resizeCenterX, 2)
            + Math.pow(Number(sceneY) - resizeCenterY, 2)));
        setDraftScaleSilently(resizeElementName,
            resizeStartScale * distance / resizeStartDistance);
    }

    function endResizeElement() {
        if (resizeElementName.length === 0)
            return;
        resizeElementName = "";
        commitHistoryTransaction();
    }

    function setDraftVisualizerWidth(percentValue) {
        const numeric = Number(percentValue);
        if (!Number.isFinite(numeric) || numeric < 25 || numeric > 400) {
            statusMessage = "Visualizer width must be 25% to 400%";
            return;
        }
        recordUndoBeforeChange();
        const next = cloneVisualizer(draftVisualizer);
        next.stretch_x = Math.max(0.25, Math.min(4.00, numeric / 100));
        draftVisualizer = next;
        selectElement("visualizer", false);
        statusMessage = "Visualizer width updated";
    }

    function beginVisualizerWidthResize(sceneX) {
        if (editorFocus.width <= 0)
            return;
        selectElement("visualizer", false);
        const point = elementPoint("visualizer");
        visualizerWidthCenterX = Number(point.x) * editorFocus.width;
        visualizerWidthStartDistance = Math.max(8, Math.abs(Number(sceneX) - visualizerWidthCenterX));
        visualizerWidthStartStretch = elementStretchX("visualizer");
        visualizerWidthResizeActive = true;
        beginHistoryTransaction();
    }

    function updateVisualizerWidthResize(sceneX) {
        if (!visualizerWidthResizeActive)
            return;
        const distance = Math.max(1, Math.abs(Number(sceneX) - visualizerWidthCenterX));
        const next = cloneVisualizer(draftVisualizer);
        next.stretch_x = Math.max(0.25, Math.min(4.00,
            visualizerWidthStartStretch * distance / visualizerWidthStartDistance));
        draftVisualizer = next;
    }

    function endVisualizerWidthResize() {
        if (!visualizerWidthResizeActive)
            return;
        visualizerWidthResizeActive = false;
        commitHistoryTransaction();
        scheduleContrastRefresh();
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
            const point = elementPoint(name);
            if (!point)
                continue;
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
        const nextLayout = cloneLayout(draftLayout);
        const nextImages = cloneCustomImages(draftCustomImages);
        const nextVisualizer = cloneVisualizer(draftVisualizer);
        for (const name of selectedElements) {
            if (name === "visualizer") {
                nextVisualizer.x = Number(nextVisualizer.x) + delta.x;
                nextVisualizer.y = Number(nextVisualizer.y) + delta.y;
            } else if (isCustomImage(name)) {
                const index = nextImages.findIndex(image => image.id === name);
                if (index < 0) continue;
                nextImages[index].x = Number(nextImages[index].x) + delta.x;
                nextImages[index].y = Number(nextImages[index].y) + delta.y;
            } else if (elementNames.indexOf(name) >= 0) {
                nextLayout[name].x = Number(nextLayout[name].x) + delta.x;
                nextLayout[name].y = Number(nextLayout[name].y) + delta.y;
            }
        }
        draftLayout = nextLayout;
        draftCustomImages = nextImages;
        draftVisualizer = nextVisualizer;
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
        for (const peer of editableElementNames()) {
            if (!root.selectedContains(peer)) {
                const point = elementPoint(peer);
                if (!point) continue;
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
        const nextVisualizer = cloneVisualizer(draftVisualizer);
        nextVisualizer.color = value;
        draftVisualizer = nextVisualizer;
        statusMessage = value === "auto" ? "All elements use Auto contrast"
            : "All element colors updated";
    }

    function resetElementPosition(name) {
        if (!elementExists(name))
            return;
        recordUndoBeforeChange();
        if (name === "visualizer") {
            const defaults = defaultVisualizer();
            const next = cloneVisualizer(draftVisualizer);
            next.x = defaults.x;
            next.y = defaults.y;
            draftVisualizer = next;
        } else if (isCustomImage(name)) {
            const next = cloneCustomImages(draftCustomImages);
            const index = next.findIndex(image => image.id === name);
            if (index < 0) return;
            next[index].x = 0.5;
            next[index].y = 0.5;
            draftCustomImages = next;
        } else {
            const defaults = defaultLayout();
            const next = cloneLayout(draftLayout);
            next[name].x = defaults[name].x;
            next[name].y = defaults[name].y;
            draftLayout = next;
        }
        selectedElement = name;
        selectedElements = [name];
        statusMessage = elementLabel(name) + " position reset";
        scheduleContrastRefresh();
    }

    function resetElementToDefault(name) {
        if (!elementExists(name))
            return;
        recordUndoBeforeChange();
        if (name === "visualizer") {
            draftVisualizer = defaultVisualizer();
        } else if (isCustomImage(name)) {
            const index = customImageIndex(name);
            const next = cloneCustomImages(draftCustomImages);
            const current = next[index];
            next[index] = ({
                id: current.id, path: current.path, x: 0.5, y: 0.5,
                scale: 1.0, stretch_x: 1.0, stretch_y: 1.0,
                opacity: 100, rotation: 0, visible: true
            });
            draftCustomImages = next;
        } else {
            const defaults = defaultLayout();
            const visibility = defaultVisibility();
            const nextLayout = cloneLayout(draftLayout);
            nextLayout[name] = cloneSnapshot(defaults[name]);
            draftLayout = nextLayout;
            const nextVisibility = cloneVisibility(draftVisibility);
            nextVisibility[name] = name === "password" ? true : visibility[name];
            draftVisibility = nextVisibility;
        }
        selectedElement = name;
        selectedElements = [name];
        statusMessage = elementLabel(name) + " reset to default";
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

    function setDraftBackgroundOpacity(value) {
        const numeric = Number(value);
        if (!Number.isFinite(numeric))
            return;
        const next = Math.max(0, Math.min(100, Math.round(numeric)));
        recordUndoBeforeChange();
        if (draftBackgroundOpacity === 100 && next < 100 && draftWallpaperBlur === 0
                && !draftWallpaperBlurExplicit)
            draftWallpaperBlur = 20;
        draftBackgroundOpacity = next;
    }

    function setBackgroundOpacityFromPointer(pointerX, trackWidth) {
        if (trackWidth > 0)
            setDraftBackgroundOpacity(Number(pointerX) * 100 / Number(trackWidth));
    }

    function setBlurFromPointer(pointerX, trackWidth) {
        if (trackWidth > 0)
            setDraftWallpaperBlur(Number(pointerX) * 100 / Number(trackWidth));
    }

    function draftBrightness() {
        if (draftOverlayMode === "dark") return -draftOverlayStrength;
        if (draftOverlayMode === "light") return draftOverlayStrength;
        return 0;
    }

    function setDraftBrightness(value) {
        const numeric = Number(value);
        if (!Number.isFinite(numeric)) return;
        const next = Math.max(-100, Math.min(100, Math.round(numeric)));
        setDraftOverlay(next < 0 ? "dark" : next > 0 ? "light" : "none", Math.abs(next));
    }

    function setBrightnessFromPointer(pointerX, trackWidth) {
        if (trackWidth > 0)
            setDraftBrightness(Number(pointerX) * 200 / Number(trackWidth) - 100);
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

    function setDraftWallpaperFit(value) {
        const fit = String(value || "");
        if (["cover", "contain"].indexOf(fit) < 0)
            return;
        recordUndoBeforeChange();
        draftWallpaperFit = fit;
    }

    function setDraftWallpaperFocal(x, y) {
        const nextX = Number(x);
        const nextY = Number(y);
        if (!Number.isFinite(nextX) || !Number.isFinite(nextY))
            return;
        recordUndoBeforeChange();
        draftWallpaperFocalX = Math.max(0, Math.min(1, nextX));
        draftWallpaperFocalY = Math.max(0, Math.min(1, nextY));
        scheduleContrastRefresh();
    }

    function setDraftOverlay(mode, strength) {
        const nextMode = String(mode || "");
        const nextStrength = Number(strength);
        if (["none", "dark", "light"].indexOf(nextMode) < 0 || !Number.isFinite(nextStrength))
            return;
        recordUndoBeforeChange();
        draftOverlayMode = nextMode;
        draftOverlayStrength = Math.max(0, Math.min(100, Math.round(nextStrength)));
        scheduleContrastRefresh();
    }

    function setDraftWallpaperBlur(value) {
        const next = Number(value);
        if (!Number.isFinite(next))
            return;
        recordUndoBeforeChange();
        draftWallpaperBlur = Math.max(0, Math.min(100, Math.round(next)));
        draftWallpaperBlurExplicit = true;
    }

    function setDraftVisualizerSetting(name, value) {
        const next = cloneVisualizer(draftVisualizer);
        if (name === "shape") {
            const shape = String(value || "");
            if (["straight", "arc", "circle"].indexOf(shape) < 0)
                return;
            recordUndoBeforeChange();
            next.shape = shape;
        } else if (name === "performance") {
            const performance = String(value || "");
            if (["balanced", "responsive"].indexOf(performance) < 0)
                return;
            recordUndoBeforeChange();
            next.performance = performance;
        } else {
            const numeric = Math.round(Number(value));
            if (!Number.isFinite(numeric))
                return;
            const bounds = ({
                bands: ({ min: 4, max: 64 }),
                gap: ({ min: 0, max: 24 }),
                height: ({ min: 25, max: 300 }),
                sensitivity: ({ min: 25, max: 300 }),
                bend: ({ min: -360, max: 360 })
            });
            const range = bounds[name];
            if (!range)
                return;
            recordUndoBeforeChange();
            next[name] = Math.max(range.min, Math.min(range.max, numeric));
        }
        draftVisualizer = next;
    }

    function setDraftWeatherUnits(value) {
        const units = String(value || "");
        if (["auto", "fahrenheit", "celsius"].indexOf(units) < 0)
            return;
        recordUndoBeforeChange();
        draftWeatherUnits = units;
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

    function acceptCustomImageSelection(line) {
        if (!open)
            return;
        const value = String(line || "").trim();
        if (!value.startsWith("/") || value.indexOf("://") >= 0) {
            statusMessage = "Awtwall returned an invalid local image";
            return;
        }
        addCustomImage(value);
    }

    function scheduleContrastRefresh() {
        if (!open || pickerSuspended)
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

    function cloneCustomImages(value) {
        if (!Array.isArray(value))
            return [];
        const result = [];
        const ids = ({});
        for (let i = 0; i < value.length && result.length < customImageMaximum; ++i) {
            const raw = value[i];
            if (!raw || typeof raw !== "object" || Array.isArray(raw))
                continue;
            const id = String(raw.id || "");
            const imagePath = String(raw.path || "");
            if (!/^image-[A-Za-z0-9_-]{1,64}$/.test(id) || ids[id]
                    || !imagePath.startsWith("/") || imagePath.indexOf("://") >= 0)
                continue;
            const x = Number(raw.x);
            const y = Number(raw.y);
            const scale = Number(raw.scale);
            const stretchX = Number(raw.stretch_x);
            const stretchY = Number(raw.stretch_y);
            const opacity = Number(raw.opacity);
            const rotation = Number(raw.rotation === undefined ? 0 : raw.rotation);
            ids[id] = true;
            result.push(({
                id: id,
                path: imagePath,
                x: Math.max(0.05, Math.min(0.95, Number.isFinite(x) ? x : 0.5)),
                y: Math.max(0.08, Math.min(0.92, Number.isFinite(y) ? y : 0.5)),
                scale: Math.max(0.50, Math.min(elementScaleMaximum, Number.isFinite(scale) ? scale : 1)),
                stretch_x: Math.max(0.25, Math.min(4.00, Number.isFinite(stretchX) ? stretchX : 1)),
                stretch_y: Math.max(0.25, Math.min(4.00, Number.isFinite(stretchY) ? stretchY : 1)),
                opacity: Math.max(0, Math.min(100, Number.isFinite(opacity) ? opacity : 100)),
                rotation: Math.max(-180, Math.min(180, Number.isFinite(rotation) ? rotation : 0)),
                visible: typeof raw.visible === "boolean" ? raw.visible : true
            }));
        }
        return result;
    }

    function customImageIndex(name) {
        const key = String(name || "");
        for (let i = 0; i < draftCustomImages.length; ++i) {
            if (String(draftCustomImages[i].id || "") === key)
                return i;
        }
        return -1;
    }

    function isCustomImage(name) {
        return customImageIndex(name) >= 0;
    }

    function editableElementNames() {
        const names = elementNames.slice();
        names.push("visualizer");
        for (const image of draftCustomImages)
            names.push(String(image.id));
        return names;
    }

    function elementExists(name) {
        return name === "visualizer" || elementNames.indexOf(name) >= 0 || isCustomImage(name);
    }

    function elementPoint(name) {
        if (name === "visualizer")
            return draftVisualizer;
        if (isCustomImage(name))
            return draftCustomImages[customImageIndex(name)];
        return draftLayout[name] || defaultLayout()[name] || null;
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
            const stretchX = Number(raw.stretch_x === undefined ? 1 : raw.stretch_x);
            const stretchY = Number(raw.stretch_y === undefined ? 1 : raw.stretch_y);
            const opacity = Number(raw.opacity === undefined ? 100 : raw.opacity);
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
                scale: Math.max(0.50, Math.min(elementScaleMaximum, Number.isFinite(scale) ? scale : 1)),
                stretch_x: Math.max(0.25, Math.min(4.00, Number.isFinite(stretchX) ? stretchX : 1)),
                stretch_y: Math.max(0.25, Math.min(4.00, Number.isFinite(stretchY) ? stretchY : 1)),
                opacity: Math.max(password ? 20 : 0, Math.min(100, Number.isFinite(opacity) ? opacity : 100)),
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

    function writeDraftPoint(name, x, y, selectPrimary) {
        if (!elementExists(name))
            return;
        if (selectPrimary)
            recordUndoBeforeChange();
        const point = clampPoint(name, Number(x), Number(y));
        if (name === "visualizer") {
            const next = cloneVisualizer(draftVisualizer);
            next.x = point.x;
            next.y = point.y;
            draftVisualizer = next;
        } else if (isCustomImage(name)) {
            const next = cloneCustomImages(draftCustomImages);
            const index = next.findIndex(image => image.id === name);
            if (index < 0) return;
            next[index].x = point.x;
            next[index].y = point.y;
            draftCustomImages = next;
        } else {
            const next = cloneLayout(draftLayout);
            next[name].x = point.x;
            next[name].y = point.y;
            draftLayout = next;
        }
        if (selectPrimary)
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
        if (!elementExists(name))
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
        const point = elementPoint(name);
        const value = point ? Number(point.scale === undefined ? 1 : point.scale) : 1;
        return Number.isFinite(value) ? Math.max(0.50, Math.min(elementScaleMaximum, value)) : 1;
    }

    function elementStretchX(name) {
        const point = elementPoint(name);
        const value = point ? Number(point.stretch_x === undefined ? 1 : point.stretch_x) : 1;
        return Number.isFinite(value) ? Math.max(0.25, Math.min(4.00, value)) : 1;
    }

    function elementStretchY(name) {
        const point = elementPoint(name);
        const value = point ? Number(point.stretch_y === undefined ? 1 : point.stretch_y) : 1;
        return Number.isFinite(value) ? Math.max(0.25, Math.min(4.00, value)) : 1;
    }

    function elementOpacity(name) {
        const point = elementPoint(name);
        const minimum = name === "password" ? 20 : 0;
        const value = point ? Number(point.opacity === undefined ? 100 : point.opacity) : 100;
        return Number.isFinite(value) ? Math.max(minimum, Math.min(100, value)) : 100;
    }

    function elementColor(name) {
        if (isCustomImage(name))
            return "auto";
        const point = elementPoint(name);
        const value = point ? String(point.color === undefined ? "auto" : point.color) : "auto";
        return value === "auto" || /^#[0-9a-fA-F]{6}$/.test(value)
            ? value.toLowerCase() : "auto";
    }

    function setDraftColor(name, colorValue) {
        if (name !== "visualizer" && elementNames.indexOf(name) < 0)
            return;
        const value = String(colorValue || "").trim().toLowerCase();
        if (value !== "auto" && !/^#[0-9a-f]{6}$/.test(value)) {
            statusMessage = "Color must be Auto or #RRGGBB";
            return;
        }
        recordUndoBeforeChange();
        if (name === "visualizer") {
            const next = cloneVisualizer(draftVisualizer);
            next.color = value;
            draftVisualizer = next;
        } else {
            const next = cloneLayout(draftLayout);
            next[name].color = value;
            draftLayout = next;
        }
        selectElement(name, false);
        statusMessage = "";
    }

    function setDraftScale(name, scale) {
        if (!elementExists(name))
            return;
        const value = Number(scale);
        if (!Number.isFinite(value))
            return;
        recordUndoBeforeChange();
        const maximum = elementScaleMaximum;
        setDraftScaleSilently(name, Math.round(Math.max(0.50, Math.min(maximum, value)) * 100) / 100);
        selectElement(name, false);
    }

    function setDraftOpacity(name, opacity) {
        if (!elementExists(name))
            return;
        const numeric = Number(opacity);
        if (!Number.isFinite(numeric))
            return;
        const minimum = name === "password" ? 20 : 0;
        const value = Math.round(Math.max(minimum, Math.min(100, numeric)));
        recordUndoBeforeChange();
        if (name === "visualizer") {
            const next = cloneVisualizer(draftVisualizer);
            next.opacity = value;
            draftVisualizer = next;
        } else if (isCustomImage(name)) {
            const next = cloneCustomImages(draftCustomImages);
            const index = next.findIndex(image => image.id === name);
            if (index < 0) return;
            next[index].opacity = value;
            draftCustomImages = next;
        } else {
            const next = cloneLayout(draftLayout);
            next[name].opacity = value;
            draftLayout = next;
        }
        selectElement(name, false);
    }

    function setDraftStretch(name, stretchX, stretchY) {
        if (!elementExists(name))
            return;
        const rawX = Number(stretchX);
        const rawY = Number(stretchY);
        if (!Number.isFinite(rawX) || !Number.isFinite(rawY))
            return;
        const x = Math.round(Math.max(0.25, Math.min(4.00, rawX)) * 100) / 100;
        const y = Math.round(Math.max(0.25, Math.min(4.00, rawY)) * 100) / 100;
        recordUndoBeforeChange();
        if (name === "visualizer") {
            const next = cloneVisualizer(draftVisualizer);
            next.stretch_x = x;
            next.stretch_y = y;
            draftVisualizer = next;
        } else if (isCustomImage(name)) {
            const next = cloneCustomImages(draftCustomImages);
            const index = next.findIndex(image => image.id === name);
            if (index < 0) return;
            next[index].stretch_x = x;
            next[index].stretch_y = y;
            draftCustomImages = next;
        } else {
            const next = cloneLayout(draftLayout);
            next[name].stretch_x = x;
            next[name].stretch_y = y;
            draftLayout = next;
        }
        selectElement(name, false);
    }

    function elementCanHide(name) {
        return name !== "password" && elementExists(name);
    }

    function setDraftVisible(name, visible) {
        if (!elementCanHide(name))
            return;
        recordUndoBeforeChange();
        if (name === "visualizer") {
            const next = cloneVisualizer(draftVisualizer);
            next.enabled = !!visible;
            draftVisualizer = next;
        } else if (isCustomImage(name)) {
            const next = cloneCustomImages(draftCustomImages);
            const index = next.findIndex(image => image.id === name);
            if (index < 0) return;
            next[index].visible = !!visible;
            draftCustomImages = next;
        } else {
            const next = cloneVisibility(draftVisibility);
            next[name] = !!visible;
            draftVisibility = next;
        }
        selectElement(name, false);
    }

    function elementEnabled(name) {
        if (name === "visualizer")
            return draftVisualizer.enabled === true;
        if (isCustomImage(name)) {
            const point = elementPoint(name);
            return point ? point.visible !== false : false;
        }
        return draftVisibility[name] !== false;
    }

    function nextCustomImageId() {
        const prefix = "image-" + Date.now().toString(36);
        let suffix = 0;
        let candidate = prefix;
        while (customImageIndex(candidate) >= 0) {
            suffix += 1;
            candidate = prefix + "_" + suffix;
        }
        return candidate;
    }

    function addCustomImage(imagePath) {
        const value = String(imagePath || "").trim();
        if (!value.startsWith("/") || value.indexOf("://") >= 0) {
            statusMessage = "Custom image must be a local absolute path";
            return;
        }
        if (draftCustomImages.length >= customImageMaximum) {
            statusMessage = "Custom image limit reached (" + customImageMaximum + ")";
            return;
        }
        recordUndoBeforeChange();
        const next = cloneCustomImages(draftCustomImages);
        const id = nextCustomImageId();
        next.push(({
            id: id, path: value, x: 0.5, y: 0.5, scale: 1.0,
            stretch_x: 1.0, stretch_y: 1.0, opacity: 100, rotation: 0, visible: true
        }));
        draftCustomImages = next;
        selectedElement = id;
        selectedElements = [id];
        activeDrawer = "element";
        statusMessage = "Image added. Save to apply.";
    }

    function removeCustomImage(name) {
        const index = customImageIndex(name);
        if (index < 0)
            return;
        recordUndoBeforeChange();
        const next = cloneCustomImages(draftCustomImages);
        next.splice(index, 1);
        draftCustomImages = next;
        selectedElement = "logo";
        selectedElements = ["logo"];
        clearGuides();
        statusMessage = "Image removed. Save to apply.";
    }

    function setDraftEntryTransition(value) {
        const key = String(value || "");
        if (["fade", "pixel", "iris", "edges", "wipe"].indexOf(key) < 0)
            return;
        if (draftEntryTransition === key) {
            replayEntryTransition();
            return;
        }
        recordUndoBeforeChange();
        draftEntryTransition = key;
        replayEntryTransition();
    }

    function setDraftEntryTransitionDuration(value) {
        const numeric = Math.round(Number(value));
        if (!Number.isFinite(numeric)) return;
        recordUndoBeforeChange();
        draftEntryTransitionDuration = Math.max(800, Math.min(6000, numeric));
    }

    function setEntryTransitionDurationFromPointer(pointerX, trackWidth) {
        const width = Number(trackWidth);
        if (!Number.isFinite(width) || width <= 0)
            return;
        const ratio = Math.max(0, Math.min(1, Number(pointerX) / width));
        const duration = 800 + ratio * 5200;
        setDraftEntryTransitionDuration(Math.round(duration / 50) * 50);
    }

    function replayEntryTransition() {
        entryTransitionReplayToken = entryTransitionReplayToken >= 2147483646
            ? 1 : entryTransitionReplayToken + 1;
        statusMessage = "Replaying " + draftEntryTransition + " transition";
    }

    function resetDraft() {
        recordUndoBeforeChange();
        draftLayout = defaultLayout();
        draftCustomImages = [];
        draftVisualizer = defaultVisualizer();
        draftBackgroundOpacity = 100;
        draftEntryTransition = "fade";
        draftEntryTransitionDuration = 1800;
        draftVisibility = defaultVisibility();
        draftBackgroundMode = "black";
        draftBackgroundColor = "#000000";
        draftWallpaperPath = "";
        draftWallpaperFit = "cover";
        draftWallpaperFocalX = 0.5;
        draftWallpaperFocalY = 0.5;
        draftOverlayMode = "none";
        draftOverlayStrength = 0;
        draftWallpaperBlur = 0;
        draftWallpaperBlurExplicit = false;
        draftWeatherUnits = "auto";
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
        draftCustomImages = cloneCustomImages(BarState.lockscreenCustomImages());
        draftVisualizer = cloneVisualizer(BarState.lockscreenVisualizer());
        draftBackgroundOpacity = BarState.lockscreenBackgroundOpacity();
        draftEntryTransition = BarState.lockscreenEntryTransition();
        draftEntryTransitionDuration = BarState.lockscreenEntryTransitionDuration();
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
        draftWallpaperFit = BarState.lockscreenWallpaperFit();
        draftWallpaperFocalX = BarState.lockscreenWallpaperFocalX();
        draftWallpaperFocalY = BarState.lockscreenWallpaperFocalY();
        draftOverlayMode = BarState.lockscreenOverlayMode();
        draftOverlayStrength = BarState.lockscreenOverlayStrength();
        draftWallpaperBlur = BarState.lockscreenWallpaperBlur();
        draftWallpaperBlurExplicit = false;
        draftWeatherUnits = BarState.lockscreenWeatherUnits();
        draftAutoAccents = defaultAutoAccents();
        selectedElement = elementExists(selectedElement) ? selectedElement : "logo";
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

    function toggleDrawer(name) {
        const allowed = ["element", "layout", "background", "weather"];
        if (allowed.indexOf(String(name || "")) < 0)
            return;
        activeDrawer = activeDrawer === name ? "" : name;
        if (activeDrawer !== "element")
            elementPaletteOpen = false;
        if (activeDrawer !== "background")
            backgroundPaletteOpen = false;
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
        activeDrawer = "";
        pickerSuspended = false;
        editingActive = true;
        editorWindow.visible = true;
        FlyoutManager.claimOverlay("lockscreen-editor");
        scheduleContrastRefresh();
        Qt.callLater(() => editorFocus.forceActiveFocus());
    }

    function openFocused() {
        openForScreen(focusedScreen());
    }

    function suspendForWallpaperPicker() {
        if (!open || pickerSuspended || wallpaperPickerProcess.running || customImagePickerProcess.running)
            return;
        if (historyTransactionActive)
            commitHistoryTransaction();
        inertiaOwner = "";
        pickerSuspended = true;
        statusMessage = "Opening lockscreen wallpaper picker…";
        FlyoutManager.releaseOverlay("lockscreen-editor");
        editorWindow.visible = false;
        wallpaperPickerProcess.exec(["bash", wallpaperPickerBackend]);
    }

    function suspendForCustomImagePicker() {
        if (!open || pickerSuspended || customImagePickerProcess.running || wallpaperPickerProcess.running)
            return;
        if (draftCustomImages.length >= customImageMaximum) {
            statusMessage = "Custom image limit reached (" + customImageMaximum + ")";
            return;
        }
        if (historyTransactionActive)
            commitHistoryTransaction();
        inertiaOwner = "";
        pickerSuspended = true;
        statusMessage = "Opening custom image picker…";
        FlyoutManager.releaseOverlay("lockscreen-editor");
        editorWindow.visible = false;
        customImagePickerProcess.exec(["bash", wallpaperPickerBackend]);
    }

    function resumeAfterWallpaperPicker() {
        if (!open || !pickerSuspended)
            return;
        pickerSuspended = false;
        editorWindow.visible = true;
        FlyoutManager.claimOverlay("lockscreen-editor");
        scheduleContrastRefresh();
        Qt.callLater(() => editorFocus.forceActiveFocus());
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
        activeDrawer = "";
        elementPaletteOpen = false;
        backgroundPaletteOpen = false;
        pickerSuspended = false;
        editingActive = false;
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
            draftWallpaperPath,
            draftWallpaperFit,
            String(draftWallpaperFocalX),
            String(draftWallpaperFocalY),
            draftOverlayMode,
            String(draftOverlayStrength),
            String(draftWallpaperBlur),
            draftWeatherUnits,
            JSON.stringify(draftCustomImages),
            JSON.stringify(draftVisualizer),
            String(draftBackgroundOpacity),
            String(draftEntryTransition),
            String(draftEntryTransitionDuration)
        ]);
    }

    function elementLabel(name) {
        if (name === "logo") return "Logo";
        if (name === "time") return "Time";
        if (name === "date") return "Date";
        if (name === "username") return "Username";
        if (name === "weather") return "Weather";
        if (name === "password") return "Password";
        if (name === "visualizer") return "Visualizer";
        if (isCustomImage(name)) return "Image " + (customImageIndex(name) + 1);
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
            if (root.open && exitCode !== 0)
                root.statusMessage = "Lockscreen wallpaper picker closed without a selection";
            else if (root.open
                    && root.statusMessage === "Opening lockscreen wallpaper picker…")
                root.statusMessage = "No wallpaper selected.";
            root.resumeAfterWallpaperPicker();
        }
    }

    Process {
        id: customImagePickerProcess
        stdout: SplitParser {
            onRead: line => root.acceptCustomImageSelection(line)
        }
        onExited: (exitCode, exitStatus) => {
            if (root.open && exitCode !== 0)
                root.statusMessage = "Custom image picker closed without a selection";
            else if (root.open
                    && root.statusMessage === "Opening custom image picker…")
                root.statusMessage = "No image selected.";
            root.resumeAfterWallpaperPicker();
        }
    }

    Shortcut {
        sequence: "Escape"
        context: Qt.ApplicationShortcut
        enabled: root.open && !root.pickerSuspended
        autoRepeat: false
        onActivated: root.close()
    }


    LockPreviewAudioAnalyzer {
        id: previewAudioAnalyzer
        enabled: root.editingActive && !root.pickerSuspended
            && root.draftVisualizer.enabled
        performanceMode: root.draftVisualizer.performance
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

        Shortcut {
            id: editorUndoShortcut
            sequence: "Ctrl+Z"
            context: Qt.WindowShortcut
            enabled: root.open && !root.pickerSuspended && root.undoStack.length > 0
            autoRepeat: false
            onActivated: root.undo()
        }

        Shortcut {
            id: editorRedoShortcut
            sequence: "Ctrl+Shift+Z"
            context: Qt.WindowShortcut
            enabled: root.open && !root.pickerSuspended && root.redoStack.length > 0
            autoRepeat: false
            onActivated: root.redo()
        }

        Shortcut {
            id: editorRedoAlternateShortcut
            sequence: "Ctrl+Y"
            context: Qt.WindowShortcut
            enabled: root.open && !root.pickerSuspended && root.redoStack.length > 0
            autoRepeat: false
            onActivated: root.redo()
        }

        Rectangle {
            id: editorFocus
            anchors.fill: parent
            color: "transparent"
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
                } else if (event.key === Qt.Key_Delete && root.isCustomImage(root.selectedElement)) {
                    root.removeCustomImage(root.selectedElement);
                    event.accepted = true;
                }
            }

            Item {
                id: editorTransitionStart
                x: editorFocus.width + 64
                y: 0
                width: editorFocus.width
                height: editorFocus.height

                Rectangle { anchors.fill: parent; color: "#101318" }
                Rectangle {
                    x: 0
                    y: 0
                    width: parent.width
                    height: Math.max(28, parent.height * 0.035)
                    color: "#1c222b"
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width * 0.62
                    height: parent.height * 0.56
                    radius: 8
                    color: "#202731"
                    border.width: 1
                    border.color: "#3a4657"
                    Rectangle {
                        x: 0
                        y: 0
                        width: parent.width
                        height: Math.max(26, parent.height * 0.07)
                        radius: parent.radius
                        color: "#2a3340"
                    }
                    Text {
                        anchors.centerIn: parent
                        text: "Synthetic desktop preview"
                        color: "#8d99aa"
                        font.family: Theme.fontFamily
                        font.pixelSize: Math.max(12, parent.height * 0.035)
                    }
                }
            }

            LockPreviewScene {
                id: previewScene
                anchors.fill: parent
                theme: Theme
                animationPreference: BarState.lockscreenAnimationPreference()
                entryTransition: root.draftEntryTransition
                entryTransitionDuration: root.draftEntryTransitionDuration
                externallyManagedEntryTransition: true
                externalEntryTransitionRunning: editorTransitionLayer.running
                randomFormationMode: 3
                logoPhysicsHz: BarState.lockscreenLogoPhysicsHz()
                mouseInteractive: BarState.lockscreenMouseInteractiveEnabled()
                showLogo: root.draftVisibility.logo
                showTime: root.draftVisibility.time
                showDate: root.draftVisibility.date
                showUsername: root.draftVisibility.username
                showWeather: root.draftVisibility.weather
                weatherText: root.draftWeatherUnits === "celsius"
                    ? "22°C · Clear" : "72°F · Clear"
                backgroundMode: root.draftBackgroundMode
                wallpaperSource: wallpaperState.source
                backgroundColor: root.draftBackgroundColor
                wallpaperFit: root.draftWallpaperFit
                wallpaperFocalX: root.draftWallpaperFocalX
                wallpaperFocalY: root.draftWallpaperFocalY
                overlayMode: root.draftOverlayMode
                overlayStrength: root.draftOverlayStrength
                wallpaperBlur: root.draftWallpaperBlur
                autoAccents: root.draftAutoAccents
                layout: root.draftLayout
                customImages: root.draftCustomImages
                visualizer: root.draftVisualizer
                audioBands: previewAudioAnalyzer.bands
                backgroundOpacity: root.draftBackgroundOpacity
                previewMode: true
                editorMode: true
                editorVisibility: root.draftVisibility
                editorHeldElement: root.heldElement
                editorHoldScale: root.heldScaleBoost
            }

            LockPreviewTransitionLayer {
                id: editorTransitionLayer
                anchors.fill: parent
                z: 160
                startSource: editorTransitionStart
                endSource: previewScene
                mode: root.draftEntryTransition
                duration: root.draftEntryTransitionDuration
                replayToken: root.entryTransitionReplayToken
            }

            Item {
                id: editorGridOverlay
                anchors.fill: parent
                visible: root.showEditorGrid
                enabled: false
                z: 175

                Rectangle {
                    id: safeAreaGuide
                    x: parent.width * 0.05
                    y: parent.height * 0.08
                    width: parent.width * 0.90
                    height: parent.height * 0.84
                    color: "transparent"
                    border.width: 1
                    border.color: Theme.muted
                    opacity: 0.72
                }

                Rectangle {
                    x: parent.width / 3
                    y: 0
                    width: 1
                    height: parent.height
                    color: Theme.muted
                    opacity: 0.38
                }
                Rectangle {
                    x: parent.width * 2 / 3
                    y: 0
                    width: 1
                    height: parent.height
                    color: Theme.muted
                    opacity: 0.38
                }
                Rectangle {
                    x: parent.width / 2
                    y: 0
                    width: 1
                    height: parent.height
                    color: Theme.focus
                    opacity: 0.56
                }
                Rectangle {
                    x: 0
                    y: parent.height / 3
                    width: parent.width
                    height: 1
                    color: Theme.muted
                    opacity: 0.38
                }
                Rectangle {
                    x: 0
                    y: parent.height * 2 / 3
                    width: parent.width
                    height: 1
                    color: Theme.muted
                    opacity: 0.38
                }
                Rectangle {
                    x: 0
                    y: parent.height / 2
                    width: parent.width
                    height: 1
                    color: Theme.focus
                    opacity: 0.56
                }
            }

            Rectangle {
                id: wallpaperFocalHandle
                visible: root.draftBackgroundMode === "wallpaper"
                    && root.draftWallpaperFit === "cover"
                    && root.draftWallpaperPath.length > 0
                width: 22
                height: 22
                radius: width / 2
                x: root.draftWallpaperFocalX * Math.max(0, parent.width - width)
                y: root.draftWallpaperFocalY * Math.max(0, parent.height - height)
                color: "transparent"
                border.width: 2
                border.color: Theme.focus
                z: 190

                Rectangle {
                    anchors.centerIn: parent
                    width: 4
                    height: 4
                    radius: 2
                    color: Theme.focus
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.CrossCursor
                    preventStealing: true
                    onPressed: root.beginHistoryTransaction()
                    onPositionChanged: mouse => {
                        if (!pressed || editorFocus.width <= 0 || editorFocus.height <= 0)
                            return;
                        const scenePoint = parent.mapToItem(editorFocus, mouse.x, mouse.y);
                        root.setDraftWallpaperFocal(
                            scenePoint.x / editorFocus.width,
                            scenePoint.y / editorFocus.height);
                    }
                    onReleased: root.commitHistoryTransaction()
                    onCanceled: root.commitHistoryTransaction()
                }
            }

            Repeater {
                model: root.editableElementNames()

                Rectangle {
                    required property string modelData
                    readonly property string elementName: modelData
                    readonly property bool enabledElement: root.elementEnabled(elementName)
                    readonly property var point: root.elementPoint(elementName)
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
                            const point = root.elementPoint(parent.elementName);
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
                            const current = root.elementPoint(parent.elementName);
                            root.translateSelectedElements(
                                snapped.x - Number(current.x),
                                snapped.y - Number(current.y), true);
                            const moved = root.elementPoint(parent.elementName);
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


                    Rectangle {
                        id: elementResizeHandle
                        visible: root.selectedElement === parent.elementName
                        width: 16
                        height: 16
                        radius: 3
                        x: parent.width - width / 2
                        y: parent.height - height / 2
                        color: Theme.focus
                        border.width: 1
                        border.color: Theme.foreground
                        z: 20

                        Rectangle {
                            anchors.centerIn: parent
                            width: 5
                            height: 5
                            radius: 1
                            color: Theme.background
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.SizeFDiagCursor
                            preventStealing: true
                            onPressed: mouse => {
                                const point = parent.mapToItem(editorFocus, mouse.x, mouse.y);
                                root.beginResizeElement(parent.parent.elementName, point.x, point.y);
                                mouse.accepted = true;
                            }
                            onPositionChanged: mouse => {
                                if (!pressed)
                                    return;
                                const point = parent.mapToItem(editorFocus, mouse.x, mouse.y);
                                root.updateResizeElement(point.x, point.y);
                            }
                            onReleased: root.endResizeElement()
                            onCanceled: root.endResizeElement()
                        }
                    }

                    Rectangle {
                        id: visualizerWidthLeftHandle
                        visible: root.selectedElement === parent.elementName
                            && parent.elementName === "visualizer"
                        width: 14
                        height: 24
                        radius: 3
                        x: -width / 2
                        y: parent.height / 2 - height / 2
                        color: Theme.focus
                        border.width: 1
                        border.color: Theme.foreground
                        z: 30
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.SizeHorCursor
                            preventStealing: true
                            onPressed: mouse => {
                                const point = parent.mapToItem(editorFocus, mouse.x, mouse.y);
                                root.beginVisualizerWidthResize(point.x);
                                mouse.accepted = true;
                            }
                            onPositionChanged: mouse => {
                                if (!pressed) return;
                                const point = parent.mapToItem(editorFocus, mouse.x, mouse.y);
                                root.updateVisualizerWidthResize(point.x);
                            }
                            onReleased: root.endVisualizerWidthResize()
                            onCanceled: root.endVisualizerWidthResize()
                        }
                    }

                    Rectangle {
                        id: visualizerWidthRightHandle
                        visible: root.selectedElement === parent.elementName
                            && parent.elementName === "visualizer"
                        width: 14
                        height: 24
                        radius: 3
                        x: parent.width - width / 2
                        y: parent.height / 2 - height / 2
                        color: Theme.focus
                        border.width: 1
                        border.color: Theme.foreground
                        z: 30
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.SizeHorCursor
                            preventStealing: true
                            onPressed: mouse => {
                                const point = parent.mapToItem(editorFocus, mouse.x, mouse.y);
                                root.beginVisualizerWidthResize(point.x);
                                mouse.accepted = true;
                            }
                            onPositionChanged: mouse => {
                                if (!pressed) return;
                                const point = parent.mapToItem(editorFocus, mouse.x, mouse.y);
                                root.updateVisualizerWidthResize(point.x);
                            }
                            onReleased: root.endVisualizerWidthResize()
                            onCanceled: root.endVisualizerWidthResize()
                        }
                    }

                    Timer {
                        id: inertiaTimer
                        interval: 16
                        repeat: true
                        running: root.open && !root.pickerSuspended && parent.inertiaActive
                            && root.inertiaOwner === parent.elementName
                        onRunningChanged: {
                            if (!root.open && !running) {
                                parent.inertiaActive = false;
                                parent.flickVelocityX = 0;
                                parent.flickVelocityY = 0;
                            }
                        }
                        onTriggered: {
                            const point = root.elementPoint(parent.elementName);
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
                id: rotationHandle
                visible: root.isCustomImage(root.selectedElement)
                width: 20
                height: 20
                radius: 10
                x: Math.round(root.primaryPoint().x * parent.width - width / 2)
                y: Math.round(root.primaryPoint().y * parent.height
                    - Math.max(54, 100 * root.elementScale(root.selectedElement)) - height / 2)
                color: Theme.background
                border.width: 2
                border.color: Theme.focus
                z: 40

                Text {
                    anchors.centerIn: parent
                    text: "↻"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.SizeAllCursor
                    preventStealing: true
                    onPressed: mouse => {
                        const point = parent.mapToItem(editorFocus, mouse.x, mouse.y);
                        root.beginRotateElement(root.selectedElement, point.x, point.y);
                        mouse.accepted = true;
                    }
                    onPositionChanged: mouse => {
                        if (!pressed)
                            return;
                        const point = parent.mapToItem(editorFocus, mouse.x, mouse.y);
                        root.updateRotateElement(point.x, point.y);
                    }
                    onReleased: root.endRotateElement()
                    onCanceled: root.endRotateElement()
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
                height: editorDockContent.implicitHeight + 18
                color: Theme.popupBackground
                border.width: 1
                border.color: Theme.muted
                z: 300

                ColumnLayout {
                    id: editorDockContent
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

                        Text { text: "Scale"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 9 }
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
                            available: root.elementScale(root.selectedElement) < root.elementScaleMaximum
                            textSize: 10
                            onClicked: root.setDraftScale(root.selectedElement,
                                root.elementScale(root.selectedElement) + 0.10)
                        }

                        Text { text: "X"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 9 }
                        TextField {
                            id: positionXField
                            Layout.preferredWidth: 54
                            text: Number(root.primaryPoint().x * 100).toFixed(1)
                            validator: DoubleValidator { bottom: 0; top: 100; decimals: 1 }
                            selectByMouse: true
                            font.pixelSize: 9
                            onEditingFinished: root.setSelectedCoordinate("x", text)
                        }
                        Text { text: "Y"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 9 }
                        TextField {
                            id: positionYField
                            Layout.preferredWidth: 54
                            text: Number(root.primaryPoint().y * 100).toFixed(1)
                            validator: DoubleValidator { bottom: 0; top: 100; decimals: 1 }
                            selectByMouse: true
                            font.pixelSize: 9
                            onEditingFinished: root.setSelectedCoordinate("y", text)
                        }


                        Text {
                            text: "Rotation"
                            visible: root.isCustomImage(root.selectedElement)
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                        }
                        TextField {
                            Layout.preferredWidth: 58
                            visible: root.isCustomImage(root.selectedElement)
                            text: Number(root.elementRotation(root.selectedElement)).toFixed(1)
                            validator: DoubleValidator { bottom: -180; top: 180; decimals: 1 }
                            selectByMouse: true
                            font.pixelSize: 9
                            onEditingFinished: root.setDraftRotation(root.selectedElement, text)
                        }

                        SettingsButton {
                            id: selectedElementColorButton
                            visible: !root.isCustomImage(root.selectedElement)
                            label: root.elementColor(root.selectedElement) === "auto"
                                ? "Color: Auto" : "Color: " + root.elementColor(root.selectedElement)
                            textSize: 9
                            onClicked: {
                                if (root.activeDrawer !== "element")
                                    root.toggleDrawer("element");
                                root.elementPaletteOpen = true;
                            }
                        }

                        SettingsButton { label: "Undo"; textSize: 9; available: root.undoStack.length > 0; onClicked: root.undo() }
                        SettingsButton { label: "Redo"; textSize: 9; available: root.redoStack.length > 0; onClicked: root.redo() }

                        SettingsButton { label: "Element"; active: root.activeDrawer === "element"; textSize: 9; onClicked: root.toggleDrawer("element") }
                        SettingsButton { label: "Layout"; active: root.activeDrawer === "layout"; textSize: 9; onClicked: root.toggleDrawer("layout") }
                        SettingsButton { label: "Background"; active: root.activeDrawer === "background"; textSize: 9; onClicked: root.toggleDrawer("background") }
                        SettingsButton { label: "Weather"; active: root.activeDrawer === "weather"; textSize: 9; onClicked: root.toggleDrawer("weather") }

                        Item { Layout.fillWidth: true }

                        Text {
                            visible: root.statusMessage.length > 0
                            text: root.statusMessage.length > 0 ? root.statusMessage : "Password cannot be hidden."
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            elide: Text.ElideRight
                            Layout.maximumWidth: 260
                        }

                        SettingsButton { label: "Cancel"; textSize: 9; onClicked: root.close() }
                        SettingsButton {
                            label: "Save"
                            active: true
                            textSize: 9
                            available: !saveProcess.running && !contrastPersistProcess.running
                            onClicked: root.save()
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 7
                        visible: root.activeDrawer === "element"

                        SettingsButton {
                            label: "Add Image"
                            textSize: 9
                            available: root.draftCustomImages.length < root.customImageMaximum
                                && !customImagePickerProcess.running
                            onClicked: root.suspendForCustomImagePicker()
                        }
                        SettingsButton {
                            label: "Remove Image"
                            textSize: 9
                            visible: root.isCustomImage(root.selectedElement)
                            available: visible
                            onClicked: root.removeCustomImage(root.selectedElement)
                        }

                        Text { text: "Opacity"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 9 }
                        SettingsButton {
                            label: "−"
                            textSize: 9
                            available: root.elementOpacity(root.selectedElement) > (root.selectedElement === "password" ? 20 : 0)
                            onClicked: root.setDraftOpacity(root.selectedElement, root.elementOpacity(root.selectedElement) - 5)
                        }
                        Text {
                            text: Math.round(root.elementOpacity(root.selectedElement)) + "%"
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            Layout.preferredWidth: 38
                            horizontalAlignment: Text.AlignHCenter
                        }
                        SettingsButton {
                            label: "+"
                            textSize: 9
                            available: root.elementOpacity(root.selectedElement) < 100
                            onClicked: root.setDraftOpacity(root.selectedElement, root.elementOpacity(root.selectedElement) + 5)
                        }

                        Text { text: "Stretch X"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 9 }
                        SettingsButton { label: "−"; textSize: 9; available: root.elementStretchX(root.selectedElement) > 0.25; onClicked: root.setDraftStretch(root.selectedElement, root.elementStretchX(root.selectedElement) - 0.10, root.elementStretchY(root.selectedElement)) }
                        Text { text: Math.round(root.elementStretchX(root.selectedElement) * 100) + "%"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: 9; Layout.preferredWidth: 42; horizontalAlignment: Text.AlignHCenter }
                        SettingsButton { label: "+"; textSize: 9; available: root.elementStretchX(root.selectedElement) < 4.00; onClicked: root.setDraftStretch(root.selectedElement, root.elementStretchX(root.selectedElement) + 0.10, root.elementStretchY(root.selectedElement)) }

                        Text { text: "Stretch Y"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 9 }
                        SettingsButton { label: "−"; textSize: 9; available: root.elementStretchY(root.selectedElement) > 0.25; onClicked: root.setDraftStretch(root.selectedElement, root.elementStretchX(root.selectedElement), root.elementStretchY(root.selectedElement) - 0.10) }
                        Text { text: Math.round(root.elementStretchY(root.selectedElement) * 100) + "%"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: 9; Layout.preferredWidth: 42; horizontalAlignment: Text.AlignHCenter }
                        SettingsButton { label: "+"; textSize: 9; available: root.elementStretchY(root.selectedElement) < 4.00; onClicked: root.setDraftStretch(root.selectedElement, root.elementStretchX(root.selectedElement), root.elementStretchY(root.selectedElement) + 0.10) }

                        Item { Layout.fillWidth: true }
                        Text {
                            text: root.isCustomImage(root.selectedElement)
                                ? "Custom images are local presentation-only elements."
                                : "Drag the corner handle for direct uniform scaling."
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            elide: Text.ElideRight
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 7
                        visible: root.activeDrawer === "element" && !root.isCustomImage(root.selectedElement)

                        SettingsButton {
                            label: "Reset Position"
                            textSize: 9
                            onClicked: root.resetElementPosition(root.selectedElement)
                        }
                        SettingsButton {
                            label: "Reset to Default"
                            textSize: 9
                            onClicked: root.resetElementToDefault(root.selectedElement)
                        }
                        Text { text: "Element color"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 9 }
                        SettingsButton { label: "Auto"; active: root.elementColor(root.selectedElement) === "auto"; textSize: 9; onClicked: root.setDraftColor(root.selectedElement, "auto") }
                        SettingsButton { label: "White"; active: root.elementColor(root.selectedElement) === "#ffffff"; textSize: 9; onClicked: root.setDraftColor(root.selectedElement, "#ffffff") }
                        SettingsButton { label: "Black"; active: root.elementColor(root.selectedElement) === "#000000"; textSize: 9; onClicked: root.setDraftColor(root.selectedElement, "#000000") }
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
                        Text { text: "All:"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 9 }
                        SettingsButton { label: "Auto All"; textSize: 9; onClicked: root.setAllDraftColors("auto") }
                        SettingsButton { label: "White All"; textSize: 9; onClicked: root.setAllDraftColors("#ffffff") }
                        SettingsButton { label: "Black All"; textSize: 9; onClicked: root.setAllDraftColors("#000000") }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: "Password cannot be hidden. Auto samples each element independently."
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            elide: Text.ElideRight
                        }
                    }


                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 7
                        visible: root.activeDrawer === "element"
                            && root.selectedElement === "visualizer"

                        Text { text: "Bands"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 9 }
                        SettingsButton { label: "−"; textSize: 9; available: root.draftVisualizer.bands > 4; onClicked: root.setDraftVisualizerSetting("bands", root.draftVisualizer.bands - 4) }
                        Text { text: String(root.draftVisualizer.bands); color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: 9; Layout.preferredWidth: 26; horizontalAlignment: Text.AlignHCenter }
                        SettingsButton { label: "+"; textSize: 9; available: root.draftVisualizer.bands < 64; onClicked: root.setDraftVisualizerSetting("bands", root.draftVisualizer.bands + 4) }

                        Text { text: "Gap"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 9 }
                        SettingsButton { label: "−"; textSize: 9; available: root.draftVisualizer.gap > 0; onClicked: root.setDraftVisualizerSetting("gap", root.draftVisualizer.gap - 1) }
                        Text { text: String(root.draftVisualizer.gap); color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: 9; Layout.preferredWidth: 24; horizontalAlignment: Text.AlignHCenter }
                        SettingsButton { label: "+"; textSize: 9; available: root.draftVisualizer.gap < 24; onClicked: root.setDraftVisualizerSetting("gap", root.draftVisualizer.gap + 1) }

                        Text { text: "Width"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 9 }
                        TextField {
                            Layout.preferredWidth: 58
                            text: (Number(root.draftVisualizer.stretch_x || 1) * 100).toFixed(1)
                            validator: DoubleValidator { bottom: 25; top: 400; decimals: 1 }
                            selectByMouse: true
                            font.pixelSize: 9
                            onEditingFinished: root.setDraftVisualizerWidth(text)
                        }

                        Text { text: "Height"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 9 }
                        SettingsButton { label: "−"; textSize: 9; available: root.draftVisualizer.height > 25; onClicked: root.setDraftVisualizerSetting("height", root.draftVisualizer.height - 10) }
                        Text { text: root.draftVisualizer.height + "%"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: 9; Layout.preferredWidth: 38; horizontalAlignment: Text.AlignHCenter }
                        SettingsButton { label: "+"; textSize: 9; available: root.draftVisualizer.height < 300; onClicked: root.setDraftVisualizerSetting("height", root.draftVisualizer.height + 10) }

                        Text { text: "Sensitivity"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 9 }
                        SettingsButton { label: "−"; textSize: 9; available: root.draftVisualizer.sensitivity > 25; onClicked: root.setDraftVisualizerSetting("sensitivity", root.draftVisualizer.sensitivity - 10) }
                        Text { text: root.draftVisualizer.sensitivity + "%"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: 9; Layout.preferredWidth: 38; horizontalAlignment: Text.AlignHCenter }
                        SettingsButton { label: "+"; textSize: 9; available: root.draftVisualizer.sensitivity < 300; onClicked: root.setDraftVisualizerSetting("sensitivity", root.draftVisualizer.sensitivity + 10) }

                        SettingsButton { label: "Straight"; active: root.draftVisualizer.shape === "straight"; textSize: 9; onClicked: root.setDraftVisualizerSetting("shape", "straight") }
                        SettingsButton { label: "Arc"; active: root.draftVisualizer.shape === "arc"; textSize: 9; onClicked: root.setDraftVisualizerSetting("shape", "arc") }
                        SettingsButton { label: "Circle"; active: root.draftVisualizer.shape === "circle"; textSize: 9; onClicked: root.setDraftVisualizerSetting("shape", "circle") }
                        Text { text: "Response"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 9 }
                        SettingsButton { label: "Balanced"; active: root.draftVisualizer.performance === "balanced"; textSize: 9; onClicked: root.setDraftVisualizerSetting("performance", "balanced") }
                        SettingsButton { label: "Responsive"; active: root.draftVisualizer.performance === "responsive"; textSize: 9; onClicked: root.setDraftVisualizerSetting("performance", "responsive") }

                        Text { text: "Arc Bend"; visible: root.draftVisualizer.shape === "arc"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 9 }
                        TextField {
                            Layout.preferredWidth: 58
                            visible: root.draftVisualizer.shape === "arc"
                            text: String(Math.round(Number(root.draftVisualizer.bend || 0)))
                            validator: DoubleValidator { bottom: -360; top: 360; decimals: 0 }
                            selectByMouse: true
                            font.pixelSize: 9
                            onEditingFinished: root.setDraftVisualizerSetting("bend", text)
                        }
                        Item { Layout.fillWidth: true }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 7
                        visible: root.activeDrawer === "layout"

                        SettingsButton { label: "Minimal"; textSize: 9; onClicked: root.applyLayoutPreset("minimal") }
                        SettingsButton { label: "Centered"; textSize: 9; onClicked: root.applyLayoutPreset("centered") }
                        SettingsButton { label: "Information"; textSize: 9; onClicked: root.applyLayoutPreset("information") }
                        SettingsButton { label: "Lower Third"; textSize: 9; onClicked: root.applyLayoutPreset("lower-third") }
                        SettingsButton { label: "Guides"; active: root.showEditorGrid; textSize: 9; onClicked: root.showEditorGrid = !root.showEditorGrid }
                        SettingsButton { label: "Restore Defaults"; textSize: 9; onClicked: root.resetDraft() }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: "Presets change layout and visibility only."
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            elide: Text.ElideRight
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 7
                        visible: root.activeDrawer === "background"

                        SettingsButton { label: "Black"; active: root.draftBackgroundMode === "black"; textSize: 9; onClicked: root.setDraftBackgroundMode("black") }
                        SettingsButton {
                            label: "Wallpaper"
                            active: root.draftBackgroundMode === "wallpaper"
                            textSize: 9
                            onClicked: {
                                if (root.draftWallpaperPath.length > 0)
                                    root.setDraftBackgroundMode("wallpaper");
                                else
                                    root.suspendForWallpaperPicker();
                            }
                        }
                        SettingsButton {
                            label: "Choose Wallpaper"
                            textSize: 9
                            available: !wallpaperPickerProcess.running
                            onClicked: root.suspendForWallpaperPicker()
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
                        spacing: 7
                        visible: root.activeDrawer === "background"

                        Text { text: "Fit"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 9 }
                        SettingsButton { label: "Cover"; active: root.draftWallpaperFit === "cover"; available: root.draftWallpaperPath.length > 0; textSize: 9; onClicked: root.setDraftWallpaperFit("cover") }
                        SettingsButton { label: "Contain"; active: root.draftWallpaperFit === "contain"; available: root.draftWallpaperPath.length > 0; textSize: 9; onClicked: root.setDraftWallpaperFit("contain") }
                        Text { text: "Brightness"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 9 }
                        Rectangle {
                            id: brightnessTrack
                            Layout.preferredWidth: 150; Layout.preferredHeight: 14
                            radius: height / 2; color: Theme.popupBackground; border.width: 1; border.color: Theme.active
                            Rectangle { x: parent.width / 2; width: Math.abs(root.draftBrightness()) * parent.width / 200; height: parent.height; radius: height / 2; color: Theme.focus; transform: Scale { xScale: root.draftBrightness() < 0 ? -1 : 1; origin.x: 0 } }
                            Rectangle { x: (root.draftBrightness() + 100) * parent.width / 200 - width / 2; anchors.verticalCenter: parent.verticalCenter; width: 12; height: 12; radius: 6; color: Theme.foreground }
                            MouseArea { anchors.fill: parent; onPressed: mouse => { root.beginHistoryTransaction(); root.setBrightnessFromPointer(mouse.x, width); } onPositionChanged: mouse => { if (pressed) root.setBrightnessFromPointer(mouse.x, width); } onReleased: root.commitHistoryTransaction() }
                        }
                        Text { text: (root.draftBrightness() > 0 ? "+" : "") + root.draftBrightness() + "%"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: 9; Layout.preferredWidth: 42 }
                        Text { text: "Blur"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 9 }
                        Rectangle {
                            id: blurTrack
                            Layout.preferredWidth: 110; Layout.preferredHeight: 14
                            radius: height / 2; color: Theme.popupBackground; border.width: 1; border.color: Theme.active
                            Rectangle { width: root.draftWallpaperBlur * parent.width / 100; height: parent.height; radius: height / 2; color: Theme.focus }
                            Rectangle { x: root.draftWallpaperBlur * parent.width / 100 - width / 2; anchors.verticalCenter: parent.verticalCenter; width: 12; height: 12; radius: 6; color: Theme.foreground }
                            MouseArea { anchors.fill: parent; onPressed: mouse => { root.beginHistoryTransaction(); root.setBlurFromPointer(mouse.x, width); } onPositionChanged: mouse => { if (pressed) root.setBlurFromPointer(mouse.x, width); } onReleased: root.commitHistoryTransaction() }
                        }
                        Text { text: root.draftWallpaperBlur + "%"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: 9; Layout.preferredWidth: 34 }
                        Item { Layout.fillWidth: true }
                    }


                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 7
                        visible: root.activeDrawer === "background"

                        Text { text: "Background Opacity"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 9 }
                        Rectangle {
                            id: backgroundOpacityTrack
                            Layout.preferredWidth: 150; Layout.preferredHeight: 14
                            radius: height / 2; color: Theme.popupBackground; border.width: 1; border.color: Theme.active
                            Rectangle { width: root.draftBackgroundOpacity * parent.width / 100; height: parent.height; radius: height / 2; color: Theme.focus }
                            Rectangle { x: root.draftBackgroundOpacity * parent.width / 100 - width / 2; anchors.verticalCenter: parent.verticalCenter; width: 12; height: 12; radius: 6; color: Theme.foreground }
                            MouseArea { anchors.fill: parent; onPressed: mouse => { root.beginHistoryTransaction(); root.setBackgroundOpacityFromPointer(mouse.x, width); } onPositionChanged: mouse => { if (pressed) root.setBackgroundOpacityFromPointer(mouse.x, width); } onReleased: root.commitHistoryTransaction() }
                        }
                        Text { text: root.draftBackgroundOpacity + "%"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: 9; Layout.preferredWidth: 36 }
                        SettingsButton { label: "Opaque"; textSize: 9; active: root.draftBackgroundOpacity === 100; onClicked: root.setDraftBackgroundOpacity(100) }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: "Transparency can reveal content from the unlocked desktop behind the secure lock surface."
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            wrapMode: Text.Wrap
                        }
                    }



                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 7
                        visible: root.activeDrawer === "background"

                        Text { text: "Entry Transition"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 9 }
                        SettingsButton { label: "Fade"; active: root.draftEntryTransition === "fade"; textSize: 9; onClicked: root.setDraftEntryTransition("fade") }
                        SettingsButton { label: "Pixel"; active: root.draftEntryTransition === "pixel"; textSize: 9; onClicked: root.setDraftEntryTransition("pixel") }
                        SettingsButton { label: "Reverse Iris"; active: root.draftEntryTransition === "iris"; textSize: 9; onClicked: root.setDraftEntryTransition("iris") }
                        SettingsButton { label: "Edges"; active: root.draftEntryTransition === "edges"; textSize: 9; onClicked: root.setDraftEntryTransition("edges") }
                        SettingsButton { label: "Wipe"; active: root.draftEntryTransition === "wipe"; textSize: 9; onClicked: root.setDraftEntryTransition("wipe") }
                        SettingsButton { label: "Replay Transition"; textSize: 9; onClicked: root.replayEntryTransition() }
                        Text { text: "Transition Speed"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 9 }
                        Rectangle {
                            id: entryTransitionDurationTrack
                            Layout.preferredWidth: 140
                            Layout.preferredHeight: 14
                            radius: height / 2
                            color: Theme.popupBackground
                            border.width: 1
                            border.color: Theme.active
                            Rectangle {
                                width: Math.max(0, Math.min(1,
                                    (root.draftEntryTransitionDuration - 800) / 5200)) * parent.width
                                height: parent.height
                                radius: height / 2
                                color: Theme.focus
                            }
                            Rectangle {
                                width: 12
                                height: 12
                                radius: 6
                                anchors.verticalCenter: parent.verticalCenter
                                x: Math.max(0, Math.min(parent.width - width,
                                    (root.draftEntryTransitionDuration - 800)
                                        * (parent.width - width) / 5200))
                                color: Theme.foreground
                            }
                            MouseArea {
                                anchors.fill: parent
                                onPressed: mouse => {
                                    root.beginHistoryTransaction();
                                    root.setEntryTransitionDurationFromPointer(mouse.x, width);
                                }
                                onPositionChanged: mouse => {
                                    if (pressed)
                                        root.setEntryTransitionDurationFromPointer(mouse.x, width);
                                }
                                onReleased: root.commitHistoryTransaction()
                                onCanceled: root.commitHistoryTransaction()
                            }
                        }
                        Text { text: (root.draftEntryTransitionDuration / 1000).toFixed(2) + "s"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: 9 }
                        Item { Layout.fillWidth: true }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 7
                        visible: root.activeDrawer === "weather"

                        Text { text: "Weather units"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 9 }
                        SettingsButton { label: "Auto"; active: root.draftWeatherUnits === "auto"; textSize: 9; onClicked: root.setDraftWeatherUnits("auto") }
                        SettingsButton { label: "°F"; active: root.draftWeatherUnits === "fahrenheit"; textSize: 9; onClicked: root.setDraftWeatherUnits("fahrenheit") }
                        SettingsButton { label: "°C"; active: root.draftWeatherUnits === "celsius"; textSize: 9; onClicked: root.setDraftWeatherUnits("celsius") }
                        Item { Layout.fillWidth: true }
                        Text { text: "Auto follows the system measurement locale."; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 9; elide: Text.ElideRight }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: visible ? 142 : 0
                        spacing: 12
                        visible: (root.activeDrawer === "element" && root.elementPaletteOpen)
                            || (root.activeDrawer === "background" && root.backgroundPaletteOpen)

                        InlineColorPicker {
                            id: elementColorPicker
                            visible: root.activeDrawer === "element" && root.elementPaletteOpen
                                && !root.isCustomImage(root.selectedElement)
                            Layout.preferredWidth: 320
                            Layout.preferredHeight: visible ? 142 : 0
                            colorValue: root.elementColor(root.selectedElement) === "auto"
                                ? String(root.draftAutoAccents[root.selectedElement] || "#ffffff")
                                : root.elementColor(root.selectedElement)
                            onColorEdited: hex => root.setDraftColor(root.selectedElement, hex)
                        }

                        InlineColorPicker {
                            id: backgroundColorPicker
                            visible: root.activeDrawer === "background" && root.backgroundPaletteOpen
                            Layout.preferredWidth: 320
                            Layout.preferredHeight: visible ? 142 : 0
                            colorValue: root.draftBackgroundColor
                            onColorEdited: hex => root.setDraftBackgroundColor(hex)
                        }

                        Item { Layout.fillWidth: true }
                    }
                }
            }
        }
    }
}
