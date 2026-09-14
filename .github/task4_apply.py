from pathlib import Path


def one(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one match, got {count}")
    return text.replace(old, new, 1)


def exact(text, old, new, expected, label):
    count = text.count(old)
    if count != expected:
        raise RuntimeError(f"{label}: expected {expected} matches, got {count}")
    return text.replace(old, new)


root = Path('.')

# Desktop persistent-state reader.
p = root / 'config/quickshell/awtarchy/BarState.qml'
s = p.read_text()
s = one(s,
'''        opacity: 100,\n        color: "auto",\n        bands: 16,''',
'''        opacity: 100,\n        rotation: 0,\n        color: "auto",\n        bands: 16,''',
'BarState visualizer default rotation')
s = exact(s,
'opacity: 100, color: "auto" })',
'opacity: 100, rotation: 0, color: "auto" })',
6,
'BarState built-in default rotations')
s = one(s,
'''        const opacity = Number(value.opacity ?? defaults.opacity);\n        const color = String(value.color ?? defaults.color).toLowerCase();''',
'''        const opacity = Number(value.opacity ?? defaults.opacity);\n        const rotation = Number(value.rotation ?? defaults.rotation);\n        const color = String(value.color ?? defaults.color).toLowerCase();''',
'BarState visualizer rotation parse')
s = one(s,
'''                || !Number.isFinite(opacity) || opacity < 0 || opacity > 100\n                || (color !== "auto" && !/^#[0-9a-f]{6}$/.test(color))''',
'''                || !Number.isFinite(opacity) || opacity < 0 || opacity > 100\n                || !Number.isFinite(rotation) || rotation < -180 || rotation > 180\n                || (color !== "auto" && !/^#[0-9a-f]{6}$/.test(color))''',
'BarState visualizer rotation validation')
s = one(s,
'''            opacity: Math.round(opacity),\n            color: color,''',
'''            opacity: Math.round(opacity),\n            rotation: rotation,\n            color: color,''',
'BarState visualizer rotation output')
s = one(s,
'''            stretch_x: fallback.stretch_x, stretch_y: fallback.stretch_y,\n            opacity: fallback.opacity, color: fallbackColor''',
'''            stretch_x: fallback.stretch_x, stretch_y: fallback.stretch_y,\n            opacity: fallback.opacity, rotation: fallback.rotation || 0, color: fallbackColor''',
'BarState layout fallback rotation')
s = one(s,
'''        const opacity = Number(value.opacity === undefined ? 100 : value.opacity);\n        const rawColor = String(value.color === undefined ? "auto" : value.color);''',
'''        const opacity = Number(value.opacity === undefined ? 100 : value.opacity);\n        const rotation = Number(value.rotation === undefined ? 0 : value.rotation);\n        const rawColor = String(value.color === undefined ? "auto" : value.color);''',
'BarState layout rotation parse')
s = one(s,
'''                || !Number.isFinite(opacity)\n                || x < minX || x > maxX || y < minY || y > maxY''',
'''                || !Number.isFinite(opacity) || !Number.isFinite(rotation)\n                || x < minX || x > maxX || y < minY || y > maxY''',
'BarState layout rotation finite validation')
s = one(s,
'''                || stretchY < 0.25 || stretchY > 4.00\n                || opacity < minOpacity || opacity > 100)''',
'''                || stretchY < 0.25 || stretchY > 4.00\n                || opacity < minOpacity || opacity > 100\n                || rotation < -180 || rotation > 180)''',
'BarState layout rotation bounds')
s = one(s,
'''        return ({ x: x, y: y, scale: scale, stretch_x: stretchX,\n            stretch_y: stretchY, opacity: opacity, color: color });''',
'''        return ({ x: x, y: y, scale: scale, stretch_x: stretchX,\n            stretch_y: stretchY, opacity: opacity, rotation: rotation, color: color });''',
'BarState layout rotation output')
p.write_text(s)

# Secure shell normalizer.
p = root / 'config/quickshell/awtarchy-lock/shell.qml'
s = p.read_text()
s = one(s,
'''            opacity: 100,\n            color: "auto",\n            bands: 16,''',
'''            opacity: 100,\n            rotation: 0,\n            color: "auto",\n            bands: 16,''',
'secure visualizer default rotation')
s = exact(s,
'opacity: 100, color: "auto" })',
'opacity: 100, rotation: 0, color: "auto" })',
6,
'secure built-in default rotations')
s = one(s,
'''        const opacity = Number(value.opacity === undefined ? defaults.opacity : value.opacity);\n        const color = String(value.color === undefined ? defaults.color : value.color).toLowerCase();''',
'''        const opacity = Number(value.opacity === undefined ? defaults.opacity : value.opacity);\n        const rotation = Number(value.rotation === undefined ? defaults.rotation : value.rotation);\n        const color = String(value.color === undefined ? defaults.color : value.color).toLowerCase();''',
'secure visualizer rotation parse')
s = one(s,
'''                || !Number.isFinite(opacity) || opacity < 0 || opacity > 100\n                || (color !== "auto" && !/^#[0-9a-f]{6}$/.test(color))''',
'''                || !Number.isFinite(opacity) || opacity < 0 || opacity > 100\n                || !Number.isFinite(rotation) || rotation < -180 || rotation > 180\n                || (color !== "auto" && !/^#[0-9a-f]{6}$/.test(color))''',
'secure visualizer rotation validation')
s = one(s,
'''            opacity: opacity,\n            color: color,''',
'''            opacity: opacity,\n            rotation: rotation,\n            color: color,''',
'secure visualizer rotation output')
s = one(s,
'''        const fallbackOpacity = Number(fallback.opacity === undefined ? 100 : fallback.opacity);\n        if (!value || typeof value !== "object" || Array.isArray(value))\n            return ({ x: fallback.x, y: fallback.y, scale: fallback.scale, stretch_x: 1.0, stretch_y: 1.0, opacity: fallbackOpacity, color: fallbackColor });''',
'''        const fallbackOpacity = Number(fallback.opacity === undefined ? 100 : fallback.opacity);\n        const fallbackRotation = Number(fallback.rotation === undefined ? 0 : fallback.rotation);\n        if (!value || typeof value !== "object" || Array.isArray(value))\n            return ({ x: fallback.x, y: fallback.y, scale: fallback.scale, stretch_x: 1.0, stretch_y: 1.0, opacity: fallbackOpacity, rotation: fallbackRotation, color: fallbackColor });''',
'secure layout fallback rotation')
s = one(s,
'''        const opacity = Number(value.opacity === undefined ? 100 : value.opacity);\n        const rawColor = String(value.color === undefined ? "auto" : value.color);''',
'''        const opacity = Number(value.opacity === undefined ? 100 : value.opacity);\n        const rotation = Number(value.rotation === undefined ? 0 : value.rotation);\n        const rawColor = String(value.color === undefined ? "auto" : value.color);''',
'secure layout rotation parse')
s = one(s,
'''                || !Number.isFinite(opacity)\n                || x < minX || x > maxX || y < minY || y > maxY''',
'''                || !Number.isFinite(opacity) || !Number.isFinite(rotation)\n                || x < minX || x > maxX || y < minY || y > maxY''',
'secure layout rotation finite validation')
s = one(s,
'''                || stretchY < 0.25 || stretchY > 4.00\n                || opacity < minOpacity || opacity > 100)\n            return ({ x: fallback.x, y: fallback.y, scale: fallback.scale, stretch_x: 1.0, stretch_y: 1.0, opacity: fallbackOpacity, color: fallbackColor });\n        return ({ x: x, y: y, scale: scale, stretch_x: stretchX, stretch_y: stretchY, opacity: opacity, color: color });''',
'''                || stretchY < 0.25 || stretchY > 4.00\n                || opacity < minOpacity || opacity > 100\n                || rotation < -180 || rotation > 180)\n            return ({ x: fallback.x, y: fallback.y, scale: fallback.scale, stretch_x: 1.0, stretch_y: 1.0, opacity: fallbackOpacity, rotation: fallbackRotation, color: fallbackColor });\n        return ({ x: x, y: y, scale: scale, stretch_x: stretchX, stretch_y: stretchY, opacity: opacity, rotation: rotation, color: color });''',
'secure layout rotation bounds/output')
p.write_text(s)

# Editor transform model and direct manipulation.
p = root / 'config/quickshell/awtarchy/LockscreenEditor.qml'
s = p.read_text()
s = one(s,
'''    property var draftCustomImages: []\n    property var draftVisualizer: defaultVisualizer()''',
'''    property var draftCustomImages: []\n    property var draftTimezoneClocks: []\n    property var draftCustomTexts: []\n    property var draftVisualizer: defaultVisualizer()''',
'editor future dynamic transform owners')
s = one(s,
'''            opacity: 100,\n            color: "auto",\n            bands: 16,''',
'''            opacity: 100,\n            rotation: 0,\n            color: "auto",\n            bands: 16,''',
'editor visualizer default rotation')
s = one(s,
'''        const opacity = Number(raw.opacity === undefined ? defaults.opacity : raw.opacity);\n        const rawColor = String(raw.color === undefined ? defaults.color : raw.color).toLowerCase();''',
'''        const opacity = Number(raw.opacity === undefined ? defaults.opacity : raw.opacity);\n        const rotation = Number(raw.rotation === undefined ? defaults.rotation : raw.rotation);\n        const rawColor = String(raw.color === undefined ? defaults.color : raw.color).toLowerCase();''',
'editor visualizer rotation parse')
s = one(s,
'''            opacity: Math.max(0, Math.min(100, Number.isFinite(opacity) ? Math.round(opacity) : defaults.opacity)),\n            color: color,''',
'''            opacity: Math.max(0, Math.min(100, Number.isFinite(opacity) ? Math.round(opacity) : defaults.opacity)),\n            rotation: normalizedRotation(Number.isFinite(rotation) ? rotation : defaults.rotation),\n            color: color,''',
'editor visualizer rotation output')
s = exact(s,
'opacity: 100, color: "auto" })',
'opacity: 100, rotation: 0, color: "auto" })',
6,
'editor built-in default rotations')
s = one(s,
'''                opacity: current.opacity,\n                color: current.color''',
'''                opacity: current.opacity,\n                rotation: current.rotation,\n                color: current.color''',
'layout preset preserves rotation')
s = one(s,
'''            const opacity = Number(raw.opacity === undefined ? 100 : raw.opacity); const rawColor = String(raw.color === undefined ? "auto" : raw.color);''',
'''            const opacity = Number(raw.opacity === undefined ? 100 : raw.opacity); const rotation = Number(raw.rotation === undefined ? 0 : raw.rotation); const rawColor = String(raw.color === undefined ? "auto" : raw.color);''',
'cloneLayout rotation parse')
s = one(s,
'''                stretch_y: Math.max(0.25, Math.min(4.00, Number.isFinite(stretchY) ? stretchY : 1)),\n                opacity: Math.max(password ? 20 : 0, Math.min(100, Number.isFinite(opacity) ? opacity : 100)), color: color });''',
'''                stretch_y: Math.max(0.25, Math.min(4.00, Number.isFinite(stretchY) ? stretchY : 1)),\n                opacity: Math.max(password ? 20 : 0, Math.min(100, Number.isFinite(opacity) ? opacity : 100)),\n                rotation: normalizedRotation(Number.isFinite(rotation) ? rotation : 0), color: color });''',
'cloneLayout rotation output')
old = '''    function elementRotation(name) {\n        const index = customImageIndex(name);\n        if (index < 0)\n            return 0;\n        return normalizedRotation(draftCustomImages[index].rotation === undefined\n            ? 0 : draftCustomImages[index].rotation);\n    }\n\n    function setDraftRotationSilently(name, rotation) {\n        const index = customImageIndex(name);\n        if (index < 0)\n            return;\n        const next = cloneCustomImages(draftCustomImages);\n        next[index].rotation = normalizedRotation(rotation);\n        draftCustomImages = next;\n    }\n\n    function setDraftRotation(name, rotation) {\n        if (!isCustomImage(name))\n            return;\n        const numeric = Number(rotation);\n        if (!Number.isFinite(numeric)) {\n            statusMessage = "Rotation must be a number";\n            return;\n        }\n        recordUndoBeforeChange();\n        setDraftRotationSilently(name, numeric);\n        selectElement(name, false);\n        statusMessage = "Image rotation updated";\n    }'''
new = '''    function elementRotation(name) {\n        const point = elementPoint(name);\n        return normalizedRotation(point && point.rotation !== undefined ? point.rotation : 0);\n    }\n\n    function dynamicRotationIndex(name, prefix, values) {\n        if (!name.startsWith(prefix) || !Array.isArray(values)) return -1;\n        const id = name.slice(prefix.length);\n        for (let i = 0; i < values.length; ++i) {\n            if (String(values[i].id || "") === id) return i;\n        }\n        return -1;\n    }\n\n    function setDraftRotationSilently(name, rotation) {\n        const value = normalizedRotation(rotation);\n        if (name === "visualizer") {\n            const next = cloneVisualizer(draftVisualizer); next.rotation = value; draftVisualizer = next; return;\n        }\n        if (isCustomImage(name)) {\n            const next = cloneCustomImages(draftCustomImages); const index = customImageIndex(name);\n            if (index < 0) return; next[index].rotation = value; draftCustomImages = next; return;\n        }\n        if (name.startsWith("timezone:")) {\n            const index = dynamicRotationIndex(name, "timezone:", draftTimezoneClocks);\n            if (index < 0) return; const next = cloneSnapshot(draftTimezoneClocks); next[index].rotation = value; draftTimezoneClocks = next; return;\n        }\n        if (name.startsWith("text:")) {\n            const index = dynamicRotationIndex(name, "text:", draftCustomTexts);\n            if (index < 0) return; const next = cloneSnapshot(draftCustomTexts); next[index].rotation = value; draftCustomTexts = next; return;\n        }\n        if (elementNames.indexOf(name) >= 0) {\n            const next = cloneLayout(draftLayout); next[name].rotation = value; draftLayout = next;\n        }\n    }\n\n    function setElementRotation(name, value) {\n        if (!elementExists(name)) return;\n        const numeric = Number(value);\n        if (!Number.isFinite(numeric)) { statusMessage = "Rotation must be a number"; return; }\n        recordUndoBeforeChange();\n        setDraftRotationSilently(name, numeric);\n        selectElement(name, false);\n        statusMessage = elementLabel(name) + " rotation updated";\n        scheduleContrastRefresh();\n    }\n\n    function setDraftRotation(name, rotation) {\n        setElementRotation(name, rotation);\n    }'''
s = one(s, old, new, 'generic editor rotation functions')
s = one(s,
'''    function beginRotateElement(name, sceneX, sceneY) {\n        if (!isCustomImage(name) || editorFocus.width <= 0 || editorFocus.height <= 0)''',
'''    function beginRotateElement(name, sceneX, sceneY) {\n        if (!elementExists(name) || editorFocus.width <= 0 || editorFocus.height <= 0)''',
'generic rotate handle eligibility')
s = one(s,
'''                        Text { text: "Rotation"; visible: root.isCustomImage(root.selectedElement); color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 9 }\n                        TextField { id: rotationField; Layout.preferredWidth: 68; visible: root.isCustomImage(root.selectedElement); text: Number(root.elementRotation(root.selectedElement)).toFixed(1); selectByMouse: true; font.pixelSize: 9; onEditingFinished: root.setDraftRotation(root.selectedElement, text) }\n                        SettingsButton { label: "0°"; visible: root.isCustomImage(root.selectedElement); textSize: 9; onClicked: root.setDraftRotation(root.selectedElement, 0) }\n                        SettingsButton { label: "90°"; visible: root.isCustomImage(root.selectedElement); textSize: 9; onClicked: root.setDraftRotation(root.selectedElement, 90) }\n                        SettingsButton { label: "180°"; visible: root.isCustomImage(root.selectedElement); textSize: 9; onClicked: root.setDraftRotation(root.selectedElement, 180) }\n                        SettingsButton { label: "270°"; visible: root.isCustomImage(root.selectedElement); textSize: 9; onClicked: root.setDraftRotation(root.selectedElement, 270) }''',
'''                        Text { text: "Rotation"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 9 }\n                        TextField { id: rotationField; Layout.preferredWidth: 68; text: Number(root.elementRotation(root.selectedElement)).toFixed(1); selectByMouse: true; font.pixelSize: 9; onEditingFinished: root.setDraftRotation(root.selectedElement, text) }\n                        SettingsButton { label: "0°"; textSize: 9; onClicked: root.setDraftRotation(root.selectedElement, 0) }\n                        SettingsButton { label: "90°"; textSize: 9; onClicked: root.setDraftRotation(root.selectedElement, 90) }\n                        SettingsButton { label: "180°"; textSize: 9; onClicked: root.setDraftRotation(root.selectedElement, 180) }\n                        SettingsButton { label: "270°"; textSize: 9; onClicked: root.setDraftRotation(root.selectedElement, 270) }''',
'rotation settings visible for all elements')
s = one(s,
'''            Rectangle { id: rotationHandle; visible: root.isCustomImage(root.selectedElement);''',
'''            Rectangle { id: rotationHandle; visible: root.elementExists(root.selectedElement);''',
'rotation handle visible for all elements')
p.write_text(s)

# Shared secure/editor scene. Keep both scene files byte-identical.
p = root / 'config/quickshell/awtarchy-lock/LockScene.qml'
s = p.read_text()
s = one(s,
'''    function elementRotation(name) {\n        const image = customImageForName(name);\n        if (!image)\n            return 0;\n        const value = Number(image.rotation === undefined ? 0 : image.rotation);\n        return Number.isFinite(value) ? Math.max(-180, Math.min(180, value)) : 0;\n    }''',
'''    function elementRotation(name) {\n        const point = presentationPoint(name);\n        const value = Number(point && point.rotation !== undefined ? point.rotation : 0);\n        return Number.isFinite(value) ? Math.max(-180, Math.min(180, value)) : 0;\n    }''',
'shared generic rotation reader')
s = one(s,
'''            scale: root.elementScale("visualizer")\n            transformOrigin: Item.Center''',
'''            scale: root.elementScale("visualizer")\n            rotation: root.elementRotation("visualizer")\n            transformOrigin: Item.Center''',
'visualizer rotation render')
s = one(s,
'''            scale: root.elementScale("logo")\n            transformOrigin: Item.Center''',
'''            scale: root.elementScale("logo")\n            rotation: root.elementRotation("logo")\n            transformOrigin: Item.Center''',
'logo rotation render')
for name, item_id in [('time', 'timeItem'), ('date', 'dateItem'), ('username', 'usernameItem'), ('weather', 'weatherItem')]:
    s = one(s,
        f'''            scale: root.elementScale("{name}")\n            transformOrigin: Item.Center''',
        f'''            scale: root.elementScale("{name}")\n            rotation: root.elementRotation("{name}")\n            transformOrigin: Item.Center''',
        f'{name} rotation render')
s = one(s,
'''        Item {\n            visible: root.previewMode\n            x: root.passwordCenterX - width / 2''',
'''        Item {\n            visible: root.previewMode\n            rotation: root.elementRotation("password")\n            transformOrigin: Item.Center\n            x: root.passwordCenterX - width / 2''',
'preview password rotation render')
p.write_text(s)
(root / 'config/quickshell/awtarchy/LockPreviewScene.qml').write_text(s)

# Secure visible password presentation consumes the scene transform only.
p = root / 'config/quickshell/awtarchy-lock/LockSurface.qml'
s = p.read_text()
s = one(s,
'''        z: 1100\n        opacity: scene.securePasswordEntryOpacity * scene.elementOpacity("password")\n        transform: Scale {''',
'''        z: 1100\n        opacity: scene.securePasswordEntryOpacity * scene.elementOpacity("password")\n        rotation: scene.elementRotation("password")\n        transformOrigin: Item.Center\n        transform: Scale {''',
'secure password rotation render')
p.write_text(s)
