#!/usr/bin/env python3
from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one anchor, found {count}")
    return text.replace(old, new, 1)


editor_path = Path("config/quickshell/awtarchy/LockscreenEditor.qml")
editor = editor_path.read_text()

editor = replace_once(
    editor,
    '    property var draftLayout: defaultLayout()\n    property var draftCustomImages: []\n',
    '    property var draftLayout: defaultLayout()\n'
    '    property var draftCustomImages: []\n'
    '    property var draftVisualizer: defaultVisualizer()\n'
    '    property int draftBackgroundOpacity: 100\n',
    "editor Pass 3 draft properties",
)

visualizer_default = '''    function defaultVisualizer() {
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
            sensitivity: 100,
            shape: "straight",
            bend: 45
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
        return ({
            enabled: enabled,
            x: Math.max(0.05, Math.min(0.95, Number.isFinite(x) ? x : defaults.x)),
            y: Math.max(0.08, Math.min(0.92, Number.isFinite(y) ? y : defaults.y)),
            scale: Math.max(0.50, Math.min(2.00, Number.isFinite(scale) ? scale : defaults.scale)),
            stretch_x: Math.max(0.25, Math.min(4.00, Number.isFinite(stretchX) ? stretchX : defaults.stretch_x)),
            stretch_y: Math.max(0.25, Math.min(4.00, Number.isFinite(stretchY) ? stretchY : defaults.stretch_y)),
            opacity: Math.max(0, Math.min(100, Number.isFinite(opacity) ? Math.round(opacity) : defaults.opacity)),
            color: color,
            bands: Number.isInteger(bands) ? Math.max(4, Math.min(64, bands)) : defaults.bands,
            gap: Number.isInteger(gap) ? Math.max(0, Math.min(24, gap)) : defaults.gap,
            height: Number.isInteger(responseHeight) ? Math.max(25, Math.min(300, responseHeight)) : defaults.height,
            sensitivity: Number.isInteger(sensitivity) ? Math.max(25, Math.min(300, sensitivity)) : defaults.sensitivity,
            shape: ["straight", "arc", "circle"].indexOf(shape) >= 0 ? shape : defaults.shape,
            bend: Number.isInteger(bend) ? Math.max(-100, Math.min(100, bend)) : defaults.bend
        });
    }

'''
editor = replace_once(
    editor,
    '    function defaultLayout() {\n',
    visualizer_default + '    function defaultLayout() {\n',
    "editor visualizer defaults",
)

editor = replace_once(
    editor,
    '            password: "#ffffff"\n',
    '            password: "#ffffff",\n            visualizer: "#ffffff"\n',
    "editor visualizer auto accent",
)

editor = replace_once(
    editor,
    '            customImages: cloneCustomImages(draftCustomImages),\n            visibility: cloneVisibility(draftVisibility),\n',
    '            customImages: cloneCustomImages(draftCustomImages),\n'
    '            visualizer: cloneSnapshot(draftVisualizer),\n'
    '            visibility: cloneVisibility(draftVisibility),\n',
    "snapshot visualizer",
)
editor = replace_once(
    editor,
    '            backgroundMode: draftBackgroundMode,\n            backgroundColor: draftBackgroundColor,\n',
    '            backgroundMode: draftBackgroundMode,\n'
    '            backgroundColor: draftBackgroundColor,\n'
    '            backgroundOpacity: draftBackgroundOpacity,\n',
    "snapshot background opacity",
)
editor = replace_once(
    editor,
    '        draftCustomImages = cloneCustomImages(snapshot.customImages);\n        draftVisibility = cloneVisibility(snapshot.visibility);\n',
    '        draftCustomImages = cloneCustomImages(snapshot.customImages);\n'
    '        draftVisualizer = cloneVisualizer(snapshot.visualizer);\n'
    '        draftVisibility = cloneVisibility(snapshot.visibility);\n',
    "restore visualizer",
)
editor = replace_once(
    editor,
    '        draftBackgroundColor = validHex(snapshot.backgroundColor)\n            ? String(snapshot.backgroundColor).toLowerCase() : "#000000";\n',
    '        draftBackgroundColor = validHex(snapshot.backgroundColor)\n'
    '            ? String(snapshot.backgroundColor).toLowerCase() : "#000000";\n'
    '        const backgroundOpacity = Number(snapshot.backgroundOpacity);\n'
    '        draftBackgroundOpacity = Number.isFinite(backgroundOpacity)\n'
    '            ? Math.max(0, Math.min(100, Math.round(backgroundOpacity))) : 100;\n',
    "restore background opacity",
)

editor = replace_once(
    editor,
    '        if (isCustomImage(name)) {\n            const next = cloneCustomImages(draftCustomImages);\n            const index = customImageIndex(name);\n            if (index < 0) return;\n            next[index].scale = value;\n            draftCustomImages = next;\n        } else {\n            const next = cloneLayout(draftLayout);\n            next[name].scale = value;\n            draftLayout = next;\n        }\n        scheduleContrastRefresh();\n',
    '        if (name === "visualizer") {\n'
    '            const next = cloneVisualizer(draftVisualizer);\n'
    '            next.scale = value;\n'
    '            draftVisualizer = next;\n'
    '        } else if (isCustomImage(name)) {\n'
    '            const next = cloneCustomImages(draftCustomImages);\n'
    '            const index = customImageIndex(name);\n'
    '            if (index < 0) return;\n'
    '            next[index].scale = value;\n'
    '            draftCustomImages = next;\n'
    '        } else {\n'
    '            const next = cloneLayout(draftLayout);\n'
    '            next[name].scale = value;\n'
    '            draftLayout = next;\n'
    '        }\n'
    '        scheduleContrastRefresh();\n',
    "generic silent scale",
)

editor = replace_once(
    editor,
    '        const nextLayout = cloneLayout(draftLayout);\n        const nextImages = cloneCustomImages(draftCustomImages);\n',
    '        const nextLayout = cloneLayout(draftLayout);\n'
    '        const nextImages = cloneCustomImages(draftCustomImages);\n'
    '        const nextVisualizer = cloneVisualizer(draftVisualizer);\n',
    "group visualizer clone",
)
editor = replace_once(
    editor,
    '        for (const name of selectedElements) {\n            if (isCustomImage(name)) {\n',
    '        for (const name of selectedElements) {\n'
    '            if (name === "visualizer") {\n'
    '                nextVisualizer.x = Number(nextVisualizer.x) + delta.x;\n'
    '                nextVisualizer.y = Number(nextVisualizer.y) + delta.y;\n'
    '            } else if (isCustomImage(name)) {\n',
    "group visualizer movement",
)
editor = replace_once(
    editor,
    '        draftLayout = nextLayout;\n        draftCustomImages = nextImages;\n',
    '        draftLayout = nextLayout;\n'
    '        draftCustomImages = nextImages;\n'
    '        draftVisualizer = nextVisualizer;\n',
    "group visualizer assignment",
)

editor = replace_once(
    editor,
    '        if (isCustomImage(name)) {\n            const next = cloneCustomImages(draftCustomImages);\n            const index = next.findIndex(image => image.id === name);\n            if (index < 0) return;\n            next[index].x = 0.5;\n            next[index].y = 0.5;\n            draftCustomImages = next;\n        } else {\n            const defaults = defaultLayout();\n',
    '        if (name === "visualizer") {\n'
    '            const defaults = defaultVisualizer();\n'
    '            const next = cloneVisualizer(draftVisualizer);\n'
    '            next.x = defaults.x;\n'
    '            next.y = defaults.y;\n'
    '            draftVisualizer = next;\n'
    '        } else if (isCustomImage(name)) {\n'
    '            const next = cloneCustomImages(draftCustomImages);\n'
    '            const index = next.findIndex(image => image.id === name);\n'
    '            if (index < 0) return;\n'
    '            next[index].x = 0.5;\n'
    '            next[index].y = 0.5;\n'
    '            draftCustomImages = next;\n'
    '        } else {\n'
    '            const defaults = defaultLayout();\n',
    "reset visualizer position",
)

background_opacity_fn = '''    function setDraftBackgroundOpacity(value) {
        const numeric = Number(value);
        if (!Number.isFinite(numeric))
            return;
        recordUndoBeforeChange();
        draftBackgroundOpacity = Math.max(0, Math.min(100, Math.round(numeric)));
    }

'''
editor = replace_once(
    editor,
    '    function setDraftBackgroundColor(colorValue) {\n',
    background_opacity_fn + '    function setDraftBackgroundColor(colorValue) {\n',
    "background opacity setter",
)

visualizer_setting_fn = '''    function setDraftVisualizerSetting(name, value) {
        const next = cloneVisualizer(draftVisualizer);
        if (name === "shape") {
            const shape = String(value || "");
            if (["straight", "arc", "circle"].indexOf(shape) < 0)
                return;
            recordUndoBeforeChange();
            next.shape = shape;
        } else {
            const numeric = Math.round(Number(value));
            if (!Number.isFinite(numeric))
                return;
            const bounds = ({
                bands: ({ min: 4, max: 64 }),
                gap: ({ min: 0, max: 24 }),
                height: ({ min: 25, max: 300 }),
                sensitivity: ({ min: 25, max: 300 }),
                bend: ({ min: -100, max: 100 })
            });
            const range = bounds[name];
            if (!range)
                return;
            recordUndoBeforeChange();
            next[name] = Math.max(range.min, Math.min(range.max, numeric));
        }
        draftVisualizer = next;
    }

'''
editor = replace_once(
    editor,
    '    function setDraftWeatherUnits(value) {\n',
    visualizer_setting_fn + '    function setDraftWeatherUnits(value) {\n',
    "visualizer settings setter",
)

editor = replace_once(
    editor,
    '    function editableElementNames() {\n        const names = elementNames.slice();\n',
    '    function editableElementNames() {\n'
    '        const names = elementNames.slice();\n'
    '        names.push("visualizer");\n',
    "visualizer selectable",
)
editor = replace_once(
    editor,
    '    function elementExists(name) {\n        return elementNames.indexOf(name) >= 0 || isCustomImage(name);\n    }\n\n'
    '    function elementPoint(name) {\n        if (isCustomImage(name))\n',
    '    function elementExists(name) {\n'
    '        return name === "visualizer" || elementNames.indexOf(name) >= 0 || isCustomImage(name);\n'
    '    }\n\n'
    '    function elementPoint(name) {\n'
    '        if (name === "visualizer")\n'
    '            return draftVisualizer;\n'
    '        if (isCustomImage(name))\n',
    "visualizer element lookup",
)
editor = replace_once(
    editor,
    '        if (isCustomImage(name)) {\n            const next = cloneCustomImages(draftCustomImages);\n            const index = next.findIndex(image => image.id === name);\n            if (index < 0) return;\n            next[index].x = point.x;\n            next[index].y = point.y;\n            draftCustomImages = next;\n        } else {\n            const next = cloneLayout(draftLayout);\n            next[name].x = point.x;\n            next[name].y = point.y;\n            draftLayout = next;\n        }\n',
    '        if (name === "visualizer") {\n'
    '            const next = cloneVisualizer(draftVisualizer);\n'
    '            next.x = point.x;\n'
    '            next.y = point.y;\n'
    '            draftVisualizer = next;\n'
    '        } else if (isCustomImage(name)) {\n'
    '            const next = cloneCustomImages(draftCustomImages);\n'
    '            const index = next.findIndex(image => image.id === name);\n'
    '            if (index < 0) return;\n'
    '            next[index].x = point.x;\n'
    '            next[index].y = point.y;\n'
    '            draftCustomImages = next;\n'
    '        } else {\n'
    '            const next = cloneLayout(draftLayout);\n'
    '            next[name].x = point.x;\n'
    '            next[name].y = point.y;\n'
    '            draftLayout = next;\n'
    '        }\n',
    "visualizer point write",
)

editor = replace_once(
    editor,
    '    function elementColor(name) {\n        if (isCustomImage(name))\n            return "auto";\n',
    '    function elementColor(name) {\n'
    '        if (isCustomImage(name))\n'
    '            return "auto";\n',
    "element color anchor",
)
editor = replace_once(
    editor,
    '    function setDraftColor(name, colorValue) {\n        if (elementNames.indexOf(name) < 0)\n            return;\n',
    '    function setDraftColor(name, colorValue) {\n'
    '        if (name !== "visualizer" && elementNames.indexOf(name) < 0)\n'
    '            return;\n',
    "visualizer color allow",
)
editor = replace_once(
    editor,
    '        recordUndoBeforeChange();\n        const next = cloneLayout(draftLayout);\n        next[name].color = value;\n        draftLayout = next;\n        selectElement(name, false);\n        statusMessage = "";\n    }\n\n    function setDraftScale(name, scale) {\n',
    '        recordUndoBeforeChange();\n'
    '        if (name === "visualizer") {\n'
    '            const next = cloneVisualizer(draftVisualizer);\n'
    '            next.color = value;\n'
    '            draftVisualizer = next;\n'
    '        } else {\n'
    '            const next = cloneLayout(draftLayout);\n'
    '            next[name].color = value;\n'
    '            draftLayout = next;\n'
    '        }\n'
    '        selectElement(name, false);\n'
    '        statusMessage = "";\n'
    '    }\n\n'
    '    function setDraftScale(name, scale) {\n',
    "visualizer color write",
)

# This block occurs first in setDraftOpacity after the scale function.
old_opacity = '''        if (isCustomImage(name)) {
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
'''
new_opacity = '''        if (name === "visualizer") {
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
'''
editor = replace_once(editor, old_opacity, new_opacity, "visualizer opacity write")

old_stretch = '''        if (isCustomImage(name)) {
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
'''
new_stretch = '''        if (name === "visualizer") {
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
'''
editor = replace_once(editor, old_stretch, new_stretch, "visualizer stretch write")

editor = replace_once(
    editor,
    '        recordUndoBeforeChange();\n        if (isCustomImage(name)) {\n            const next = cloneCustomImages(draftCustomImages);\n',
    '        recordUndoBeforeChange();\n'
    '        if (name === "visualizer") {\n'
    '            const next = cloneVisualizer(draftVisualizer);\n'
    '            next.enabled = !!visible;\n'
    '            draftVisualizer = next;\n'
    '        } else if (isCustomImage(name)) {\n'
    '            const next = cloneCustomImages(draftCustomImages);\n',
    "visualizer visibility write",
)
editor = replace_once(
    editor,
    '    function elementEnabled(name) {\n        if (isCustomImage(name)) {\n',
    '    function elementEnabled(name) {\n'
    '        if (name === "visualizer")\n'
    '            return draftVisualizer.enabled === true;\n'
    '        if (isCustomImage(name)) {\n',
    "visualizer enabled reader",
)

editor = replace_once(
    editor,
    '        const next = cloneLayout(draftLayout);\n        for (const name of elementNames)\n            next[name].color = value;\n        draftLayout = next;\n',
    '        const next = cloneLayout(draftLayout);\n'
    '        for (const name of elementNames)\n'
    '            next[name].color = value;\n'
    '        draftLayout = next;\n'
    '        const nextVisualizer = cloneVisualizer(draftVisualizer);\n'
    '        nextVisualizer.color = value;\n'
    '        draftVisualizer = nextVisualizer;\n',
    "all colors include visualizer",
)

editor = replace_once(
    editor,
    '        draftLayout = defaultLayout();\n        draftCustomImages = [];\n        draftVisibility = defaultVisibility();\n',
    '        draftLayout = defaultLayout();\n'
    '        draftCustomImages = [];\n'
    '        draftVisualizer = defaultVisualizer();\n'
    '        draftBackgroundOpacity = 100;\n'
    '        draftVisibility = defaultVisibility();\n',
    "reset Pass 3 draft",
)
editor = replace_once(
    editor,
    '        draftLayout = cloneLayout(BarState.lockscreenLayout());\n        draftCustomImages = cloneCustomImages(BarState.lockscreenCustomImages());\n',
    '        draftLayout = cloneLayout(BarState.lockscreenLayout());\n'
    '        draftCustomImages = cloneCustomImages(BarState.lockscreenCustomImages());\n'
    '        draftVisualizer = cloneVisualizer(BarState.lockscreenVisualizer());\n'
    '        draftBackgroundOpacity = BarState.lockscreenBackgroundOpacity();\n',
    "load Pass 3 persisted state",
)
editor = replace_once(
    editor,
    '            draftWeatherUnits,\n            JSON.stringify(draftCustomImages)\n',
    '            draftWeatherUnits,\n'
    '            JSON.stringify(draftCustomImages),\n'
    '            JSON.stringify(draftVisualizer),\n'
    '            String(draftBackgroundOpacity)\n',
    "save Pass 3 state",
)
editor = replace_once(
    editor,
    '        if (name === "password") return "Password";\n        if (isCustomImage(name)) return "Image " + (customImageIndex(name) + 1);\n',
    '        if (name === "password") return "Password";\n'
    '        if (name === "visualizer") return "Visualizer";\n'
    '        if (isCustomImage(name)) return "Image " + (customImageIndex(name) + 1);\n',
    "visualizer label",
)

# Preview analyzer is strictly editor-scoped and stops during Awtwall picker ownership.
analyzer_component = '''    LockPreviewAudioAnalyzer {
        id: previewAudioAnalyzer
        enabled: root.editingActive && !root.pickerSuspended
            && root.draftVisualizer.enabled
    }

'''
editor = replace_once(
    editor,
    '    PanelWindow {\n        id: editorWindow\n',
    analyzer_component + '    PanelWindow {\n        id: editorWindow\n',
    "preview analyzer component",
)
editor = replace_once(
    editor,
    '            color: "#000000"\n            focus: true\n',
    '            color: "transparent"\n            focus: true\n',
    "transparent editor backing",
)
editor = replace_once(
    editor,
    '                layout: root.draftLayout\n                customImages: root.draftCustomImages\n',
    '                layout: root.draftLayout\n'
    '                customImages: root.draftCustomImages\n'
    '                visualizer: root.draftVisualizer\n'
    '                audioBands: previewAudioAnalyzer.bands\n'
    '                backgroundOpacity: root.draftBackgroundOpacity\n',
    "preview Pass 3 wiring",
)

# Visualizer-specific controls live in the existing Element drawer.
visualizer_controls = '''
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

                        Text { text: "Bend"; visible: root.draftVisualizer.shape === "arc"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 9 }
                        Slider {
                            Layout.preferredWidth: 100
                            visible: root.draftVisualizer.shape === "arc"
                            from: -100; to: 100; stepSize: 1
                            value: root.draftVisualizer.bend
                            onPressedChanged: { if (pressed) root.beginHistoryTransaction(); else root.commitHistoryTransaction(); }
                            onMoved: root.setDraftVisualizerSetting("bend", value)
                        }
                        Text { text: String(root.draftVisualizer.bend); visible: root.draftVisualizer.shape === "arc"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: 9; Layout.preferredWidth: 28 }
                        Item { Layout.fillWidth: true }
                    }
'''
editor = replace_once(
    editor,
    '                    RowLayout {\n                        Layout.fillWidth: true\n                        spacing: 7\n                        visible: root.activeDrawer === "layout"\n',
    visualizer_controls + '\n                    RowLayout {\n                        Layout.fillWidth: true\n                        spacing: 7\n                        visible: root.activeDrawer === "layout"\n',
    "visualizer element controls",
)

background_opacity_controls = '''
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 7
                        visible: root.activeDrawer === "background"

                        Text { text: "Background Opacity"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 9 }
                        Slider {
                            id: backgroundOpacitySlider
                            Layout.preferredWidth: 150
                            from: 0; to: 100; stepSize: 1
                            value: root.draftBackgroundOpacity
                            onPressedChanged: { if (pressed) root.beginHistoryTransaction(); else root.commitHistoryTransaction(); }
                            onMoved: root.setDraftBackgroundOpacity(value)
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
'''
editor = replace_once(
    editor,
    '                    RowLayout {\n                        Layout.fillWidth: true\n                        spacing: 7\n                        visible: root.activeDrawer === "weather"\n',
    background_opacity_controls + '\n                    RowLayout {\n                        Layout.fillWidth: true\n                        spacing: 7\n                        visible: root.activeDrawer === "weather"\n',
    "background opacity controls",
)

editor_path.write_text(editor)


qs_path = Path("config/quickshell/awtarchy/QuickSettings.qml")
qs = qs_path.read_text()
qs_anchor = '''                                        Text { Layout.fillWidth: true; text: "Logo Physics"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: root.scaledText(9) }
                                        RowLayout {
                                            spacing: 5
                                            SettingsButton { label: "30 Hz"; active: BarState.lockscreenLogoPhysicsHz() === 30; textSize: root.scaledText(9); onClicked: root.queueStateCommand(["set-lockscreen-logo-physics-hz", "30"]) }
                                            SettingsButton { label: "60 Hz"; active: BarState.lockscreenLogoPhysicsHz() === 60; textSize: root.scaledText(9); onClicked: root.queueStateCommand(["set-lockscreen-logo-physics-hz", "60"]) }
                                            SettingsButton { label: "90 Hz"; active: BarState.lockscreenLogoPhysicsHz() === 90; textSize: root.scaledText(9); onClicked: root.queueStateCommand(["set-lockscreen-logo-physics-hz", "90"]) }
                                        }
'''
qs_new = qs_anchor + '''                                        Text { Layout.fillWidth: true; text: "Visualizer"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: root.scaledText(9) }
                                        SettingsButton {
                                            label: BarState.lockscreenVisualizer().enabled ? "On" : "Off"
                                            active: BarState.lockscreenVisualizer().enabled
                                            textSize: root.scaledText(9)
                                            onClicked: root.queueStateCommand([
                                                "set-lockscreen-visualizer-enabled",
                                                BarState.lockscreenVisualizer().enabled ? "false" : "true"
                                            ])
                                        }
                                        Text { Layout.fillWidth: true; text: "Background Opacity"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: root.scaledText(9) }
                                        RowLayout {
                                            spacing: 5
                                            SettingsButton { label: "100%"; active: BarState.lockscreenBackgroundOpacity() === 100; textSize: root.scaledText(9); onClicked: root.queueStateCommand(["set-lockscreen-background-opacity", "100"]) }
                                            SettingsButton { label: "50%"; active: BarState.lockscreenBackgroundOpacity() === 50; textSize: root.scaledText(9); onClicked: root.queueStateCommand(["set-lockscreen-background-opacity", "50"]) }
                                            SettingsButton { label: "0%"; active: BarState.lockscreenBackgroundOpacity() === 0; textSize: root.scaledText(9); onClicked: root.queueStateCommand(["set-lockscreen-background-opacity", "0"]) }
                                        }
'''
qs = replace_once(qs, qs_anchor, qs_new, "Quick Settings Pass 3 controls")
qs_path.write_text(qs)
