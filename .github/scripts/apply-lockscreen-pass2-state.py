#!/usr/bin/env python3
from pathlib import Path
import re


def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


def regex_once(text, pattern, repl, label):
    new, count = re.subn(pattern, repl, text, count=1, flags=re.S)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one regex match, found {count}")
    return new


scene_path = Path("config/quickshell/awtarchy-lock/LockScene.qml")
scene = scene_path.read_text()
scene = replace_once(
    scene,
    '    required property var autoAccents\n    required property var layout\n',
    '    required property var autoAccents\n    required property var layout\n    required property var customImages\n',
    "scene custom image input",
)
scene = replace_once(
    scene,
    '''    function normalizedPoint(name) {\n        const value = root.layout && typeof root.layout === "object"\n            ? root.layout[name] : null;\n        return value && typeof value === "object" ? value : null;\n    }\n\n''',
    '''    function normalizedPoint(name) {\n        const value = root.layout && typeof root.layout === "object"\n            ? root.layout[name] : null;\n        return value && typeof value === "object" ? value : null;\n    }\n\n    function customImageForName(name) {\n        if (!Array.isArray(root.customImages))\n            return null;\n        const key = String(name || "");\n        for (let i = 0; i < root.customImages.length; ++i) {\n            const image = root.customImages[i];\n            if (image && typeof image === "object" && String(image.id || "") === key)\n                return image;\n        }\n        return null;\n    }\n\n    function presentationPoint(name) {\n        return normalizedPoint(name) || customImageForName(name);\n    }\n\n''',
    "scene generic point helper",
)
scene = replace_once(
    scene,
    '''    function normalizedX(name, fallback) {\n        const point = normalizedPoint(name);\n        const value = point ? Number(point.x) : Number.NaN;\n        return Number.isFinite(value) ? Math.max(0, Math.min(1, value)) : fallback;\n    }\n\n    function normalizedY(name, fallback) {\n        const point = normalizedPoint(name);\n        const value = point ? Number(point.y) : Number.NaN;\n        return Number.isFinite(value) ? Math.max(0, Math.min(1, value)) : fallback;\n    }\n\n''',
    '''    function normalizedX(name, fallback) {\n        const point = presentationPoint(name);\n        const value = point ? Number(point.x) : Number.NaN;\n        return Number.isFinite(value) ? Math.max(0, Math.min(1, value)) : fallback;\n    }\n\n    function normalizedY(name, fallback) {\n        const point = presentationPoint(name);\n        const value = point ? Number(point.y) : Number.NaN;\n        return Number.isFinite(value) ? Math.max(0, Math.min(1, value)) : fallback;\n    }\n\n''',
    "scene generic coordinates",
)
scene = regex_once(
    scene,
    r'''    function elementScale\(name\) \{.*?\n    \}\n\n(?=    function elementColor)''',
    '''    function elementScale(name) {\n        const point = presentationPoint(name);\n        const value = point ? Number(point.scale === undefined ? 1 : point.scale) : 1;\n        const baseScale = Number.isFinite(value) ? Math.max(0.50, Math.min(2.00, value)) : 1;\n        const holdScale = root.editorMode && name === editorHeldElement ? editorHoldScale : 1.0;\n        const safeHoldScale = Number.isFinite(Number(holdScale))\n            ? Math.max(1.0, Math.min(1.12, Number(holdScale))) : 1.0;\n        return baseScale * safeHoldScale;\n    }\n\n    function elementStretchX(name) {\n        const point = presentationPoint(name);\n        const value = point ? Number(point.stretch_x === undefined ? 1 : point.stretch_x) : 1;\n        return Number.isFinite(value) ? Math.max(0.25, Math.min(4.00, value)) : 1;\n    }\n\n    function elementStretchY(name) {\n        const point = presentationPoint(name);\n        const value = point ? Number(point.stretch_y === undefined ? 1 : point.stretch_y) : 1;\n        return Number.isFinite(value) ? Math.max(0.25, Math.min(4.00, value)) : 1;\n    }\n\n    function elementOpacity(name) {\n        const point = presentationPoint(name);\n        const value = point ? Number(point.opacity === undefined ? 100 : point.opacity) : 100;\n        const minimum = name === "password" ? 20 : 0;\n        const percent = Number.isFinite(value) ? Math.max(minimum, Math.min(100, value)) : 100;\n        return percent / 100;\n    }\n\n''',
    "scene generic transforms",
)
scene = regex_once(
    scene,
    r'''    function elementVisualWidth\(name\) \{.*?\n    \}\n\n    function elementVisualHeight\(name\) \{.*?\n    \}\n''',
    '''    function elementVisualWidth(name) {\n        if (customImageForName(name))\n            return 180 * root.uiScale * root.elementScale(name) * root.elementStretchX(name);\n        if (name === "logo") return root.wordmarkWidth * root.elementScale("logo") * root.elementStretchX("logo");\n        if (name === "time") return timeItem.implicitWidth * root.elementScale("time") * root.elementStretchX("time");\n        if (name === "date") return dateItem.implicitWidth * root.elementScale("date") * root.elementStretchX("date");\n        if (name === "username") return usernameItem.implicitWidth * root.elementScale("username") * root.elementStretchX("username");\n        if (name === "weather") return weatherItem.implicitWidth * root.elementScale("weather") * root.elementStretchX("weather");\n        if (name === "password") return root.passwordWidth * root.elementStretchX("password");\n        return 48 * root.uiScale;\n    }\n\n    function elementVisualHeight(name) {\n        if (customImageForName(name))\n            return 180 * root.uiScale * root.elementScale(name) * root.elementStretchY(name);\n        if (name === "logo") return root.wordmarkHeight * root.elementScale("logo") * root.elementStretchY("logo");\n        if (name === "time") return timeItem.implicitHeight * root.elementScale("time") * root.elementStretchY("time");\n        if (name === "date") return dateItem.implicitHeight * root.elementScale("date") * root.elementStretchY("date");\n        if (name === "username") return usernameItem.implicitHeight * root.elementScale("username") * root.elementStretchY("username");\n        if (name === "weather") return weatherItem.implicitHeight * root.elementScale("weather") * root.elementStretchY("weather");\n        if (name === "password") return root.passwordHeight * root.elementStretchY("password");\n        return 28 * root.uiScale;\n    }\n''',
    "scene visual bounds",
)
custom_repeater = '''        Repeater {\n            id: customImageRepeater\n            model: Array.isArray(root.customImages) ? root.customImages : []\n\n            Image {\n                required property var modelData\n                readonly property string elementName: String(modelData.id || "")\n\n                visible: modelData.visible !== false || root.editorMode\n                source: String(modelData.path || "").startsWith("/")\n                    ? "file://" + String(modelData.path) : ""\n                asynchronous: true\n                cache: true\n                fillMode: Image.PreserveAspectFit\n                width: Math.round(180 * root.uiScale)\n                height: Math.round(180 * root.uiScale)\n                x: root.normalizedX(elementName, 0.50) * parent.width - width / 2\n                y: root.normalizedY(elementName, 0.50) * parent.height - height / 2\n                scale: root.elementScale(elementName)\n                transformOrigin: Item.Center\n                transform: Scale {\n                    origin.x: width / 2\n                    origin.y: height / 2\n                    xScale: root.elementStretchX(elementName)\n                    yScale: root.elementStretchY(elementName)\n                }\n                opacity: root.elementOpacity(elementName)\n                    * (modelData.visible !== false ? 1.0 : root.editorMode ? 0.30 : 0.0)\n                z: 4\n            }\n        }\n\n'''
scene = replace_once(
    scene,
    '        Item {\n            id: wordmarkItem\n',
    custom_repeater + '        Item {\n            id: wordmarkItem\n',
    "scene custom image repeater",
)
scene = replace_once(
    scene,
    '''            visible: root.presentationVisible("logo", root.showLogo)\n            opacity: root.presentationOpacity("logo")\n            x: root.normalizedX("logo", 0.50) * parent.width - width / 2\n            y: root.normalizedY("logo", 0.34) * parent.height - height / 2\n            width: root.wordmarkWidth\n            height: root.wordmarkHeight\n            scale: root.elementScale("logo")\n            transformOrigin: Item.Center\n''',
    '''            visible: root.presentationVisible("logo", root.showLogo)\n            opacity: root.presentationOpacity("logo") * root.elementOpacity("logo")\n            x: root.normalizedX("logo", 0.50) * parent.width - width / 2\n            y: root.normalizedY("logo", 0.34) * parent.height - height / 2\n            width: root.wordmarkWidth\n            height: root.wordmarkHeight\n            scale: root.elementScale("logo")\n            transformOrigin: Item.Center\n            transform: Scale {\n                origin.x: wordmarkItem.width / 2\n                origin.y: wordmarkItem.height / 2\n                xScale: root.elementStretchX("logo")\n                yScale: root.elementStretchY("logo")\n            }\n            z: 10\n''',
    "logo stretch opacity",
)
for name, base_opacity in (("time", ""), ("date", "0.78 * "), ("username", "0.72 * "), ("weather", "0.76 * ")):
    item = name + "Item"
    visible_line = f'            visible: root.presentationVisible("{name}", root.show{name.capitalize()})'
    if name == "weather":
        visible_line += ' && root.weatherText.length > 0'
    old = f'''{visible_line}\n            opacity: {base_opacity}root.presentationOpacity("{name}")\n            scale: root.elementScale("{name}")\n            transformOrigin: Item.Center\n'''
    new = f'''{visible_line}\n            opacity: {base_opacity}root.presentationOpacity("{name}") * root.elementOpacity("{name}")\n            scale: root.elementScale("{name}")\n            transformOrigin: Item.Center\n            transform: Scale {{\n                origin.x: {item}.width / 2\n                origin.y: {item}.height / 2\n                xScale: root.elementStretchX("{name}")\n                yScale: root.elementStretchY("{name}")\n            }}\n            z: 10\n'''
    scene = replace_once(scene, old, new, f"{name} stretch opacity")
scene_path.write_text(scene)
Path("config/quickshell/awtarchy/LockPreviewScene.qml").write_text(scene)

surface_path = Path("config/quickshell/awtarchy-lock/LockSurface.qml")
surface = surface_path.read_text()
surface = replace_once(
    surface,
    '    required property var autoAccents\n    required property var layout\n',
    '    required property var autoAccents\n    required property var layout\n    required property var customImages\n',
    "surface custom image input",
)
surface = replace_once(
    surface,
    '        autoAccents: root.autoAccents\n        layout: root.layout\n        previewMode: false\n',
    '        autoAccents: root.autoAccents\n        layout: root.layout\n        customImages: root.customImages\n        previewMode: false\n',
    "surface scene custom images",
)
surface = replace_once(
    surface,
    '''        z: 20\n        opacity: root.unlocking ? 0 : root.entered ? 1 : 0\n\n        Behavior on opacity {\n''',
    '''        z: 20\n        opacity: (root.unlocking ? 0 : root.entered ? 1 : 0) * scene.elementOpacity("password")\n        transform: Scale {\n            origin.x: passwordBlock.width / 2\n            origin.y: passwordBlock.height / 2\n            xScale: scene.elementStretchX("password")\n            yScale: scene.elementStretchY("password")\n        }\n\n        Behavior on opacity {\n''',
    "password transform opacity",
)
surface_path.write_text(surface)

shell_path = Path("config/quickshell/awtarchy-lock/shell.qml")
shell = shell_path.read_text()
shell = replace_once(
    shell,
    '    property var lockLayout: defaultLockLayout()\n',
    '    property var lockLayout: defaultLockLayout()\n    property var lockCustomImages: []\n',
    "shell custom image property",
)
shell = regex_once(
    shell,
    r'''    function defaultLockLayout\(\) \{.*?\n    \}\n\n(?=    function normalizedAnimationPreference)''',
    '''    function defaultLockLayout() {\n        return ({\n            logo: ({ x: 0.50, y: 0.34, scale: 1.0, stretch_x: 1.0, stretch_y: 1.0, opacity: 100, color: "auto" }),\n            time: ({ x: 0.50, y: 0.51, scale: 1.0, stretch_x: 1.0, stretch_y: 1.0, opacity: 100, color: "auto" }),\n            date: ({ x: 0.50, y: 0.555, scale: 1.0, stretch_x: 1.0, stretch_y: 1.0, opacity: 100, color: "auto" }),\n            username: ({ x: 0.50, y: 0.595, scale: 1.0, stretch_x: 1.0, stretch_y: 1.0, opacity: 100, color: "auto" }),\n            weather: ({ x: 0.50, y: 0.635, scale: 1.0, stretch_x: 1.0, stretch_y: 1.0, opacity: 100, color: "auto" }),\n            password: ({ x: 0.50, y: 0.70, scale: 1.0, stretch_x: 1.0, stretch_y: 1.0, opacity: 100, color: "auto" })\n        });\n    }\n\n''',
    "shell default layout",
)
shell = regex_once(
    shell,
    r'''    function layoutPoint\(value, fallback, password\) \{.*?\n    \}\n(?=    function normalizedLayout)''',
    '''    function layoutPoint(value, fallback, password) {\n        const fallbackColor = String(fallback.color || "auto");\n        const fallbackOpacity = Number(fallback.opacity === undefined ? 100 : fallback.opacity);\n        if (!value || typeof value !== "object" || Array.isArray(value))\n            return ({ x: fallback.x, y: fallback.y, scale: fallback.scale, stretch_x: 1.0, stretch_y: 1.0, opacity: fallbackOpacity, color: fallbackColor });\n        const x = Number(value.x);\n        const y = Number(value.y);\n        const scale = Number(value.scale === undefined ? 1 : value.scale);\n        const stretchX = Number(value.stretch_x === undefined ? 1 : value.stretch_x);\n        const stretchY = Number(value.stretch_y === undefined ? 1 : value.stretch_y);\n        const opacity = Number(value.opacity === undefined ? 100 : value.opacity);\n        const rawColor = String(value.color === undefined ? "auto" : value.color);\n        const color = rawColor === "auto" || /^#[0-9a-fA-F]{6}$/.test(rawColor)\n            ? rawColor.toLowerCase() : fallbackColor;\n        const minX = password ? 0.15 : 0.05;\n        const maxX = password ? 0.85 : 0.95;\n        const minY = password ? 0.20 : 0.08;\n        const maxY = password ? 0.86 : 0.92;\n        const minOpacity = password ? 20 : 0;\n        if (!Number.isFinite(x) || !Number.isFinite(y) || !Number.isFinite(scale)\n                || !Number.isFinite(stretchX) || !Number.isFinite(stretchY)\n                || !Number.isFinite(opacity)\n                || x < minX || x > maxX || y < minY || y > maxY\n                || scale < 0.50 || scale > 2.00\n                || stretchX < 0.25 || stretchX > 4.00\n                || stretchY < 0.25 || stretchY > 4.00\n                || opacity < minOpacity || opacity > 100)\n            return ({ x: fallback.x, y: fallback.y, scale: fallback.scale, stretch_x: 1.0, stretch_y: 1.0, opacity: fallbackOpacity, color: fallbackColor });\n        return ({ x: x, y: y, scale: scale, stretch_x: stretchX, stretch_y: stretchY, opacity: opacity, color: color });\n    }\n''',
    "shell layout normalization",
)
shell = replace_once(
    shell,
    '''    function normalizedWeatherLocation(value) {\n''',
    '''    function normalizedCustomImages(value) {\n        if (!Array.isArray(value) || value.length > 12)\n            return [];\n        const result = [];\n        const ids = ({});\n        for (let i = 0; i < value.length; ++i) {\n            const image = value[i];\n            if (!image || typeof image !== "object" || Array.isArray(image))\n                return [];\n            const id = String(image.id || "");\n            const path = normalizedWallpaperPath(image.path);\n            const x = Number(image.x);\n            const y = Number(image.y);\n            const scale = Number(image.scale);\n            const stretchX = Number(image.stretch_x);\n            const stretchY = Number(image.stretch_y);\n            const opacity = Number(image.opacity);\n            if (!/^image-[A-Za-z0-9_-]{1,64}$/.test(id) || ids[id] || path.length === 0\n                    || !Number.isFinite(x) || x < 0.05 || x > 0.95\n                    || !Number.isFinite(y) || y < 0.08 || y > 0.92\n                    || !Number.isFinite(scale) || scale < 0.50 || scale > 2.00\n                    || !Number.isFinite(stretchX) || stretchX < 0.25 || stretchX > 4.00\n                    || !Number.isFinite(stretchY) || stretchY < 0.25 || stretchY > 4.00\n                    || !Number.isFinite(opacity) || opacity < 0 || opacity > 100\n                    || typeof image.visible !== "boolean")\n                return [];\n            ids[id] = true;\n            result.push(({\n                id: id, path: path, x: x, y: y, scale: scale,\n                stretch_x: stretchX, stretch_y: stretchY, opacity: opacity,\n                visible: image.visible\n            }));\n        }\n        return result;\n    }\n\n    function normalizedWeatherLocation(value) {\n''',
    "shell custom image normalization",
)
shell = replace_once(
    shell,
    '        lockLayout = defaultLockLayout();\n',
    '        lockLayout = defaultLockLayout();\n        lockCustomImages = [];\n',
    "shell custom image reset",
)
shell = replace_once(
    shell,
    '            lockLayout = normalizedLayout(parsed.lockscreen_layout);\n',
    '            lockLayout = normalizedLayout(parsed.lockscreen_layout);\n            lockCustomImages = normalizedCustomImages(parsed.lockscreen_custom_images);\n',
    "shell custom image load",
)
shell = replace_once(
    shell,
    '                autoAccents: lockContrastCache.colors\n                layout: root.lockLayout\n',
    '                autoAccents: lockContrastCache.colors\n                layout: root.lockLayout\n                customImages: root.lockCustomImages\n',
    "shell custom image surface pass",
)
shell_path.write_text(shell)

print("Pass 2 secure rendering patch applied")
