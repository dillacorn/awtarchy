from pathlib import Path


def one(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one match, got {count}")
    return text.replace(old, new, 1)


def all_matches(text, old, new, minimum, label):
    count = text.count(old)
    if count < minimum:
        raise RuntimeError(f"{label}: expected at least {minimum} matches, got {count}")
    return text.replace(old, new)


root = Path('.')

# Local timezone formatter. Values are never eval'd; zones must exist in zoneinfo.
tz = root / 'config/hypr/scripts/quickshell_lockscreen_timezones.sh'
tz.write_text(r'''#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ZONEINFO_ROOT="/usr/share/zoneinfo"

valid_zone() {
    local zone="${1:-}"
    [[ -n "$zone" && "$zone" != /* && "$zone" != *'..'* && -f "$ZONEINFO_ROOT/$zone" ]]
}

format_zone() {
    local zone="$1"
    local format="${2:-24h}"
    valid_zone "$zone" || return 2
    case "$format" in
        12h) TZ="$zone" date '+%-I:%M %p' ;;
        24h) TZ="$zone" date '+%H:%M' ;;
        *) return 2 ;;
    esac
}

if [[ "${1:-}" == "--batch" ]]; then
    shift
    (( $# % 3 == 0 )) || { printf '%s\n' 'invalid timezone batch' >&2; return 2 2>/dev/null || false; }
    first=true
    printf '{'
    while (( $# >= 3 )); do
        id="$1"; zone="$2"; format="$3"; shift 3
        [[ "$id" =~ ^timezone-[A-Za-z0-9_-]{1,64}$ ]] || { printf '%s\n' 'invalid timezone id' >&2; return 2 2>/dev/null || false; }
        value="$(format_zone "$zone" "$format")" || { printf '%s\n' "invalid timezone: $zone" >&2; return 2 2>/dev/null || false; }
        if $first; then first=false; else printf ','; fi
        printf '"%s":"%s"' "$id" "$value"
    done
    printf '}\n'
else
    zone="${1:-UTC}"
    format="${2:-24h}"
    format_zone "$zone" "$format"
fi
''')
tz.chmod(0o755)

# Desktop state reader.
p = root / 'config/quickshell/awtarchy/BarState.qml'
s = p.read_text()
anchor = '''    function updateNotificationsEnabled() {'''
insert = r'''    function lockscreenTimezoneClocks() {
        const value = data().lockscreen_timezone_clocks;
        if (!Array.isArray(value) || value.length > 12) return [];
        const result = []; const ids = ({});
        for (const raw of value) {
            if (!raw || typeof raw !== "object" || Array.isArray(raw)) return [];
            const id = String(raw.id || ""); const timezone = String(raw.timezone || "UTC");
            const format = String(raw.format || "24h") === "12h" ? "12h" : "24h";
            const x = Number(raw.x), y = Number(raw.y), scale = Number(raw.scale);
            const sx = Number(raw.stretch_x), sy = Number(raw.stretch_y), opacity = Number(raw.opacity), rotation = Number(raw.rotation);
            const color = String(raw.color || "auto").toLowerCase();
            if (!/^timezone-[A-Za-z0-9_-]{1,64}$/.test(id) || ids[id]
                    || timezone.startsWith("/") || timezone.indexOf("..") >= 0 || /[\u0000-\u001f\u007f-\u009f]/.test(timezone)
                    || !Number.isFinite(x) || x < 0.05 || x > 0.95 || !Number.isFinite(y) || y < 0.08 || y > 0.92
                    || !Number.isFinite(scale) || scale < 0.5 || scale > 100 || !Number.isFinite(sx) || sx < 0.25 || sx > 4
                    || !Number.isFinite(sy) || sy < 0.25 || sy > 4 || !Number.isFinite(opacity) || opacity < 0 || opacity > 100
                    || !Number.isFinite(rotation) || rotation < -180 || rotation > 180
                    || (color !== "auto" && !/^#[0-9a-f]{6}$/.test(color)) || typeof raw.visible !== "boolean") return [];
            ids[id] = true;
            result.push(({ id: id, timezone: timezone, format: format, x: x, y: y, scale: scale,
                stretch_x: sx, stretch_y: sy, opacity: opacity, rotation: rotation, color: color, visible: raw.visible }));
        }
        return result;
    }

    function lockscreenCustomTexts() {
        const value = data().lockscreen_custom_texts;
        if (!Array.isArray(value) || value.length > 12) return [];
        const result = []; const ids = ({});
        for (const raw of value) {
            if (!raw || typeof raw !== "object" || Array.isArray(raw)) return [];
            const id = String(raw.id || ""); const text = String(raw.text === undefined ? "Custom Text" : raw.text);
            const variants = Array.isArray(raw.variants) ? raw.variants.map(value => String(value)) : [];
            const alignment = ["left", "center", "right"].indexOf(String(raw.alignment)) >= 0 ? String(raw.alignment) : "center";
            const x = Number(raw.x), y = Number(raw.y), scale = Number(raw.scale);
            const sx = Number(raw.stretch_x), sy = Number(raw.stretch_y), opacity = Number(raw.opacity), rotation = Number(raw.rotation);
            const color = String(raw.color || "auto").toLowerCase();
            if (!/^text-[A-Za-z0-9_-]{1,64}$/.test(id) || ids[id] || text.length > 4096 || variants.length > 32
                    || variants.some(value => value.length > 4096)
                    || !Number.isFinite(x) || x < 0.05 || x > 0.95 || !Number.isFinite(y) || y < 0.08 || y > 0.92
                    || !Number.isFinite(scale) || scale < 0.5 || scale > 100 || !Number.isFinite(sx) || sx < 0.25 || sx > 4
                    || !Number.isFinite(sy) || sy < 0.25 || sy > 4 || !Number.isFinite(opacity) || opacity < 0 || opacity > 100
                    || !Number.isFinite(rotation) || rotation < -180 || rotation > 180
                    || (color !== "auto" && !/^#[0-9a-f]{6}$/.test(color)) || typeof raw.visible !== "boolean") return [];
            ids[id] = true;
            result.push(({ id: id, text: text, variants: variants, randomize: raw.randomize === true,
                alignment: alignment, x: x, y: y, scale: scale, stretch_x: sx, stretch_y: sy,
                opacity: opacity, rotation: rotation, color: color, visible: raw.visible }));
        }
        return result;
    }

''' + anchor
s = one(s, anchor, insert, 'BarState dynamic getters')
p.write_text(s)

# Secure shell normalization + timezone formatting.
p = root / 'config/quickshell/awtarchy-lock/shell.qml'
s = p.read_text()
s = one(s,
'''    readonly property string captureHelper: configHome
        + "/hypr/scripts/quickshell_lockscreen_capture.sh"''',
'''    readonly property string captureHelper: configHome
        + "/hypr/scripts/quickshell_lockscreen_capture.sh"
    readonly property string timezoneHelper: configHome
        + "/hypr/scripts/quickshell_lockscreen_timezones.sh"''',
'secure timezone helper path')
s = one(s,
'''    property var lockCustomImages: []
    property var lockVisualizer: defaultLockVisualizer()''',
'''    property var lockCustomImages: []
    property var lockTimezoneClocks: []
    property var lockTimezoneValues: ({})
    property var lockCustomTexts: []
    property var lockVisualizer: defaultLockVisualizer()''',
'secure dynamic state properties')
anchor = '''    function normalizedWeatherLocation(value) {'''
insert = r'''    function normalizedTimezoneClocks(value) {
        if (!Array.isArray(value) || value.length > 12) return [];
        const result = []; const ids = ({});
        for (const raw of value) {
            if (!raw || typeof raw !== "object" || Array.isArray(raw)) return [];
            const id = String(raw.id || ""), timezone = String(raw.timezone || "UTC");
            const format = String(raw.format || "24h") === "12h" ? "12h" : "24h";
            const x = Number(raw.x), y = Number(raw.y), scale = Number(raw.scale), sx = Number(raw.stretch_x), sy = Number(raw.stretch_y);
            const opacity = Number(raw.opacity), rotation = Number(raw.rotation), color = String(raw.color || "auto").toLowerCase();
            if (!/^timezone-[A-Za-z0-9_-]{1,64}$/.test(id) || ids[id] || timezone.startsWith("/") || timezone.indexOf("..") >= 0
                    || /[\u0000-\u001f\u007f-\u009f]/.test(timezone) || !Number.isFinite(x) || x < 0.05 || x > 0.95
                    || !Number.isFinite(y) || y < 0.08 || y > 0.92 || !Number.isFinite(scale) || scale < 0.5 || scale > 100
                    || !Number.isFinite(sx) || sx < 0.25 || sx > 4 || !Number.isFinite(sy) || sy < 0.25 || sy > 4
                    || !Number.isFinite(opacity) || opacity < 0 || opacity > 100 || !Number.isFinite(rotation) || rotation < -180 || rotation > 180
                    || (color !== "auto" && !/^#[0-9a-f]{6}$/.test(color)) || typeof raw.visible !== "boolean") return [];
            ids[id] = true;
            result.push(({ id:id, timezone:timezone, format:format, x:x, y:y, scale:scale, stretch_x:sx, stretch_y:sy,
                opacity:opacity, rotation:rotation, color:color, visible:raw.visible }));
        }
        return result;
    }

    function normalizedCustomTexts(value) {
        if (!Array.isArray(value) || value.length > 12) return [];
        const result = []; const ids = ({});
        for (const raw of value) {
            if (!raw || typeof raw !== "object" || Array.isArray(raw)) return [];
            const id = String(raw.id || ""), text = String(raw.text === undefined ? "Custom Text" : raw.text);
            const variants = Array.isArray(raw.variants) ? raw.variants.map(value => String(value)) : [];
            const alignment = ["left","center","right"].indexOf(String(raw.alignment)) >= 0 ? String(raw.alignment) : "center";
            const x = Number(raw.x), y = Number(raw.y), scale = Number(raw.scale), sx = Number(raw.stretch_x), sy = Number(raw.stretch_y);
            const opacity = Number(raw.opacity), rotation = Number(raw.rotation), color = String(raw.color || "auto").toLowerCase();
            if (!/^text-[A-Za-z0-9_-]{1,64}$/.test(id) || ids[id] || text.length > 4096 || variants.length > 32
                    || variants.some(value => value.length > 4096) || !Number.isFinite(x) || x < 0.05 || x > 0.95
                    || !Number.isFinite(y) || y < 0.08 || y > 0.92 || !Number.isFinite(scale) || scale < 0.5 || scale > 100
                    || !Number.isFinite(sx) || sx < 0.25 || sx > 4 || !Number.isFinite(sy) || sy < 0.25 || sy > 4
                    || !Number.isFinite(opacity) || opacity < 0 || opacity > 100 || !Number.isFinite(rotation) || rotation < -180 || rotation > 180
                    || (color !== "auto" && !/^#[0-9a-f]{6}$/.test(color)) || typeof raw.visible !== "boolean") return [];
            ids[id] = true;
            result.push(({ id:id, text:text, variants:variants, randomize:raw.randomize === true, alignment:alignment,
                x:x, y:y, scale:scale, stretch_x:sx, stretch_y:sy, opacity:opacity, rotation:rotation, color:color, visible:raw.visible }));
        }
        return result;
    }

    function timezoneHelperArgs() {
        const args = ["bash", root.timezoneHelper, "--batch"];
        for (const clock of root.lockTimezoneClocks)
            args.push(String(clock.id), String(clock.timezone), String(clock.format));
        return args;
    }

    function refreshTimezoneValues() {
        if (root.lockTimezoneClocks.length === 0) { root.lockTimezoneValues = ({}); return; }
        if (!timezoneProcess.running) timezoneProcess.exec(root.timezoneHelperArgs());
    }

    function applyTimezoneValues(line) {
        try { const value = JSON.parse(String(line || "")); if (value && typeof value === "object" && !Array.isArray(value)) root.lockTimezoneValues = value; }
        catch (error) { }
    }

''' + anchor
s = one(s, anchor, insert, 'secure dynamic normalization')
s = one(s,
'''        lockCustomImages = [];
        lockVisualizer = defaultLockVisualizer();''',
'''        lockCustomImages = [];
        lockTimezoneClocks = [];
        lockTimezoneValues = ({});
        lockCustomTexts = [];
        lockVisualizer = defaultLockVisualizer();''',
'secure reset dynamic state')
s = one(s,
'''            lockCustomImages = normalizedCustomImages(parsed.lockscreen_custom_images);
            lockVisualizer = normalizedVisualizer(parsed.lockscreen_visualizer);''',
'''            lockCustomImages = normalizedCustomImages(parsed.lockscreen_custom_images);
            lockTimezoneClocks = normalizedTimezoneClocks(parsed.lockscreen_timezone_clocks);
            lockCustomTexts = normalizedCustomTexts(parsed.lockscreen_custom_texts);
            lockVisualizer = normalizedVisualizer(parsed.lockscreen_visualizer);''',
'secure load dynamic state')
s = one(s,
'''        root.loadPreferences();
    }

    FileView {''',
'''        root.loadPreferences();
        Qt.callLater(root.refreshTimezoneValues);
    }

    Process {
        id: timezoneProcess
        stdout: SplitParser { onRead: line => root.applyTimezoneValues(line) }
    }
    Timer { interval: 15000; repeat: true; running: root.lockTimezoneClocks.length > 0; triggeredOnStart: true; onTriggered: root.refreshTimezoneValues() }

    FileView {''',
'secure timezone process')
s = one(s,
'''                customImages: root.lockCustomImages
                visualizer: root.lockVisualizer''',
'''                customImages: root.lockCustomImages
                timezoneClocks: root.lockTimezoneClocks
                timezoneValues: root.lockTimezoneValues
                customTexts: root.lockCustomTexts
                visualizer: root.lockVisualizer''',
'secure surface dynamic bindings')
p.write_text(s)

# Secure surface plumbing.
p = root / 'config/quickshell/awtarchy-lock/LockSurface.qml'
s = p.read_text()
s = one(s,
'''    required property var customImages
    required property var visualizer''',
'''    required property var customImages
    required property var timezoneClocks
    required property var timezoneValues
    required property var customTexts
    required property var visualizer''',
'surface dynamic properties')
s = one(s,
'''            customImages: root.customImages
            visualizer: root.visualizer''',
'''            customImages: root.customImages
            timezoneClocks: root.timezoneClocks
            timezoneValues: root.timezoneValues
            customTexts: root.customTexts
            visualizer: root.visualizer''',
'surface scene dynamic bindings')
p.write_text(s)

# Shared scene dynamic presentation.
p = root / 'config/quickshell/awtarchy-lock/LockScene.qml'
s = p.read_text()
s = one(s,
'''    required property var customImages
    required property var visualizer''',
'''    required property var customImages
    required property var timezoneClocks
    required property var timezoneValues
    required property var customTexts
    required property var visualizer''',
'scene dynamic required properties')
s = one(s,
'''    property int customImageSpawnEpoch: 0
    property string individualImageReplayId: ""''',
'''    property int customImageSpawnEpoch: 0
    property int textReplayEpoch: 0
    property var customTextSelections: ({})
    property string individualImageReplayId: ""''',
'scene text epoch state')
old = '''    function presentationPoint(name) {
        if (name === "visualizer" && root.visualizer
                && typeof root.visualizer === "object" && !Array.isArray(root.visualizer))
            return root.visualizer;
        return normalizedPoint(name) || customImageForName(name);
    }'''
new = r'''    function timezoneClockForName(name) {
        if (!String(name || "").startsWith("timezone:") || !Array.isArray(root.timezoneClocks)) return null;
        const id = String(name).slice(9);
        for (const clock of root.timezoneClocks) if (clock && String(clock.id || "") === id) return clock;
        return null;
    }

    function customTextForName(name) {
        if (!String(name || "").startsWith("text:") || !Array.isArray(root.customTexts)) return null;
        const id = String(name).slice(5);
        for (const item of root.customTexts) if (item && String(item.id || "") === id) return item;
        return null;
    }

    function presentationPoint(name) {
        if (name === "visualizer" && root.visualizer
                && typeof root.visualizer === "object" && !Array.isArray(root.visualizer))
            return root.visualizer;
        return normalizedPoint(name) || customImageForName(name) || timezoneClockForName(name) || customTextForName(name);
    }

    function timezoneLabel(zone) {
        const parts = String(zone || "UTC").split("/");
        return String(parts[parts.length - 1] || "UTC").replace(/_/g, " ");
    }

    function timezoneDisplay(clock) {
        if (!clock) return "--:--";
        const value = String(root.timezoneValues && root.timezoneValues[clock.id] !== undefined ? root.timezoneValues[clock.id] : "--:--");
        return value + "\n" + timezoneLabel(clock.timezone);
    }

    function refreshCustomTextSelections() {
        const next = ({});
        if (Array.isArray(root.customTexts)) {
            for (const item of root.customTexts) {
                if (!item) continue;
                const variants = Array.isArray(item.variants) ? item.variants.map(value => String(value)) : [];
                if (item.randomize === true && variants.length > 0)
                    next[String(item.id)] = variants[Math.floor(Math.random() * variants.length)];
                else next[String(item.id)] = String(item.text === undefined ? "Custom Text" : item.text);
            }
        }
        root.customTextSelections = next;
    }

    function customTextDisplay(item) {
        if (!item) return "";
        const id = String(item.id || "");
        return String(root.customTextSelections[id] !== undefined ? root.customTextSelections[id] : item.text || "Custom Text");
    }

    onCustomTextsChanged: refreshCustomTextSelections()
    onPresentationReplayTokenChanged: {
        if (root.previewMode && root.presentationReplayToken > 0) {
            root.textReplayEpoch++;
            root.refreshCustomTextSelections();
        }
    }'''
s = one(s, old, new, 'scene presentation point dynamic dispatch')
s = one(s,
'''        if (customImageForName(name))
            return 180 * root.uiScale * root.elementScale(name) * root.elementStretchX(name);
        if (name === "logo")''',
'''        if (customImageForName(name))
            return 180 * root.uiScale * root.elementScale(name) * root.elementStretchX(name);
        if (timezoneClockForName(name))
            return 220 * root.uiScale * root.elementScale(name) * root.elementStretchX(name);
        if (customTextForName(name))
            return Math.min(root.width * 0.70, 640 * root.uiScale) * root.elementScale(name) * root.elementStretchX(name);
        if (name === "logo")''',
'scene dynamic visual width')
s = one(s,
'''        if (customImageForName(name))
            return 180 * root.uiScale * root.elementScale(name) * root.elementStretchY(name);
        if (name === "logo")''',
'''        if (customImageForName(name))
            return 180 * root.uiScale * root.elementScale(name) * root.elementStretchY(name);
        if (timezoneClockForName(name))
            return 66 * root.uiScale * root.elementScale(name) * root.elementStretchY(name);
        if (customTextForName(name))
            return 72 * root.uiScale * root.elementScale(name) * root.elementStretchY(name);
        if (name === "logo")''',
'scene dynamic visual height')
render_anchor = '''        Item {
            visible: root.previewMode
            rotation: root.elementRotation("password")'''
render_insert = r'''        Repeater {
            model: Array.isArray(root.timezoneClocks) ? root.timezoneClocks : []
            Text {
                required property var modelData
                readonly property string elementName: "timezone:" + String(modelData.id || "")
                visible: root.presentationVisible(elementName, modelData.visible !== false)
                opacity: root.presentationOpacity(elementName) * root.elementOpacity(elementName)
                scale: root.elementScale(elementName)
                rotation: root.elementRotation(elementName)
                transformOrigin: Item.Center
                transform: Scale { origin.x: parent.width / 2; origin.y: parent.height / 2; xScale: root.elementStretchX(parent.elementName); yScale: root.elementStretchY(parent.elementName) }
                z: 10
                width: 220 * root.uiScale
                x: root.normalizedX(elementName, 0.50) * root.width - width / 2
                y: root.normalizedY(elementName, 0.60) * root.height - height / 2
                text: root.timezoneDisplay(modelData)
                horizontalAlignment: Text.AlignHCenter
                color: root.elementColor(elementName)
                font.family: root.theme.fontFamily
                font.pixelSize: Math.round(24 * root.uiScale)
                lineHeight: 0.86
            }
        }

        Repeater {
            model: Array.isArray(root.customTexts) ? root.customTexts : []
            Text {
                required property var modelData
                readonly property string elementName: "text:" + String(modelData.id || "")
                visible: root.presentationVisible(elementName, modelData.visible !== false)
                opacity: root.presentationOpacity(elementName) * root.elementOpacity(elementName)
                scale: root.elementScale(elementName)
                rotation: root.elementRotation(elementName)
                transformOrigin: Item.Center
                transform: Scale { origin.x: parent.width / 2; origin.y: parent.height / 2; xScale: root.elementStretchX(parent.elementName); yScale: root.elementStretchY(parent.elementName) }
                z: 10
                width: Math.min(root.width * 0.70, 640 * root.uiScale)
                x: root.normalizedX(elementName, 0.50) * root.width - width / 2
                y: root.normalizedY(elementName, 0.55) * root.height - height / 2
                text: root.customTextDisplay(modelData)
                wrapMode: Text.Wrap
                horizontalAlignment: modelData.alignment === "left" ? Text.AlignLeft : modelData.alignment === "right" ? Text.AlignRight : Text.AlignHCenter
                color: root.elementColor(elementName)
                font.family: root.theme.fontFamily
                font.pixelSize: Math.round(22 * root.uiScale)
            }
        }

''' + render_anchor
s = one(s, render_anchor, render_insert, 'scene dynamic renderers')
s = one(s,
'''        root.updateClockText();
        root.entered = true;''',
'''        root.updateClockText();
        root.refreshCustomTextSelections();
        root.entered = true;''',
'scene initialize text choice')
p.write_text(s)
(root / 'config/quickshell/awtarchy/LockPreviewScene.qml').write_text(s)

# Editor repeated objects, transforms, save/load, formatting, and controls.
p = root / 'config/quickshell/awtarchy/LockscreenEditor.qml'
s = p.read_text()
s = one(s,
'''    readonly property string previewCaptureBackend: configHome + "/hypr/scripts/quickshell_lockscreen_preview_capture.sh"''',
'''    readonly property string previewCaptureBackend: configHome + "/hypr/scripts/quickshell_lockscreen_preview_capture.sh"
    readonly property string timezoneBackend: configHome + "/hypr/scripts/quickshell_lockscreen_timezones.sh"''',
'editor timezone backend')
s = one(s,
'''    readonly property int customImageMaximum: 12
    readonly property real elementScaleMaximum: 100.0''',
'''    readonly property int customImageMaximum: 12
    readonly property int timezoneClockMaximum: 12
    readonly property int customTextMaximum: 12
    readonly property var timezonePresets: [
        { key: "UTC", label: "UTC" },
        { key: "America/New_York", label: "New York" },
        { key: "America/Los_Angeles", label: "Los Angeles" },
        { key: "Europe/London", label: "London" },
        { key: "Asia/Tokyo", label: "Tokyo" },
        { key: "Australia/Sydney", label: "Sydney" }
    ]
    readonly property real elementScaleMaximum: 100.0''',
'editor timezone presets')
s = one(s,
'''    property var draftCustomTexts: []
    property var draftVisualizer: defaultVisualizer()''',
'''    property var draftCustomTexts: []
    property var previewTimezoneValues: ({})
    property var draftVisualizer: defaultVisualizer()''',
'editor timezone values state')
s = one(s,
'''            customImages: cloneCustomImages(draftCustomImages),
            visualizer: cloneSnapshot(draftVisualizer),''',
'''            customImages: cloneCustomImages(draftCustomImages),
            timezoneClocks: cloneTimezoneClocks(draftTimezoneClocks),
            customTexts: cloneCustomTexts(draftCustomTexts),
            visualizer: cloneSnapshot(draftVisualizer),''',
'editor snapshot dynamic arrays')
s = one(s,
'''        draftCustomImages = cloneCustomImages(snapshot.customImages);
        draftVisualizer = cloneVisualizer(snapshot.visualizer);''',
'''        draftCustomImages = cloneCustomImages(snapshot.customImages);
        draftTimezoneClocks = cloneTimezoneClocks(snapshot.timezoneClocks);
        draftCustomTexts = cloneCustomTexts(snapshot.customTexts);
        draftVisualizer = cloneVisualizer(snapshot.visualizer);
        refreshPreviewTimezoneValues();''',
'editor restore dynamic arrays')
# Replace dynamic element dispatch block.
old = '''    function customImageIndex(name) { const key = String(name || ""); for (let i = 0; i < draftCustomImages.length; ++i) if (String(draftCustomImages[i].id || "") === key) return i; return -1; }
    function isCustomImage(name) { return customImageIndex(name) >= 0; }
    function editableElementNames() { const names = elementNames.slice(); names.push("visualizer"); for (const image of draftCustomImages) names.push(String(image.id)); return names; }
    function elementExists(name) { return name === "visualizer" || elementNames.indexOf(name) >= 0 || isCustomImage(name); }
    function elementPoint(name) { if (name === "visualizer") return draftVisualizer; if (isCustomImage(name)) return draftCustomImages[customImageIndex(name)]; return draftLayout[name] || defaultLayout()[name] || null; }'''
new = r'''    function cloneTimezoneClocks(value) {
        if (!Array.isArray(value)) return [];
        const result = []; const ids = ({});
        for (let i = 0; i < value.length && result.length < timezoneClockMaximum; ++i) {
            const raw = value[i]; if (!raw || typeof raw !== "object" || Array.isArray(raw)) continue;
            const id = String(raw.id || ""); const timezone = String(raw.timezone || "UTC"); if (!/^timezone-[A-Za-z0-9_-]{1,64}$/.test(id) || ids[id]) continue;
            const x=Number(raw.x),y=Number(raw.y),scale=Number(raw.scale),sx=Number(raw.stretch_x),sy=Number(raw.stretch_y),opacity=Number(raw.opacity),rotation=Number(raw.rotation);
            const color=String(raw.color||"auto").toLowerCase(); ids[id]=true;
            result.push(({id:id, timezone:timezone, format:normalizedClockFormat(raw.format), x:Math.max(0.05,Math.min(0.95,Number.isFinite(x)?x:0.5)),
                y:Math.max(0.08,Math.min(0.92,Number.isFinite(y)?y:0.6)), scale:Math.max(0.5,Math.min(elementScaleMaximum,Number.isFinite(scale)?scale:1)),
                stretch_x:Math.max(0.25,Math.min(4,Number.isFinite(sx)?sx:1)), stretch_y:Math.max(0.25,Math.min(4,Number.isFinite(sy)?sy:1)),
                opacity:Math.max(0,Math.min(100,Number.isFinite(opacity)?opacity:100)), rotation:normalizedRotation(Number.isFinite(rotation)?rotation:0),
                color:color==="auto"||validHex(color)?color:"auto", visible:typeof raw.visible==="boolean"?raw.visible:true}));
        }
        return result;
    }

    function cloneCustomTexts(value) {
        if (!Array.isArray(value)) return [];
        const result=[]; const ids=({});
        for (let i=0;i<value.length&&result.length<customTextMaximum;++i) {
            const raw=value[i]; if(!raw||typeof raw!=="object"||Array.isArray(raw)) continue;
            const id=String(raw.id||""); if(!/^text-[A-Za-z0-9_-]{1,64}$/.test(id)||ids[id]) continue;
            const x=Number(raw.x),y=Number(raw.y),scale=Number(raw.scale),sx=Number(raw.stretch_x),sy=Number(raw.stretch_y),opacity=Number(raw.opacity),rotation=Number(raw.rotation);
            const color=String(raw.color||"auto").toLowerCase(); const variants=Array.isArray(raw.variants)?raw.variants.slice(0,32).map(v=>String(v).slice(0,4096)):[]; ids[id]=true;
            result.push(({id:id,text:String(raw.text===undefined?"Custom Text":raw.text).slice(0,4096),variants:variants,randomize:raw.randomize===true,
                alignment:["left","center","right"].indexOf(String(raw.alignment))>=0?String(raw.alignment):"center",
                x:Math.max(0.05,Math.min(0.95,Number.isFinite(x)?x:0.5)),y:Math.max(0.08,Math.min(0.92,Number.isFinite(y)?y:0.55)),
                scale:Math.max(0.5,Math.min(elementScaleMaximum,Number.isFinite(scale)?scale:1)),stretch_x:Math.max(0.25,Math.min(4,Number.isFinite(sx)?sx:1)),
                stretch_y:Math.max(0.25,Math.min(4,Number.isFinite(sy)?sy:1)),opacity:Math.max(0,Math.min(100,Number.isFinite(opacity)?opacity:100)),
                rotation:normalizedRotation(Number.isFinite(rotation)?rotation:0),color:color==="auto"||validHex(color)?color:"auto",visible:typeof raw.visible==="boolean"?raw.visible:true}));
        }
        return result;
    }

    function customImageIndex(name) { const key = String(name || ""); for (let i = 0; i < draftCustomImages.length; ++i) if (String(draftCustomImages[i].id || "") === key) return i; return -1; }
    function isCustomImage(name) { return customImageIndex(name) >= 0; }
    function timezoneClockIndex(name) { return dynamicRotationIndex(String(name||""), "timezone:", draftTimezoneClocks); }
    function customTextIndex(name) { return dynamicRotationIndex(String(name||""), "text:", draftCustomTexts); }
    function isTimezoneClock(name) { return timezoneClockIndex(name) >= 0; }
    function isCustomText(name) { return customTextIndex(name) >= 0; }
    function editableElementNames() { const names = elementNames.slice(); names.push("visualizer"); for (const image of draftCustomImages) names.push(String(image.id)); for(const clock of draftTimezoneClocks) names.push("timezone:"+String(clock.id)); for(const item of draftCustomTexts) names.push("text:"+String(item.id)); return names; }
    function elementExists(name) { return name === "visualizer" || elementNames.indexOf(name) >= 0 || isCustomImage(name) || isTimezoneClock(name) || isCustomText(name); }
    function elementPoint(name) { if (name === "visualizer") return draftVisualizer; if (isCustomImage(name)) return draftCustomImages[customImageIndex(name)]; if(isTimezoneClock(name)) return draftTimezoneClocks[timezoneClockIndex(name)]; if(isCustomText(name)) return draftCustomTexts[customTextIndex(name)]; return draftLayout[name] || defaultLayout()[name] || null; }

    function nextDynamicId(prefix, values) { const stem=prefix+Date.now().toString(36); let n=0,candidate=stem; while(values.some(item=>String(item.id||"")===candidate)){n++;candidate=stem+"_"+n;} return candidate; }
    function addTimezoneClock() { if(draftTimezoneClocks.length>=timezoneClockMaximum){statusMessage="Timezone clock limit reached";return;} recordUndoBeforeChange(); const next=cloneTimezoneClocks(draftTimezoneClocks); const id=nextDynamicId("timezone-",next); next.push(({id:id,timezone:"UTC",format:"24h",x:0.5,y:0.60,scale:1,stretch_x:1,stretch_y:1,opacity:100,rotation:0,color:"auto",visible:true})); draftTimezoneClocks=next; selectedElement="timezone:"+id; selectedElements=[selectedElement]; activeDrawer="element"; refreshPreviewTimezoneValues(); statusMessage="Timezone clock added. Save to apply."; }
    function removeTimezoneClock(name) { const i=timezoneClockIndex(name); if(i<0)return; recordUndoBeforeChange(); const next=cloneTimezoneClocks(draftTimezoneClocks); next.splice(i,1); draftTimezoneClocks=next; selectedElement="logo";selectedElements=["logo"];refreshPreviewTimezoneValues();statusMessage="Timezone clock removed."; }
    function addCustomText() { if(draftCustomTexts.length>=customTextMaximum){statusMessage="Custom text limit reached";return;} recordUndoBeforeChange();const next=cloneCustomTexts(draftCustomTexts);const id=nextDynamicId("text-",next);next.push(({id:id,text:"Custom Text",variants:[],randomize:false,alignment:"center",x:0.5,y:0.55,scale:1,stretch_x:1,stretch_y:1,opacity:100,rotation:0,color:"auto",visible:true}));draftCustomTexts=next;selectedElement="text:"+id;selectedElements=[selectedElement];activeDrawer="element";statusMessage="Custom text added. Save to apply."; }
    function removeCustomText(name) { const i=customTextIndex(name);if(i<0)return;recordUndoBeforeChange();const next=cloneCustomTexts(draftCustomTexts);next.splice(i,1);draftCustomTexts=next;selectedElement="logo";selectedElements=["logo"];statusMessage="Custom text removed."; }
    function timezonePresetIndex(zone) { for(let i=0;i<timezonePresets.length;++i)if(timezonePresets[i].key===String(zone))return i;return 0; }
    function setTimezoneClockZone(name, zone) { const i=timezoneClockIndex(name);if(i<0||timezonePresets.every(item=>item.key!==String(zone)))return;recordUndoBeforeChange();const next=cloneTimezoneClocks(draftTimezoneClocks);next[i].timezone=String(zone);draftTimezoneClocks=next;refreshPreviewTimezoneValues(); }
    function setTimezoneClockFormat(name, format) { const i=timezoneClockIndex(name);if(i<0)return;recordUndoBeforeChange();const next=cloneTimezoneClocks(draftTimezoneClocks);next[i].format=normalizedClockFormat(format);draftTimezoneClocks=next;refreshPreviewTimezoneValues(); }
    function setCustomTextContent(name, value) { const i=customTextIndex(name);if(i<0)return;recordUndoBeforeChange();const next=cloneCustomTexts(draftCustomTexts);next[i].text=String(value).slice(0,4096);draftCustomTexts=next; }
    function setCustomTextChoices(name, value) { const i=customTextIndex(name);if(i<0)return;const lines=String(value).split("\n").filter(line=>line.length>0).slice(0,32);recordUndoBeforeChange();const next=cloneCustomTexts(draftCustomTexts);next[i].variants=lines;draftCustomTexts=next; }
    function setCustomTextRandomize(name, value) { const i=customTextIndex(name);if(i<0)return;recordUndoBeforeChange();const next=cloneCustomTexts(draftCustomTexts);next[i].randomize=!!value;draftCustomTexts=next; }
    function setCustomTextAlignment(name, value) { const i=customTextIndex(name);if(i<0||["left","center","right"].indexOf(String(value))<0)return;recordUndoBeforeChange();const next=cloneCustomTexts(draftCustomTexts);next[i].alignment=String(value);draftCustomTexts=next; }
    function timezoneHelperArgs() { const args=["bash",timezoneBackend,"--batch"];for(const clock of draftTimezoneClocks)args.push(String(clock.id),String(clock.timezone),String(clock.format));return args; }
    function refreshPreviewTimezoneValues() { if(draftTimezoneClocks.length===0){previewTimezoneValues=({});return;}if(!timezonePreviewProcess.running)timezonePreviewProcess.exec(timezoneHelperArgs()); }
    function applyPreviewTimezoneValues(line) { try{const value=JSON.parse(String(line||""));if(value&&typeof value==="object"&&!Array.isArray(value))previewTimezoneValues=value;}catch(error){} }
'''
s = one(s, old, new, 'editor dynamic model')
# Transform dispatch extensions.
s = one(s,
'''        } else if (isCustomImage(name)) {
            const next = cloneCustomImages(draftCustomImages);
            const index = customImageIndex(name);
            if (index < 0) return;
            next[index].scale = value;
            draftCustomImages = next;
        } else {''',
'''        } else if (isCustomImage(name)) {
            const next = cloneCustomImages(draftCustomImages); const index = customImageIndex(name); if (index < 0) return; next[index].scale = value; draftCustomImages = next;
        } else if (isTimezoneClock(name)) {
            const next=cloneTimezoneClocks(draftTimezoneClocks);next[timezoneClockIndex(name)].scale=value;draftTimezoneClocks=next;
        } else if (isCustomText(name)) {
            const next=cloneCustomTexts(draftCustomTexts);next[customTextIndex(name)].scale=value;draftCustomTexts=next;
        } else {''',
'editor scale dynamic dispatch')
s = one(s,
'''            else if (isCustomImage(item.name)) { const i=ni.findIndex(image=>image.id===item.name); if(i>=0){ni[i].x=x;ni[i].y=y;ni[i].scale=scale;} }
            else if (elementNames.indexOf(item.name)>=0) { nl[item.name].x=x; nl[item.name].y=y; nl[item.name].scale=scale; }''',
'''            else if (isCustomImage(item.name)) { const i=ni.findIndex(image=>image.id===item.name); if(i>=0){ni[i].x=x;ni[i].y=y;ni[i].scale=scale;} }
            else if (isTimezoneClock(item.name)) { const i=timezoneClockIndex(item.name); const next=cloneTimezoneClocks(draftTimezoneClocks); if(i>=0){next[i].x=x;next[i].y=y;next[i].scale=scale;draftTimezoneClocks=next;} }
            else if (isCustomText(item.name)) { const i=customTextIndex(item.name); const next=cloneCustomTexts(draftCustomTexts); if(i>=0){next[i].x=x;next[i].y=y;next[i].scale=scale;draftCustomTexts=next;} }
            else if (elementNames.indexOf(item.name)>=0) { nl[item.name].x=x; nl[item.name].y=y; nl[item.name].scale=scale; }''',
'editor group scale dynamic dispatch')
s = one(s,
'''            } else if (isCustomImage(name)) {
                const index = nextImages.findIndex(image => image.id === name);
                if (index < 0) continue;
                nextImages[index].x = Number(nextImages[index].x) + delta.x;
                nextImages[index].y = Number(nextImages[index].y) + delta.y;
            } else if (elementNames.indexOf(name) >= 0) {''',
'''            } else if (isCustomImage(name)) {
                const index = nextImages.findIndex(image => image.id === name); if (index < 0) continue; nextImages[index].x = Number(nextImages[index].x) + delta.x; nextImages[index].y = Number(nextImages[index].y) + delta.y;
            } else if (isTimezoneClock(name)) {
                const next=cloneTimezoneClocks(draftTimezoneClocks);const i=timezoneClockIndex(name);if(i>=0){next[i].x=Number(next[i].x)+delta.x;next[i].y=Number(next[i].y)+delta.y;draftTimezoneClocks=next;}
            } else if (isCustomText(name)) {
                const next=cloneCustomTexts(draftCustomTexts);const i=customTextIndex(name);if(i>=0){next[i].x=Number(next[i].x)+delta.x;next[i].y=Number(next[i].y)+delta.y;draftCustomTexts=next;}
            } else if (elementNames.indexOf(name) >= 0) {''',
'editor translate dynamic dispatch')
s = one(s,
'''        else if (isCustomImage(name)) { const next = cloneCustomImages(draftCustomImages); const index = next.findIndex(image => image.id === name); if (index < 0) return; next[index].x = point.x; next[index].y = point.y; draftCustomImages = next; }
        else {''',
'''        else if (isCustomImage(name)) { const next = cloneCustomImages(draftCustomImages); const index = next.findIndex(image => image.id === name); if (index < 0) return; next[index].x = point.x; next[index].y = point.y; draftCustomImages = next; }
        else if(isTimezoneClock(name)){const next=cloneTimezoneClocks(draftTimezoneClocks);const i=timezoneClockIndex(name);next[i].x=point.x;next[i].y=point.y;draftTimezoneClocks=next;}
        else if(isCustomText(name)){const next=cloneCustomTexts(draftCustomTexts);const i=customTextIndex(name);next[i].x=point.x;next[i].y=point.y;draftCustomTexts=next;}
        else {''',
'editor write point dynamic dispatch')
s = one(s,
'''    function elementColor(name) { if (isCustomImage(name)) return "auto";''',
'''    function elementColor(name) { if (isCustomImage(name)) return "auto";''',
'editor color anchor noop')
s = one(s,
'''        if (name !== "visualizer" && elementNames.indexOf(name) < 0) return;''',
'''        if (name !== "visualizer" && elementNames.indexOf(name) < 0 && !isTimezoneClock(name) && !isCustomText(name)) return;''',
'editor dynamic color eligibility')
s = one(s,
'''        recordUndoBeforeChange(); if (name === "visualizer") { const next = cloneVisualizer(draftVisualizer); next.color = value; draftVisualizer = next; } else { const next = cloneLayout(draftLayout); next[name].color = value; draftLayout = next; }''',
'''        recordUndoBeforeChange(); if (name === "visualizer") { const next = cloneVisualizer(draftVisualizer); next.color = value; draftVisualizer = next; } else if(isTimezoneClock(name)){const next=cloneTimezoneClocks(draftTimezoneClocks);next[timezoneClockIndex(name)].color=value;draftTimezoneClocks=next;} else if(isCustomText(name)){const next=cloneCustomTexts(draftCustomTexts);next[customTextIndex(name)].color=value;draftCustomTexts=next;} else { const next = cloneLayout(draftLayout); next[name].color = value; draftLayout = next; }''',
'editor dynamic color dispatch')
s = one(s,
'''        else if (isCustomImage(name)) { const next = cloneCustomImages(draftCustomImages); const index = next.findIndex(image => image.id === name); if (index < 0) return; next[index].opacity = value; draftCustomImages = next; }
        else {''',
'''        else if (isCustomImage(name)) { const next = cloneCustomImages(draftCustomImages); const index = next.findIndex(image => image.id === name); if (index < 0) return; next[index].opacity = value; draftCustomImages = next; }
        else if(isTimezoneClock(name)){const next=cloneTimezoneClocks(draftTimezoneClocks);next[timezoneClockIndex(name)].opacity=value;draftTimezoneClocks=next;}
        else if(isCustomText(name)){const next=cloneCustomTexts(draftCustomTexts);next[customTextIndex(name)].opacity=value;draftCustomTexts=next;}
        else {''',
'editor dynamic opacity dispatch')
s = one(s,
'''        else if (isCustomImage(name)) { const next = cloneCustomImages(draftCustomImages); const index = next.findIndex(image => image.id === name); if (index < 0) return; next[index].stretch_x = x; next[index].stretch_y = y; draftCustomImages = next; }
        else {''',
'''        else if (isCustomImage(name)) { const next = cloneCustomImages(draftCustomImages); const index = next.findIndex(image => image.id === name); if (index < 0) return; next[index].stretch_x = x; next[index].stretch_y = y; draftCustomImages = next; }
        else if(isTimezoneClock(name)){const next=cloneTimezoneClocks(draftTimezoneClocks);next[timezoneClockIndex(name)].stretch_x=x;next[timezoneClockIndex(name)].stretch_y=y;draftTimezoneClocks=next;}
        else if(isCustomText(name)){const next=cloneCustomTexts(draftCustomTexts);next[customTextIndex(name)].stretch_x=x;next[customTextIndex(name)].stretch_y=y;draftCustomTexts=next;}
        else {''',
'editor dynamic stretch dispatch')
s = one(s,
'''        else if (isCustomImage(name)) { const next = cloneCustomImages(draftCustomImages); const index = next.findIndex(image => image.id === name); if (index < 0) return; next[index].visible = !!visible; draftCustomImages = next; }
        else {''',
'''        else if (isCustomImage(name)) { const next = cloneCustomImages(draftCustomImages); const index = next.findIndex(image => image.id === name); if (index < 0) return; next[index].visible = !!visible; draftCustomImages = next; }
        else if(isTimezoneClock(name)){const next=cloneTimezoneClocks(draftTimezoneClocks);next[timezoneClockIndex(name)].visible=!!visible;draftTimezoneClocks=next;}
        else if(isCustomText(name)){const next=cloneCustomTexts(draftCustomTexts);next[customTextIndex(name)].visible=!!visible;draftCustomTexts=next;}
        else {''',
'editor dynamic visibility dispatch')
s = one(s,
'''    function elementEnabled(name) { if (name === "visualizer") return draftVisualizer.enabled === true; if (isCustomImage(name)) { const point = elementPoint(name); return point ? point.visible !== false : false; } return draftVisibility[name] !== false; }''',
'''    function elementEnabled(name) { if (name === "visualizer") return draftVisualizer.enabled === true; if (isCustomImage(name) || isTimezoneClock(name) || isCustomText(name)) { const point = elementPoint(name); return point ? point.visible !== false : false; } return draftVisibility[name] !== false; }''',
'editor dynamic enabled')
# Reset/load/save.
s = one(s,
'''        recordUndoBeforeChange(); draftLayout = defaultLayout(); draftCustomImages = []; draftVisualizer = defaultVisualizer();''',
'''        recordUndoBeforeChange(); draftLayout = defaultLayout(); draftCustomImages = []; draftTimezoneClocks=[]; draftCustomTexts=[]; previewTimezoneValues=({}); draftVisualizer = defaultVisualizer();''',
'editor reset dynamic arrays')
s = one(s,
'''        draftLayout = cloneLayout(BarState.lockscreenLayout()); draftCustomImages = cloneCustomImages(BarState.lockscreenCustomImages()); draftVisualizer = cloneVisualizer(BarState.lockscreenVisualizer());''',
'''        draftLayout = cloneLayout(BarState.lockscreenLayout()); draftCustomImages = cloneCustomImages(BarState.lockscreenCustomImages()); draftTimezoneClocks=cloneTimezoneClocks(BarState.lockscreenTimezoneClocks()); draftCustomTexts=cloneCustomTexts(BarState.lockscreenCustomTexts()); draftVisualizer = cloneVisualizer(BarState.lockscreenVisualizer()); refreshPreviewTimezoneValues();''',
'editor load dynamic arrays')
s = one(s,
'''            String(draftLogoSpawnAnimation), String(draftPasswordMaskMode), String(draftPasswordMaskCharacter), String(draftClockFormat)]);''',
'''            String(draftLogoSpawnAnimation), String(draftPasswordMaskMode), String(draftPasswordMaskCharacter), String(draftClockFormat), JSON.stringify(draftTimezoneClocks), JSON.stringify(draftCustomTexts)]);''',
'editor save dynamic arrays')
# Labels and delete behavior.
s = one(s,
'''    function elementLabel(name) { if (name === "logo") return "Logo"; if (name === "time") return "Time"; if (name === "date") return "Date"; if (name === "username") return "Username"; if (name === "weather") return "Weather"; if (name === "password") return "Password"; if (name === "visualizer") return "Visualizer"; if (isCustomImage(name)) return "Image " + (customImageIndex(name) + 1); return name; }''',
'''    function elementLabel(name) { if (name === "logo") return "Logo"; if (name === "time") return "Time"; if (name === "date") return "Date"; if (name === "username") return "Username"; if (name === "weather") return "Weather"; if (name === "password") return "Password"; if (name === "visualizer") return "Visualizer"; if (isCustomImage(name)) return "Image " + (customImageIndex(name) + 1); if(isTimezoneClock(name)) return "Timezone " + (timezoneClockIndex(name)+1); if(isCustomText(name)) return "Custom Text " + (customTextIndex(name)+1); return name; }''',
'editor dynamic labels')
s = one(s,
'''                else if (event.key === Qt.Key_Delete && root.isCustomImage(root.selectedElement)) { root.removeCustomImage(root.selectedElement); event.accepted = true; } }''',
'''                else if (event.key === Qt.Key_Delete && root.isCustomImage(root.selectedElement)) { root.removeCustomImage(root.selectedElement); event.accepted = true; }
                else if (event.key === Qt.Key_Delete && root.isTimezoneClock(root.selectedElement)) { root.removeTimezoneClock(root.selectedElement); event.accepted = true; }
                else if (event.key === Qt.Key_Delete && root.isCustomText(root.selectedElement)) { root.removeCustomText(root.selectedElement); event.accepted = true; } }''',
'editor dynamic delete')
# Timezone preview process near other processes.
s = one(s,
'''    Process {
        id: previewContrastProcess''',
'''    Process { id: timezonePreviewProcess; stdout: SplitParser { onRead: line => root.applyPreviewTimezoneValues(line) } }
    Timer { interval: 15000; repeat: true; running: root.open && root.draftTimezoneClocks.length > 0; triggeredOnStart: true; onTriggered: root.refreshPreviewTimezoneValues() }
    Process {
        id: previewContrastProcess''',
'editor timezone process')
# Scene bindings: at least primary; replace every exact binding block occurrence.
s = all_matches(s,
'''                blurStyle: root.draftBlurStyle; autoAccents: root.draftAutoAccents; layout: root.draftLayout; customImages: root.draftCustomImages; visualizer: root.draftVisualizer; audioBands: previewAudioAnalyzer.bands; backgroundOpacity: root.draftBackgroundOpacity''',
'''                blurStyle: root.draftBlurStyle; autoAccents: root.draftAutoAccents; layout: root.draftLayout; customImages: root.draftCustomImages; timezoneClocks: root.draftTimezoneClocks; timezoneValues: root.previewTimezoneValues; customTexts: root.draftCustomTexts; visualizer: root.draftVisualizer; audioBands: previewAudioAnalyzer.bands; backgroundOpacity: root.draftBackgroundOpacity''',
1,
'editor preview dynamic bindings')
# Add buttons to element row.
s = one(s,
'''                        SettingsButton { label: "Add Image"; textSize: 9; available: root.draftCustomImages.length < root.customImageMaximum && !customImagePickerProcess.running; onClicked: root.suspendForCustomImagePicker() }
                        SettingsButton { label: "Remove Image"; textSize: 9; visible: root.isCustomImage(root.selectedElement); available: visible; onClicked: root.removeCustomImage(root.selectedElement) }''',
'''                        SettingsButton { label: "Add Image"; textSize: 9; available: root.draftCustomImages.length < root.customImageMaximum && !customImagePickerProcess.running; onClicked: root.suspendForCustomImagePicker() }
                        SettingsButton { label: "Add timezone clock"; textSize: 9; available: root.draftTimezoneClocks.length < root.timezoneClockMaximum; onClicked: root.addTimezoneClock() }
                        SettingsButton { label: "Add custom text"; textSize: 9; available: root.draftCustomTexts.length < root.customTextMaximum; onClicked: root.addCustomText() }
                        SettingsButton { label: "Remove Image"; textSize: 9; visible: root.isCustomImage(root.selectedElement); available: visible; onClicked: root.removeCustomImage(root.selectedElement) }
                        SettingsButton { label: "Remove clock"; textSize: 9; visible: root.isTimezoneClock(root.selectedElement); available: visible; onClicked: root.removeTimezoneClock(root.selectedElement) }
                        SettingsButton { label: "Remove text"; textSize: 9; visible: root.isCustomText(root.selectedElement); available: visible; onClicked: root.removeCustomText(root.selectedElement) }''',
'editor add dynamic buttons')
# Dynamic settings rows inserted before visualizer settings.
ui_anchor = '''                    RowLayout {
                        Layout.fillWidth: true; spacing: 7; visible: root.activeDrawer === "element" && root.selectedElement === "visualizer"'''
ui_insert = r'''                    RowLayout {
                        Layout.fillWidth: true; spacing: 7; visible: root.activeDrawer === "element" && root.isTimezoneClock(root.selectedElement)
                        Text { text: "Timezone"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 9 }
                        LockscreenCompactSelector { Layout.preferredWidth: 180; model: root.timezonePresets; currentIndex: root.timezonePresetIndex(root.elementPoint(root.selectedElement).timezone); onActivated: index => root.setTimezoneClockZone(root.selectedElement, root.timezonePresets[index].key) }
                        SettingsButton { label: root.elementPoint(root.selectedElement).format === "12h" ? "12-hour" : "24-hour"; active: root.elementPoint(root.selectedElement).format === "12h"; textSize: 9; onClicked: root.setTimezoneClockFormat(root.selectedElement, root.elementPoint(root.selectedElement).format === "12h" ? "24h" : "12h") }
                        Item { Layout.fillWidth: true }
                        Text { text: "Each extra clock has independent timezone, format, position, scale, color, opacity, and rotation."; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 8; elide: Text.ElideRight }
                    }

                    RowLayout {
                        Layout.fillWidth: true; spacing: 7; visible: root.activeDrawer === "element" && root.isCustomText(root.selectedElement)
                        Text { text: "Text"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 9 }
                        Rectangle { Layout.preferredWidth: 240; Layout.preferredHeight: 58; color: Theme.background; border.width: 1; border.color: Theme.muted
                            TextEdit { id: customTextEditor; anchors.fill: parent; anchors.margins: 5; text: root.isCustomText(root.selectedElement) ? root.elementPoint(root.selectedElement).text : ""; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: 9; wrapMode: TextEdit.Wrap; selectByMouse: true
                                Keys.onReturnPressed: event => { if (event.modifiers & Qt.ShiftModifier) { insert(cursorPosition, "\n"); event.accepted = true; } else event.accepted = false; }
                                onActiveFocusChanged: { if (!activeFocus && root.isCustomText(root.selectedElement)) root.setCustomTextContent(root.selectedElement, text); }
                            }
                        }
                        Text { text: "Random choices (one per line)"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 9 }
                        Rectangle { Layout.preferredWidth: 210; Layout.preferredHeight: 58; color: Theme.background; border.width: 1; border.color: Theme.muted
                            TextEdit { anchors.fill: parent; anchors.margins: 5; text: root.isCustomText(root.selectedElement) ? root.elementPoint(root.selectedElement).variants.join("\n") : ""; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: 9; wrapMode: TextEdit.Wrap; selectByMouse: true
                                Keys.onReturnPressed: event => { if (event.modifiers & Qt.ShiftModifier) { insert(cursorPosition, "\n"); event.accepted = true; } else event.accepted = false; }
                                onActiveFocusChanged: { if (!activeFocus && root.isCustomText(root.selectedElement)) root.setCustomTextChoices(root.selectedElement, text); }
                            }
                        }
                        SettingsButton { label: "Randomize"; active: root.elementPoint(root.selectedElement).randomize === true; textSize: 9; onClicked: root.setCustomTextRandomize(root.selectedElement, !root.elementPoint(root.selectedElement).randomize) }
                        SettingsButton { label: "Left"; active: root.elementPoint(root.selectedElement).alignment === "left"; textSize: 9; onClicked: root.setCustomTextAlignment(root.selectedElement, "left") }
                        SettingsButton { label: "Center"; active: root.elementPoint(root.selectedElement).alignment === "center"; textSize: 9; onClicked: root.setCustomTextAlignment(root.selectedElement, "center") }
                        SettingsButton { label: "Right"; active: root.elementPoint(root.selectedElement).alignment === "right"; textSize: 9; onClicked: root.setCustomTextAlignment(root.selectedElement, "right") }
                        Item { Layout.fillWidth: true }
                    }

''' + ui_anchor
s = one(s, ui_anchor, ui_insert, 'editor dynamic settings UI')
p.write_text(s)
