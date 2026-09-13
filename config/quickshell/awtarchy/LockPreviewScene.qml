import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell

Item {
    id: root

    required property var theme
    required property string animationPreference
    required property int randomFormationMode
    required property int logoPhysicsHz
    required property bool mouseInteractive
    required property bool showLogo
    required property bool showTime
    required property bool showDate
    required property bool showUsername
    required property bool showWeather
    required property string weatherText
    required property string backgroundMode
    required property string wallpaperSource
    required property color backgroundColor
    required property string wallpaperFit
    required property real wallpaperFocalX
    required property real wallpaperFocalY
    required property string overlayMode
    required property real overlayStrength
    required property real wallpaperBlur
    required property string blurStyle
    required property var autoAccents
    required property var layout
    required property var customImages
    required property var visualizer
    required property var audioBands
    required property int backgroundOpacity
    required property string passwordMaskMode
    required property string passwordMaskCharacter
    required property string clockFormat
    property Item desktopBackingSource: null

    property bool previewMode: false
    property bool editorMode: false
    property var editorVisibility: ({})
    property string editorHeldElement: ""
    property real editorHoldScale: 1.0
    property bool unlocking: false
    property bool entered: false
    property bool externalEntryTransitionRunning: false
    property int presentationReplayToken: 0
    property string presentationPhase: "transition"
    property int logoEntryEpoch: 0
    property int customImageSpawnEpoch: 0
    readonly property bool effectiveEntryTransitionRunning: externalEntryTransitionRunning
    readonly property bool customImageEntryStarted:
        presentationPhase === "custom-images" || presentationPhase === "settled"
    readonly property string effectivePasswordMaskMode:
        ["squares", "dots", "custom"].indexOf(String(passwordMaskMode)) >= 0
            ? String(passwordMaskMode) : "squares"
    readonly property string effectivePasswordMaskCharacter:
        String(passwordMaskCharacter || "").length > 0 ? String(passwordMaskCharacter) : "•"

    onEffectiveEntryTransitionRunningChanged: {
        if (effectiveEntryTransitionRunning) {
            logoEntryPhaseTimer.stop();
            customImageEntryPhaseTimer.stop();
            presentationPhase = "transition";
            return;
        }
        if (entered && (!previewMode || presentationReplayToken > 0))
            beginLogoEntry();
    }

    readonly property bool logoHoverActive: mouseInteractive && pointerActive && showLogo
        && logoContainsPoint(lastPointerX, lastPointerY) && !logoExplosionActive
    readonly property bool logoSimulationActive: logoExplosionActive || logoHoverDirty || logoReturnPending
    readonly property real securePasswordEntryOpacity: root.unlocking
        ? 0 : root.entered && !root.effectiveEntryTransitionRunning ? 1 : 0
    readonly property real uiScale: Math.max(0.72, Math.min(1.35,
        Math.min(width / 1920, height / 1080)))
    readonly property var wordmarkRows: [
        " ▄▄▄      ██     █ ▄▄▄█████ ▄▄▄      ██▀███  ▄████▄  ██  ██ ██   ██",
        " ████▄     █  █  █ █  ██  █ ████▄    ██   ██ ██▀ ▀█  ██  ██  ██  ██",
        " ██  ▀█▄  ██  █  ██   ██    ██  ▀█▄  ██  ▄█  ██    ▄ ██▀▀██   ██ ██",
        " ██▄▄▄▄██ ██  █  ██   ██    ██▄▄▄▄██ ██▀▀█▄  ██▄ ▄██ ██  ██    ▐██",
        "███    ██  ███████    ██    ██    ██ ██   ██  ████▀  ██  ██    ██",
        "             ███                                              ██",
        "                                                              ██"
    ]
    readonly property int wordmarkColumns: 67
    readonly property int wordmarkCellWidth: Math.max(8, Math.floor(18 * uiScale))
    readonly property int wordmarkCellHeight: Math.max(12, Math.floor(24 * uiScale))
    readonly property real wordmarkWidth: wordmarkColumns * wordmarkCellWidth
    readonly property real wordmarkHeight: wordmarkRows.length * wordmarkCellHeight
    readonly property int formationMode: animationPreference === "swarm" ? 0
        : animationPreference === "edges" ? 1
        : animationPreference === "center" ? 2
        : animationPreference === "split" ? 3
        : randomFormationMode
    readonly property bool pointerEffectsEnabled: mouseInteractive && pointerActive
    readonly property int ghostTrailLength: 6
    readonly property int cursorFadeDelayMs: 180
    readonly property int cursorFadeDurationMs: 320
    readonly property real pointerMovementThreshold: 3 * uiScale
    readonly property int logoPhysicsIntervalMs: logoPhysicsHz >= 90 ? 11
        : logoPhysicsHz >= 60 ? 17 : 33
    readonly property int logoExplosionScatterMs: 460
    readonly property int logoExplosionMaxMs: 1450
    readonly property real logoExplosionBaseSpeed: 1020 * uiScale
    readonly property real logoExplosionMaxSpeed: 1900 * uiScale
    readonly property real logoExplosionOffsetCap: 760 * uiScale
    readonly property real logoExplosionCollisionDistance: Math.max(
        wordmarkCellWidth, wordmarkCellHeight) * 0.76
    readonly property real logoExplosionBucketSize: Math.max(
        24 * uiScale, logoExplosionCollisionDistance * 1.35)
    readonly property int logoEntryDurationMs: 2350
    readonly property string usernameText: showUsername ? Quickshell.env("USER") : "";
    readonly property real passwordCenterX: normalizedX("password", 0.50) * width
    readonly property real passwordCenterY: normalizedY("password", 0.70) * height
    readonly property real passwordWidth: Math.round(420 * uiScale * elementScale("password"))
    readonly property real passwordHeight: Math.round(58 * uiScale * elementScale("password"))

    property bool pointerActive: false
    property bool logoExplosionActive: false
    property bool logoHoverDirty: false
    property bool logoReturnPending: false
    property var logoParticles: ({})
    property var logoParticleBuckets: ({})
    property real logoExplosionElapsedMs: 0
    property real ghostHeadX: -100
    property real ghostHeadY: -100
    property var ghostTrail: [
        ({ x: -100, y: -100 }), ({ x: -100, y: -100 }),
        ({ x: -100, y: -100 }), ({ x: -100, y: -100 }),
        ({ x: -100, y: -100 }), ({ x: -100, y: -100 })
    ]
    property real ghostOpacity: 0
    property double lastPointerSampleTime: 0
    property real lastPointerX: -1
    property real lastPointerY: -1

    onLogoHoverActiveChanged: {
        logoHoverDirty = true;
        if (logoHoverActive)
            logoReturnPending = false;
        else if (!logoExplosionActive)
            logoReturnPending = true;
    }
    property string timeText: ""
    property string dateText: "";

    function beginLogoEntry() {
        logoEntryPhaseTimer.stop();
        customImageEntryPhaseTimer.stop();
        logoEntryEpoch++;
        presentationPhase = "logo";
        if (!showLogo || animationPreference === "off") {
            beginCustomImageEntry();
            return;
        }
        logoEntryPhaseTimer.restart();
    }

    function customImageEntryDurationMs() {
        if (!Array.isArray(customImages))
            return 0;
        let duration = 0;
        for (const image of customImages) {
            if (!image || image.visible === false)
                continue;
            const mode = customImageSpawnMode(image);
            if (mode === "pixel-warp")
                return 620;
            if (mode !== "none")
                duration = Math.max(duration, 520);
        }
        return duration;
    }

    function beginCustomImageEntry() {
        logoEntryPhaseTimer.stop();
        customImageEntryPhaseTimer.stop();
        customImageSpawnEpoch++;
        presentationPhase = "custom-images";
        const duration = customImageEntryDurationMs();
        if (duration <= 0) {
            presentationPhase = "settled";
            return;
        }
        customImageEntryPhaseTimer.interval = duration;
        customImageEntryPhaseTimer.restart();
    }

    function wallpaperGeometry() {
        const sourceWidth = Number(wallpaperImage.sourceSize.width);
        const sourceHeight = Number(wallpaperImage.sourceSize.height);
        if (!Number.isFinite(sourceWidth) || !Number.isFinite(sourceHeight)
                || sourceWidth <= 0 || sourceHeight <= 0 || root.width <= 0 || root.height <= 0)
            return ({ x: 0, y: 0, width: root.width, height: root.height });
        const contain = root.wallpaperFit === "contain";
        const factor = contain
            ? Math.min(root.width / sourceWidth, root.height / sourceHeight)
            : Math.max(root.width / sourceWidth, root.height / sourceHeight);
        const targetWidth = sourceWidth * factor;
        const targetHeight = sourceHeight * factor;
        if (contain) {
            return ({
                x: (root.width - targetWidth) / 2,
                y: (root.height - targetHeight) / 2,
                width: targetWidth,
                height: targetHeight
            });
        }
        const focalX = Math.max(0, Math.min(1, Number(root.wallpaperFocalX)));
        const focalY = Math.max(0, Math.min(1, Number(root.wallpaperFocalY)));
        return ({
            x: -(targetWidth - root.width) * focalX,
            y: -(targetHeight - root.height) * focalY,
            width: targetWidth,
            height: targetHeight
        });
    }

    function normalizedPoint(name) {
        const value = root.layout && typeof root.layout === "object"
            ? root.layout[name] : null;
        return value && typeof value === "object" ? value : null;
    }

    function customImageForName(name) {
        if (!Array.isArray(root.customImages))
            return null;
        const key = String(name || "");
        for (let i = 0; i < root.customImages.length; ++i) {
            const image = root.customImages[i];
            if (image && typeof image === "object" && String(image.id || "") === key)
                return image;
        }
        return null;
    }

    function customImageSpawnMode(image) {
        const value = String(image && image.spawn_animation !== undefined
            ? image.spawn_animation : "none");
        return ["none", "pixel-warp", "closest-edge", "top", "bottom", "left", "right"].indexOf(value) >= 0
            ? value : "none";
    }

    function customImageSpawnOffset(image, itemWidth, itemHeight) {
        let mode = customImageSpawnMode(image);
        if (mode === "none" || mode === "pixel-warp")
            return Qt.point(0, 0);
        const x = Math.max(0, Math.min(1, Number(image && image.x !== undefined ? image.x : 0.5)));
        const y = Math.max(0, Math.min(1, Number(image && image.y !== undefined ? image.y : 0.5)));
        if (mode === "closest-edge") {
            let distance = x;
            mode = "left";
            if (1 - x < distance) { distance = 1 - x; mode = "right"; }
            if (y < distance) { distance = y; mode = "top"; }
            if (1 - y < distance) { mode = "bottom"; }
        }
        const centerX = x * root.width;
        const centerY = y * root.height;
        const margin = Math.max(24, 32 * root.uiScale);
        if (mode === "left") return Qt.point(-(centerX + itemWidth / 2 + margin), 0);
        if (mode === "right") return Qt.point(root.width - centerX + itemWidth / 2 + margin, 0);
        if (mode === "top") return Qt.point(0, -(centerY + itemHeight / 2 + margin));
        return Qt.point(0, root.height - centerY + itemHeight / 2 + margin);
    }

    function presentationPoint(name) {
        if (name === "visualizer" && root.visualizer
                && typeof root.visualizer === "object" && !Array.isArray(root.visualizer))
            return root.visualizer;
        return normalizedPoint(name) || customImageForName(name);
    }

    function normalizedX(name, fallback) {
        const point = presentationPoint(name);
        const value = point ? Number(point.x) : Number.NaN;
        return Number.isFinite(value) ? Math.max(0, Math.min(1, value)) : fallback;
    }

    function normalizedY(name, fallback) {
        const point = presentationPoint(name);
        const value = point ? Number(point.y) : Number.NaN;
        return Number.isFinite(value) ? Math.max(0, Math.min(1, value)) : fallback;
    }

    function elementScale(name) {
        const point = presentationPoint(name);
        const value = point ? Number(point.scale === undefined ? 1 : point.scale) : 1;
        const maximum = 100.00;
        const baseScale = Number.isFinite(value) ? Math.max(0.50, Math.min(maximum, value)) : 1;
        const holdScale = root.editorMode && name === editorHeldElement ? editorHoldScale : 1.0;
        const safeHoldScale = Number.isFinite(Number(holdScale))
            ? Math.max(1.0, Math.min(1.12, Number(holdScale))) : 1.0;
        return baseScale * safeHoldScale;
    }

    function elementStretchX(name) {
        const point = presentationPoint(name);
        const value = point ? Number(point.stretch_x === undefined ? 1 : point.stretch_x) : 1;
        return Number.isFinite(value) ? Math.max(0.25, Math.min(4.00, value)) : 1;
    }

    function elementStretchY(name) {
        const point = presentationPoint(name);
        const value = point ? Number(point.stretch_y === undefined ? 1 : point.stretch_y) : 1;
        return Number.isFinite(value) ? Math.max(0.25, Math.min(4.00, value)) : 1;
    }

    function elementOpacity(name) {
        const point = presentationPoint(name);
        const value = point ? Number(point.opacity === undefined ? 100 : point.opacity) : 100;
        const minimum = name === "password" ? 20 : 0;
        const percent = Number.isFinite(value) ? Math.max(minimum, Math.min(100, value)) : 100;
        return percent / 100;
    }

    function elementRotation(name) {
        const image = customImageForName(name);
        if (!image)
            return 0;
        const value = Number(image.rotation === undefined ? 0 : image.rotation);
        return Number.isFinite(value) ? Math.max(-180, Math.min(180, value)) : 0;
    }

    function elementColor(name) {
        const point = presentationPoint(name);
        const value = String(point && point.color !== undefined ? point.color : "auto");
        const automatic = String(root.autoAccents && root.autoAccents[name] !== undefined
            ? root.autoAccents[name] : "#ffffff");
        const safeAuto = /^#[0-9a-fA-F]{6}$/.test(automatic) ? automatic : "#ffffff";
        return value === "auto" ? safeAuto
            : /^#[0-9a-fA-F]{6}$/.test(value) ? value : safeAuto;
    }

    function visualizerNumber(name, fallback, minimum, maximum) {
        const value = root.visualizer && typeof root.visualizer === "object"
            ? Number(root.visualizer[name]) : Number.NaN;
        return Number.isFinite(value)
            ? Math.max(minimum, Math.min(maximum, value)) : fallback;
    }

    function visualizerBandCount() {
        return Math.max(4, Math.min(64,
            Math.round(visualizerNumber("bands", 16, 4, 64))));
    }

    function visualizerGapPx() {
        return visualizerNumber("gap", 4, 0, 24) * 0.60 * root.uiScale;
    }

    function visualizerResponseHeight() {
        return 180 * root.uiScale
            * visualizerNumber("height", 100, 25, 300) / 100;
    }

    function visualizerShape() {
        const value = String(root.visualizer && root.visualizer.shape !== undefined
            ? root.visualizer.shape : "straight");
        return ["straight", "arc", "circle"].indexOf(value) >= 0
            ? value : "straight";
    }

    function visualizerBend() {
        return Math.round(visualizerNumber("bend", 45, -2000, 2000));
    }

    function visualizerBands() {
        const count = Math.min(64, root.visualizerBandCount());
        const source = Array.isArray(root.audioBands) ? root.audioBands : [];
        const result = [];
        const sensitivity = visualizerNumber("sensitivity", 180, 25, 300) / 100;
        for (let i = 0; i < count; ++i) {
            if (source.length === 0) {
                result.push(0);
                continue;
            }
            const start = Math.floor(i * source.length / count);
            const end = Math.max(start + 1,
                Math.floor((i + 1) * source.length / count));
            let total = 0;
            let used = 0;
            for (let j = start; j < Math.min(source.length, end); ++j) {
                const value = Number(source[j]);
                if (!Number.isFinite(value))
                    continue;
                total += Math.max(0, Math.min(1, value));
                used++;
            }
            const average = used > 0 ? total / used : 0;
            result.push(Math.max(0, Math.min(1, average * sensitivity)));
        }
        return result;
    }

    function visualizerBaseWidth() {
        if (visualizerShape() === "circle")
            return 380 * root.uiScale;
        return 520 * root.uiScale;
    }

    function visualizerBaseHeight() {
        if (visualizerShape() === "circle")
            return 380 * root.uiScale;
        return Math.max(120 * root.uiScale, visualizerResponseHeight() * 1.5);
    }

    function presentationVisible(name, configuredVisible) {
        return configuredVisible || root.editorMode;
    }

    function presentationOpacity(name) {
        return root.editorMode && root.editorVisibility[name] === false ? 0.30 : 1.0;
    }

    function elementVisualWidth(name) {
        if (name === "visualizer")
            return visualizerBaseWidth() * root.elementScale(name) * root.elementStretchX(name);
        if (customImageForName(name))
            return 180 * root.uiScale * root.elementScale(name) * root.elementStretchX(name);
        if (name === "logo") return root.wordmarkWidth * root.elementScale("logo") * root.elementStretchX("logo");
        if (name === "time") return timeItem.implicitWidth * root.elementScale("time") * root.elementStretchX("time");
        if (name === "date") return dateItem.implicitWidth * root.elementScale("date") * root.elementStretchX("date");
        if (name === "username") return usernameItem.implicitWidth * root.elementScale("username") * root.elementStretchX("username");
        if (name === "weather") return weatherItem.implicitWidth * root.elementScale("weather") * root.elementStretchX("weather");
        if (name === "password") return root.passwordWidth * root.elementStretchX("password");
        return 48 * root.uiScale;
    }

    function elementVisualHeight(name) {
        if (name === "visualizer")
            return visualizerBaseHeight() * root.elementScale(name) * root.elementStretchY(name);
        if (customImageForName(name))
            return 180 * root.uiScale * root.elementScale(name) * root.elementStretchY(name);
        if (name === "logo") return root.wordmarkHeight * root.elementScale("logo") * root.elementStretchY("logo");
        if (name === "time") return timeItem.implicitHeight * root.elementScale("time") * root.elementStretchY("time");
        if (name === "date") return dateItem.implicitHeight * root.elementScale("date") * root.elementStretchY("date");
        if (name === "username") return usernameItem.implicitHeight * root.elementScale("username") * root.elementStretchY("username");
        if (name === "weather") return weatherItem.implicitHeight * root.elementScale("weather") * root.elementStretchY("weather");
        if (name === "password") return root.passwordHeight * root.elementStretchY("password");
        return 28 * root.uiScale;
    }

    function isFilledWordmarkCell(row, column) {
        if (row < 0 || row >= wordmarkRows.length || column < 0 || column >= wordmarkColumns)
            return false;
        const rowText = wordmarkRows[row];
        if (column >= rowText.length)
            return false;
        const glyph = rowText.charAt(column);
        return glyph === "█" || glyph === "▄" || glyph === "▀" || glyph === "▐";
    }

    function logoCellKey(row, column) {
        return String(row) + ":" + String(column);
    }

    function logoParticleOffset(row, column) {
        const particle = logoParticles[logoCellKey(row, column)];
        if (!particle)
            return ({ x: 0, y: 0 });
        const x = Number(particle.x);
        const y = Number(particle.y);
        return ({
            x: Number.isFinite(x) ? x : 0,
            y: Number.isFinite(y) ? y : 0
        });
    }

    function clampedParticleVelocity(value) {
        const numeric = Number(value);
        if (!Number.isFinite(numeric))
            return 0;
        return Math.max(-logoExplosionMaxSpeed, Math.min(logoExplosionMaxSpeed, numeric));
    }

    function bounceLogoParticleAtBounds(particle) {
        const cap = logoExplosionOffsetCap;
        const restitution = 0.42;
        if (particle.x < -cap) {
            particle.x = -cap;
            particle.vx = Math.abs(particle.vx) * restitution;
        } else if (particle.x > cap) {
            particle.x = cap;
            particle.vx = -Math.abs(particle.vx) * restitution;
        }
        if (particle.y < -cap) {
            particle.y = -cap;
            particle.vy = Math.abs(particle.vy) * restitution;
        } else if (particle.y > cap) {
            particle.y = cap;
            particle.vy = -Math.abs(particle.vy) * restitution;
        }
    }

    function ensureLogoParticle(row, column) {
        const key = logoCellKey(row, column);
        const existing = logoParticles[key];
        return existing ? Object.assign({}, existing) : ({
            row: row, column: column, x: 0, y: 0, vx: 0, vy: 0
        });
    }

    function logoHoverTarget(row, column, localPointer) {
        if (!logoHoverActive)
            return ({ x: 0, y: 0 });
        const local = localPointer;
        const centerX = (column + 0.5) * wordmarkCellWidth;
        const centerY = (row + 0.5) * wordmarkCellHeight;
        let dx = centerX - local.x;
        let dy = centerY - local.y;
        const distance = Math.max(0.001, Math.sqrt(dx * dx + dy * dy));
        const radius = Math.max(wordmarkCellWidth, wordmarkCellHeight) * 4.2;
        const unit = Math.max(0, Math.min(1, 1 - distance / radius));
        const weight = unit * unit * (3 - 2 * unit);
        const displacement = 34 * uiScale * weight;
        return ({ x: dx / distance * displacement, y: dy / distance * displacement });
    }

    function triggerLogoExplosion(x, y) {
        if (!mouseInteractive || !showLogo)
            return;
        const local = wordmarkItem.mapFromItem(root, x, y);

        const next = ({});
        for (let row = 0; row < wordmarkRows.length; ++row) {
            for (let column = 0; column < wordmarkColumns; ++column) {
                if (!isFilledWordmarkCell(row, column))
                    continue;
                const key = logoCellKey(row, column);
                const particle = ensureLogoParticle(row, column);
                const homeX = (column + 0.5) * wordmarkCellWidth;
                const homeY = (row + 0.5) * wordmarkCellHeight;
                let dx = homeX + Number(particle.x || 0) - local.x;
                let dy = homeY + Number(particle.y || 0) - local.y;
                let distance = Math.sqrt(dx * dx + dy * dy);
                const seed = row * wordmarkColumns + column + 1;
                if (distance < 0.001) {
                    const fallbackAngle = (seed * 2.399963229728653) % (Math.PI * 2);
                    dx = Math.cos(fallbackAngle);
                    dy = Math.sin(fallbackAngle);
                    distance = 1;
                }
                const jitter = (((seed * 37) % 19) - 9) * 0.018;
                const angle = Math.atan2(dy, dx) + jitter;
                const speed = logoExplosionBaseSpeed
                    * (0.84 + ((seed * 23) % 31) / 100);
                particle.vx += Math.cos(angle) * speed;
                particle.vy += Math.sin(angle) * speed;
                particle.vx = clampedParticleVelocity(particle.vx);
                particle.vy = clampedParticleVelocity(particle.vy);
                next[key] = particle;
            }
        }
        logoParticles = next;
        logoExplosionElapsedMs = 0;
        logoExplosionActive = Object.keys(next).length > 0;
        logoHoverDirty = logoExplosionActive;
    }

    function rebuildLogoBuckets() {
        const buckets = ({});
        for (const key in logoParticles) {
            const particle = logoParticles[key];
            if (!particle)
                continue;
            const centerX = (Number(particle.column) + 0.5) * wordmarkCellWidth
                + Number(particle.x || 0);
            const centerY = (Number(particle.row) + 0.5) * wordmarkCellHeight
                + Number(particle.y || 0);
            const bucketX = Math.floor(centerX / logoExplosionBucketSize);
            const bucketY = Math.floor(centerY / logoExplosionBucketSize);
            const bucketKey = String(bucketX) + ":" + String(bucketY);
            const members = buckets[bucketKey] || [];
            members.push(key);
            buckets[bucketKey] = members;
        }
        logoParticleBuckets = buckets;
    }

    function resolveLogoCollisions() {
        const next = ({});
        for (const key in logoParticles)
            next[key] = Object.assign({}, logoParticles[key]);
        const seen = ({});
        const restitution = 0.58;
        const minimumDistance = Math.max(4, logoExplosionCollisionDistance);

        for (const bucketKey in logoParticleBuckets) {
            const parts = String(bucketKey).split(":");
            const baseX = Number(parts[0]);
            const baseY = Number(parts[1]);
            const current = logoParticleBuckets[bucketKey] || [];
            for (let nx = -1; nx <= 1; ++nx) {
                for (let ny = -1; ny <= 1; ++ny) {
                    const neighborKey = String(baseX + nx) + ":" + String(baseY + ny);
                    const neighbor = logoParticleBuckets[neighborKey] || [];
                    for (let i = 0; i < current.length; ++i) {
                        for (let j = 0; j < neighbor.length; ++j) {
                            const aKey = current[i];
                            const bKey = neighbor[j];
                            if (aKey === bKey)
                                continue;
                            const pairKey = aKey < bKey
                                ? aKey + "|" + bKey : bKey + "|" + aKey;
                            if (seen[pairKey])
                                continue;
                            seen[pairKey] = true;
                            const a = next[aKey];
                            const b = next[bKey];
                            if (!a || !b)
                                continue;
                            const ax = (Number(a.column) + 0.5) * wordmarkCellWidth + Number(a.x || 0);
                            const ay = (Number(a.row) + 0.5) * wordmarkCellHeight + Number(a.y || 0);
                            const bx = (Number(b.column) + 0.5) * wordmarkCellWidth + Number(b.x || 0);
                            const by = (Number(b.row) + 0.5) * wordmarkCellHeight + Number(b.y || 0);
                            let dx = bx - ax;
                            let dy = by - ay;
                            let distance = Math.sqrt(dx * dx + dy * dy);
                            if (distance >= minimumDistance)
                                continue;
                            if (distance < 0.001) {
                                const seed = Number(a.row) * wordmarkColumns + Number(a.column) + 1;
                                const angle = (seed * 1.61803398875) % (Math.PI * 2);
                                dx = Math.cos(angle);
                                dy = Math.sin(angle);
                                distance = 1;
                            }
                            const normalX = dx / distance;
                            const normalY = dy / distance;
                            const overlap = minimumDistance - distance;
                            a.x -= normalX * overlap * 0.5;
                            a.y -= normalY * overlap * 0.5;
                            b.x += normalX * overlap * 0.5;
                            b.y += normalY * overlap * 0.5;
                            const relative = (Number(b.vx) - Number(a.vx)) * normalX
                                + (Number(b.vy) - Number(a.vy)) * normalY;
                            if (relative < 0) {
                                const impulse = -(1 + restitution) * relative * 0.5;
                                a.vx = clampedParticleVelocity(Number(a.vx) - impulse * normalX);
                                a.vy = clampedParticleVelocity(Number(a.vy) - impulse * normalY);
                                b.vx = clampedParticleVelocity(Number(b.vx) + impulse * normalX);
                                b.vy = clampedParticleVelocity(Number(b.vy) + impulse * normalY);
                            }
                        }
                    }
                }
            }
        }
        logoParticles = next;
    }

    function stepLogoExplosion() {
        if (!logoSimulationActive)
            return;
        const dt = logoPhysicsIntervalMs / 1000;
        if (logoExplosionActive)
            logoExplosionElapsedMs += logoPhysicsIntervalMs;
        const returning = !logoExplosionActive
            || logoExplosionElapsedMs >= logoExplosionScatterMs;
        const next = ({});
        let maxMotion = 0;
        const hoverLocal = logoHoverActive
            ? wordmarkItem.mapFromItem(root, lastPointerX, lastPointerY)
            : Qt.point(0, 0);
        for (let row = 0; row < wordmarkRows.length; ++row) {
            for (let column = 0; column < wordmarkColumns; ++column) {
                if (!isFilledWordmarkCell(row, column)) continue;
                const key = logoCellKey(row, column);
                const particle = ensureLogoParticle(row, column);
                const hoverTarget = logoHoverTarget(row, column, hoverLocal);
                if (returning) {
                    const spring = logoHoverActive ? 34 : 24;
                    particle.vx += (hoverTarget.x - Number(particle.x || 0)) * spring * dt;
                    particle.vy += (hoverTarget.y - Number(particle.y || 0)) * spring * dt;
                    const damping = Math.exp(-(logoHoverActive ? 10.5 : 7.2) * dt);
                    particle.vx *= damping;
                    particle.vy *= damping;
                } else {
                    const drag = Math.exp(-1.6 * dt);
                    particle.vx *= drag;
                    particle.vy *= drag;
                }
                particle.vx = clampedParticleVelocity(particle.vx);
                particle.vy = clampedParticleVelocity(particle.vy);
                particle.x = Number(particle.x || 0) + particle.vx * dt;
                particle.y = Number(particle.y || 0) + particle.vy * dt;
                bounceLogoParticleAtBounds(particle);
                maxMotion = Math.max(maxMotion,
                    Math.abs(particle.x - hoverTarget.x) + Math.abs(particle.y - hoverTarget.y)
                    + (Math.abs(particle.vx) + Math.abs(particle.vy)) * 0.02);
                next[key] = particle;
            }
        }
        logoParticles = next;
        if (!returning) {
            rebuildLogoBuckets();
            resolveLogoCollisions();
        }
        if (logoExplosionActive && logoExplosionElapsedMs >= logoExplosionMaxMs) {
            logoExplosionActive = false;
            logoExplosionElapsedMs = 0;
            logoParticleBuckets = ({});
        }
        if (returning && maxMotion < 1.2) {
        logoHoverDirty = false;
        if (!logoHoverActive && !logoExplosionActive) {
            logoReturnPending = false;
            logoParticles = ({});
        }
    }
    }

    function updateClockText() {
        const now = new Date();
        timeText = Qt.formatTime(now, root.clockFormat === "12h" ? "h:mm AP" : "HH:mm");
        dateText = Qt.formatDate(now, Locale.LongFormat);
    }

    function pushGhostSample(x, y) {
        const next = [({ x: x, y: y })];
        for (let i = 0; i < ghostTrailLength - 1; ++i)
            next.push(ghostTrail[i] || ({ x: x, y: y }));
        ghostTrail = next;
        ghostHeadX = x;
        ghostHeadY = y;
        ghostFade.stop();
        ghostOpacity = 1;
        cursorFadeDelay.restart();
    }

    function logoContainsPoint(x, y) {
        if (!showLogo)
            return false;
        const logoWidth = root.elementVisualWidth("logo");
        const logoHeight = root.elementVisualHeight("logo");
        const logoCenterX = root.normalizedX("logo", 0.50) * root.width;
        const logoCenterY = root.normalizedY("logo", 0.34) * root.height;
        return x >= logoCenterX - (logoWidth / 2)
            && x <= logoCenterX + (logoWidth / 2)
            && y >= logoCenterY - (logoHeight / 2)
            && y <= logoCenterY + (logoHeight / 2);
    }

    function handlePointerClick(x, y) {
        if (!mouseInteractive)
            return;
        pointerActive = true;
        pushGhostSample(x, y);
        lastPointerX = x;
        lastPointerY = y;
        lastPointerSampleTime = Date.now();
        if (!root.logoContainsPoint(x, y))
            return;
        root.triggerLogoExplosion(x, y);
    }

    function handlePointerMotion(x, y) {
        if (!mouseInteractive)
            return;

        const wasLogoHovering = logoHoverActive;
        pointerActive = true;
        const now = Date.now();
        const hasPrevious = lastPointerX >= 0 && lastPointerY >= 0
            && lastPointerSampleTime > 0;
        const ghostDx = x - ghostHeadX;
        const ghostDy = y - ghostHeadY;
        const ghostDistance = Math.sqrt(ghostDx * ghostDx + ghostDy * ghostDy);

        if (!hasPrevious || ghostOpacity <= 0 || ghostDistance >= pointerMovementThreshold)
            pushGhostSample(x, y);

        lastPointerX = x;
        lastPointerY = y;
        lastPointerSampleTime = now;
        const isLogoHovering = logoContainsPoint(x, y);
        logoHoverDirty = wasLogoHovering || isLogoHovering;
        if (isLogoHovering && !logoExplosionActive)
            logoReturnPending = false;
        else if (wasLogoHovering && !logoExplosionActive)
            logoReturnPending = true;
    }

    function handlePointerExit() {
        if (!mouseInteractive)
            return;
        pointerActive = false;
        lastPointerSampleTime = 0;
        if (!logoExplosionActive) {
            logoReturnPending = true;
            logoHoverDirty = true;
        }
    }
    Item {
        id: backgroundCompositionContent
        anchors.fill: parent

        ShaderEffectSource {
            id: desktopBackingTexture
            anchors.fill: parent
            sourceItem: root.desktopBackingSource
            hideSource: root.desktopBackingSource !== null
            live: true
            recursive: false
            smooth: true
            visible: root.desktopBackingSource !== null
        }

        Item {
            id: backgroundLayer
            anchors.fill: parent
            opacity: Math.max(0, Math.min(100, root.backgroundOpacity)) / 100

            Rectangle {
                anchors.fill: parent
                color: root.backgroundMode === "color" ? root.backgroundColor : "#000000"
            }

            Image {
                id: wallpaperImage
                readonly property var geometry: root.wallpaperGeometry()
                x: geometry.x
                y: geometry.y
                width: geometry.width
                height: geometry.height
                visible: root.backgroundMode === "wallpaper" && root.wallpaperSource.length > 0
                source: root.wallpaperSource
                fillMode: Image.Stretch
                asynchronous: true
                cache: true
            }

            Rectangle {
                id: backgroundOverlay
                anchors.fill: parent
                visible: root.overlayMode !== "none" && root.overlayStrength > 0
                color: root.overlayMode === "light" ? "#ffffff" : "#000000"
                opacity: Math.max(0, Math.min(100, root.overlayStrength)) / 100
            }
        }

        layer.enabled: root.wallpaperBlur > 0
            && root.blurStyle === "smooth"
        layer.effect: MultiEffect {
            autoPaddingEnabled: false
            blurEnabled: true
            blurMax: 32
            blur: Math.max(0, Math.min(1, root.wallpaperBlur / 100))
        }
    }

    ShaderEffectSource {
        id: backgroundCompositionPixelatedBlur
        anchors.fill: parent
        sourceItem: backgroundCompositionContent
        hideSource: root.wallpaperBlur > 0
            && root.blurStyle === "pixelated"
        live: true
        recursive: false
        smooth: false
        readonly property real pixelFactor: 1
            + 63 * Math.pow(Math.max(0, Math.min(1, root.wallpaperBlur / 100)), 1.2)
        textureSize: Qt.size(
            Math.max(1, Math.round(width / pixelFactor)),
            Math.max(1, Math.round(height / pixelFactor)))
        visible: root.wallpaperBlur > 0
            && root.blurStyle === "pixelated"
    }

    Item {
        id: visualLayer
        anchors.fill: parent
        opacity: root.unlocking ? 0 : root.entered ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: root.unlocking ? 160 : 80
                easing.type: Easing.OutCubic
            }
        }

        Repeater {
            id: customImageRepeater
            model: Array.isArray(root.customImages) ? root.customImages : []

            Item {
                id: customImageDelegate
                required property var modelData
                readonly property string elementName: String(modelData.id || "")
                readonly property string spawnMode: root.customImageSpawnMode(modelData)
                readonly property real finalX: root.normalizedX(elementName, 0.50) * parent.width - width / 2
                readonly property real finalY: root.normalizedY(elementName, 0.50) * parent.height - height / 2
                readonly property point spawnOffset: root.customImageSpawnOffset(modelData, width, height)
                property real spawnProgress: spawnMode === "none" ? 1 : 0

                visible: (modelData.visible !== false || root.editorMode)
                    && (spawnMode === "none" || root.customImageEntryStarted)
                width: Math.round(180 * root.uiScale)
                height: Math.round(180 * root.uiScale)
                x: finalX + spawnOffset.x * (1 - spawnProgress)
                y: finalY + spawnOffset.y * (1 - spawnProgress)
                scale: root.elementScale(elementName) * (spawnMode === "pixel-warp" ? 0.82 + 0.18 * spawnProgress : 1)
                rotation: root.elementRotation(elementName)
                transformOrigin: Item.Center
                transform: Scale {
                    origin.x: width / 2
                    origin.y: height / 2
                    xScale: root.elementStretchX(elementName)
                    yScale: root.elementStretchY(elementName)
                }
                opacity: root.elementOpacity(elementName)
                    * (modelData.visible !== false ? 1.0 : root.editorMode ? 0.30 : 0.0)
                    * (spawnMode === "pixel-warp" ? spawnProgress : 1)
                z: 4

                function restartSpawnAnimation() {
                    spawnAnimation.stop();
                    if (spawnMode === "none") { spawnProgress = 1; return; }
                    spawnProgress = 0;
                    spawnAnimation.restart();
                }

                Image {
                    id: customImageSource
                    anchors.fill: parent
                    source: String(customImageDelegate.modelData.path || "").startsWith("/")
                        ? "file://" + String(customImageDelegate.modelData.path) : ""
                    asynchronous: true
                    cache: true
                    fillMode: Image.PreserveAspectFit
                    smooth: customImageDelegate.spawnMode !== "pixel-warp" || customImageDelegate.spawnProgress >= 0.999
                }

                ShaderEffectSource {
                    id: pixelWarpSource
                    anchors.fill: parent
                    sourceItem: customImageSource
                    hideSource: visible
                    live: true
                    recursive: false
                    smooth: false
                    readonly property real pixelFactor: 1 + 31 * Math.pow(Math.max(0, 1 - customImageDelegate.spawnProgress), 1.25)
                    textureSize: Qt.size(Math.max(1, Math.round(width / pixelFactor)), Math.max(1, Math.round(height / pixelFactor)))
                    visible: customImageDelegate.spawnMode === "pixel-warp" && customImageDelegate.spawnProgress < 0.999
                }

                NumberAnimation {
                    id: spawnAnimation
                    target: customImageDelegate
                    property: "spawnProgress"
                    from: 0
                    to: 1
                    duration: customImageDelegate.spawnMode === "pixel-warp" ? 620 : 520
                    easing.type: Easing.OutCubic
                }

                Connections {
                    target: root
                    function onPresentationPhaseChanged() {
                        if (customImageDelegate.spawnMode !== "none"
                                && !root.customImageEntryStarted) {
                            spawnAnimation.stop();
                            customImageDelegate.spawnProgress = 0;
                        }
                    }
                    function onCustomImageSpawnEpochChanged() { customImageDelegate.restartSpawnAnimation(); }
                }
            }
        }

        Item {
            id: visualizerItem
            readonly property bool configuredEnabled: root.visualizer
                && root.visualizer.enabled === true
            readonly property int bandCount: Math.min(64, root.visualizerBandCount())
            readonly property var displayBands: root.visualizerBands()
            readonly property real gapPx: root.visualizerGapPx()
            readonly property string shapeMode: root.visualizerShape()
            readonly property real responseHeight: root.visualizerResponseHeight()
            readonly property real bendAmount: root.visualizerBend()

            visible: configuredEnabled || root.editorMode
            opacity: root.elementOpacity("visualizer")
                * (configuredEnabled ? 1.0 : root.editorMode ? 0.30 : 0.0)
            width: root.visualizerBaseWidth()
            height: root.visualizerBaseHeight()
            x: root.normalizedX("visualizer", 0.50) * parent.width - width / 2
            y: root.normalizedY("visualizer", 0.80) * parent.height - height / 2
            scale: root.elementScale("visualizer")
            transformOrigin: Item.Center
            transform: Scale {
                origin.x: visualizerItem.width / 2
                origin.y: visualizerItem.height / 2
                xScale: root.elementStretchX("visualizer")
                yScale: root.elementStretchY("visualizer")
            }
            z: 8

            Repeater {
                model: visualizerItem.bandCount

                Rectangle {
                    readonly property real amplitude: index < visualizerItem.displayBands.length
                        ? Number(visualizerItem.displayBands[index]) : 0
                    readonly property real safeAmplitude: Number.isFinite(amplitude)
                        ? Math.max(0, Math.min(1, amplitude)) : 0
                    readonly property real availableWidth: Math.max(1,
                        visualizerItem.width - visualizerItem.gapPx
                            * Math.max(0, visualizerItem.bandCount - 1))
                    readonly property real thickness: Math.max(1,
                        availableWidth / Math.max(1, visualizerItem.bandCount))
                    readonly property real barLength: Math.max(2 * root.uiScale,
                        safeAmplitude * visualizerItem.responseHeight)
                    readonly property real unitPosition: visualizerItem.bandCount <= 1 ? 0
                        : index / (visualizerItem.bandCount - 1)
                    readonly property real signedPosition: unitPosition * 2 - 1
                    readonly property real arcOffset: visualizerItem.shapeMode === "arc"
                        ? (1 - signedPosition * signedPosition)
                            * visualizerItem.bendAmount * 0.42 * root.uiScale : 0
                    readonly property real angleRadians: -Math.PI / 2
                        + index * Math.PI * 2 / Math.max(1, visualizerItem.bandCount)
                    readonly property real circleRadius: Math.min(
                        visualizerItem.width, visualizerItem.height) * 0.29

                    width: thickness
                    height: barLength
                    radius: Math.min(width / 2, 2 * root.uiScale)
                    color: root.elementColor("visualizer")
                    antialiasing: true
                    x: visualizerItem.shapeMode === "circle"
                        ? visualizerItem.width / 2 + Math.cos(angleRadians) * circleRadius - width / 2
                        : index * (thickness + visualizerItem.gapPx)
                    y: visualizerItem.shapeMode === "circle"
                        ? visualizerItem.height / 2 + Math.sin(angleRadians) * circleRadius - height / 2
                        : visualizerItem.height - height - arcOffset
                    rotation: visualizerItem.shapeMode === "circle"
                        ? angleRadians * 180 / Math.PI + 90
                        : visualizerItem.shapeMode === "arc"
                            ? -signedPosition * visualizerItem.bendAmount * 0.22 : 0
                    transformOrigin: Item.Center
                }
            }
        }

        Item {
            id: wordmarkItem
            visible: root.presentationVisible("logo", root.showLogo)
                && root.presentationPhase !== "transition"
            opacity: root.presentationOpacity("logo") * root.elementOpacity("logo")
            x: root.normalizedX("logo", 0.50) * parent.width - width / 2
            y: root.normalizedY("logo", 0.34) * parent.height - height / 2
            width: root.wordmarkWidth
            height: root.wordmarkHeight
            scale: root.elementScale("logo")
            transformOrigin: Item.Center
            transform: Scale {
                origin.x: wordmarkItem.width / 2
                origin.y: wordmarkItem.height / 2
                xScale: root.elementStretchX("logo")
                yScale: root.elementStretchY("logo")
            }
            z: 10

            Repeater {
                model: root.wordmarkRows.length

                delegate: Item {
                    id: wordmarkRow
                    readonly property int rowIndex: index
                    readonly property string rowText: root.wordmarkRows[rowIndex]

                    x: 0
                    y: rowIndex * root.wordmarkCellHeight
                    width: root.wordmarkWidth
                    height: root.wordmarkCellHeight

                    Repeater {
                        model: wordmarkRow.rowText.length

                        delegate: Item {
                            id: wordmarkCell

                            readonly property int columnIndex: index
                            property string glyph: wordmarkRow.rowText.charAt(columnIndex)
                            readonly property bool isFilledGlyph: glyph === "█"
                                || glyph === "▄" || glyph === "▀" || glyph === "▐"
                            readonly property int halfWidth: Math.floor(root.wordmarkCellWidth / 2)
                            readonly property int halfHeight: Math.floor(root.wordmarkCellHeight / 2)
                            readonly property real finalGlyphX: glyph === "▐" ? halfWidth : 0
                            readonly property real finalGlyphY: glyph === "▄" ? halfHeight : 0
                            readonly property real finalGlyphWidth: glyph === "▐"
                                ? root.wordmarkCellWidth - halfWidth : root.wordmarkCellWidth
                            readonly property real finalGlyphHeight: glyph === "▄"
                                ? root.wordmarkCellHeight - halfHeight
                                : glyph === "▀" ? halfHeight : root.wordmarkCellHeight
                            readonly property real particleSize: Math.max(3,
                                Math.floor(7 * root.uiScale))
                            readonly property real finalCellX: columnIndex * root.wordmarkCellWidth
                            readonly property real finalCellY: wordmarkRow.rowIndex
                                * root.wordmarkCellHeight
                            readonly property var explosionOffset:
                                root.logoParticleOffset(wordmarkRow.rowIndex, columnIndex)
                            readonly property real randomA: Math.random()
                            readonly property real randomB: Math.random()
                            readonly property real randomC: Math.random()
                            readonly property real randomD: Math.random()
                            readonly property real randomE: Math.random()
                            readonly property real startAngle: randomA * Math.PI * 2
                            readonly property real startDistance: (150 + randomB * 330) * root.uiScale
                            readonly property int edgeSide: Math.floor(randomC * 4)
                            readonly property real edgeMargin: (100 + randomD * 180) * root.uiScale
                            readonly property real jitterX: (randomD - 0.5) * 180 * root.uiScale
                            readonly property real jitterY: (randomE - 0.5) * 130 * root.uiScale
                            readonly property real swarmStartX: Math.cos(startAngle) * startDistance
                            readonly property real swarmStartY: Math.sin(startAngle) * startDistance
                            readonly property real edgeStartX: edgeSide === 0
                                ? -finalCellX - edgeMargin
                                : edgeSide === 1
                                    ? root.wordmarkWidth - finalCellX + edgeMargin
                                    : jitterX
                            readonly property real edgeStartY: edgeSide === 2
                                ? -finalCellY - edgeMargin
                                : edgeSide === 3
                                    ? root.wordmarkHeight - finalCellY + edgeMargin
                                    : jitterY
                            readonly property real centerStartX: root.wordmarkWidth / 2
                                - finalCellX + jitterX * 0.35
                            readonly property real centerStartY: root.wordmarkHeight / 2
                                - finalCellY + jitterY * 0.35
                            readonly property real splitStartX: columnIndex < root.wordmarkColumns / 2
                                ? -finalCellX - edgeMargin
                                : root.wordmarkWidth - finalCellX + edgeMargin
                            readonly property real splitStartY: jitterY
                                + (wordmarkRow.rowIndex % 2 === 0 ? -1 : 1)
                                    * (35 + randomC * 70) * root.uiScale
                            readonly property real startX: root.formationMode === 0
                                ? swarmStartX
                                : root.formationMode === 1
                                    ? edgeStartX
                                    : root.formationMode === 2
                                        ? centerStartX
                                        : splitStartX
                            readonly property real startY: root.formationMode === 0
                                ? swarmStartY
                                : root.formationMode === 1
                                    ? edgeStartY
                                    : root.formationMode === 2
                                        ? centerStartY
                                        : splitStartY
                            readonly property real curveX: (randomC - 0.5)
                                * (root.formationMode === 3 ? 150 : 240) * root.uiScale
                            readonly property real curveY: (randomD - 0.5)
                                * (root.formationMode === 2 ? 100 : 170) * root.uiScale
                            readonly property int formationDelay: Math.floor(Math.random() * 301)
                            readonly property int formationDuration: 1700
                                + Math.floor(Math.random() * 351)
                            property real formationProgress:
                                root.animationPreference === "off"
                                    || (root.previewMode && root.presentationReplayToken === 0) ? 1 : 0

                            x: finalCellX
                                + (1 - formationProgress) * startX
                                + Math.sin(Math.PI * formationProgress) * curveX
                                + explosionOffset.x
                            y: (1 - formationProgress) * startY
                                + Math.sin(Math.PI * formationProgress) * curveY
                                + explosionOffset.y
                            width: root.wordmarkCellWidth
                            height: root.wordmarkCellHeight
                            visible: isFilledGlyph

                            Rectangle {
                                x: (1 - wordmarkCell.formationProgress)
                                    * ((root.wordmarkCellWidth - wordmarkCell.particleSize) / 2)
                                    + wordmarkCell.formationProgress * wordmarkCell.finalGlyphX
                                y: (1 - wordmarkCell.formationProgress)
                                    * ((root.wordmarkCellHeight - wordmarkCell.particleSize) / 2)
                                    + wordmarkCell.formationProgress * wordmarkCell.finalGlyphY
                                width: (1 - wordmarkCell.formationProgress) * wordmarkCell.particleSize
                                    + wordmarkCell.formationProgress * wordmarkCell.finalGlyphWidth
                                height: (1 - wordmarkCell.formationProgress) * wordmarkCell.particleSize
                                    + wordmarkCell.formationProgress * wordmarkCell.finalGlyphHeight
                                color: root.elementColor("logo")
                                opacity: wordmarkCell.formationProgress <= 0 ? 0
                                    : 0.35 + 0.65 * wordmarkCell.formationProgress
                                antialiasing: false
                            }

                            SequentialAnimation {
                                id: formationAnimation
                                PauseAnimation { duration: wordmarkCell.formationDelay }
                                NumberAnimation {
                                    target: wordmarkCell
                                    property: "formationProgress"
                                    from: 0
                                    to: 1
                                    duration: wordmarkCell.formationDuration
                                    easing.type: Easing.OutCubic
                                }
                            }

                            Connections {
                                target: root
                                function onLogoEntryEpochChanged() {
                                    formationAnimation.stop();
                                    if (!wordmarkCell.isFilledGlyph || root.animationPreference === "off") {
                                        wordmarkCell.formationProgress = 1;
                                        return;
                                    }
                                    wordmarkCell.formationProgress = 0;
                                    formationAnimation.restart();
                                }
                            }
                        }
                    }
                }
            }
        }

        Text {
            id: timeItem
            visible: root.presentationVisible("time", root.showTime)
            opacity: root.presentationOpacity("time") * root.elementOpacity("time")
            scale: root.elementScale("time")
            transformOrigin: Item.Center
            transform: Scale {
                origin.x: timeItem.width / 2
                origin.y: timeItem.height / 2
                xScale: root.elementStretchX("time")
                yScale: root.elementStretchY("time")
            }
            z: 10
            x: root.normalizedX("time", 0.50) * parent.width - width / 2
            y: root.normalizedY("time", 0.51) * parent.height - height / 2
            text: root.timeText
            color: root.elementColor("time")
            font.family: root.theme.fontFamily
            font.pixelSize: Math.round(64 * root.uiScale)
            font.weight: Font.Medium
        }

        Text {
            id: dateItem
            visible: root.presentationVisible("date", root.showDate)
            opacity: 0.78 * root.presentationOpacity("date") * root.elementOpacity("date")
            scale: root.elementScale("date")
            transformOrigin: Item.Center
            transform: Scale {
                origin.x: dateItem.width / 2
                origin.y: dateItem.height / 2
                xScale: root.elementStretchX("date")
                yScale: root.elementStretchY("date")
            }
            z: 10
            x: root.normalizedX("date", 0.50) * parent.width - width / 2
            y: root.normalizedY("date", 0.555) * parent.height - height / 2
            text: root.dateText
            color: root.elementColor("date")
            font.family: root.theme.fontFamily
            font.pixelSize: Math.round(22 * root.uiScale)
        }

        Text {
            id: usernameItem
            visible: root.presentationVisible("username", root.showUsername)
            opacity: 0.72 * root.presentationOpacity("username") * root.elementOpacity("username")
            scale: root.elementScale("username")
            transformOrigin: Item.Center
            transform: Scale {
                origin.x: usernameItem.width / 2
                origin.y: usernameItem.height / 2
                xScale: root.elementStretchX("username")
                yScale: root.elementStretchY("username")
            }
            z: 10
            x: root.normalizedX("username", 0.50) * parent.width - width / 2
            y: root.normalizedY("username", 0.595) * parent.height - height / 2
            text: root.usernameText.length > 0 ? root.usernameText : Quickshell.env("USER")
            color: root.elementColor("username")
            font.family: root.theme.fontFamily
            font.pixelSize: Math.round(18 * root.uiScale)
        }

        Text {
            id: weatherItem
            visible: root.presentationVisible("weather", root.showWeather) && root.weatherText.length > 0
            opacity: 0.76 * root.presentationOpacity("weather") * root.elementOpacity("weather")
            scale: root.elementScale("weather")
            transformOrigin: Item.Center
            transform: Scale {
                origin.x: weatherItem.width / 2
                origin.y: weatherItem.height / 2
                xScale: root.elementStretchX("weather")
                yScale: root.elementStretchY("weather")
            }
            z: 10
            x: root.normalizedX("weather", 0.50) * parent.width - width / 2
            y: root.normalizedY("weather", 0.635) * parent.height - height / 2
            text: root.weatherText
            color: root.elementColor("weather")
            font.family: root.theme.fontFamily
            font.pixelSize: Math.round(18 * root.uiScale)
        }

        Item {
            visible: root.previewMode
            x: root.passwordCenterX - width / 2
            y: root.passwordCenterY - height / 2
            width: root.passwordWidth
            height: root.passwordHeight

            Row {
                anchors.centerIn: parent
                spacing: Math.round(7 * root.uiScale * root.elementScale("password"))
                Repeater {
                    model: 4
                    Item {
                        width: root.effectivePasswordMaskMode === "custom"
                            ? Math.round(12 * root.uiScale * root.elementScale("password"))
                            : Math.round(8 * root.uiScale * root.elementScale("password"))
                        height: Math.round(14 * root.uiScale * root.elementScale("password"))
                        Rectangle {
                            anchors.centerIn: parent
                            visible: root.effectivePasswordMaskMode !== "custom"
                            width: root.effectivePasswordMaskMode === "dots"
                                ? Math.round(8 * root.uiScale * root.elementScale("password"))
                                : Math.round(7 * root.uiScale * root.elementScale("password"))
                            height: root.effectivePasswordMaskMode === "dots" ? width
                                : Math.round(10 * root.uiScale * root.elementScale("password"))
                            radius: root.effectivePasswordMaskMode === "dots" ? width / 2 : 0
                            color: root.elementColor("password")
                            opacity: 0.82
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: root.effectivePasswordMaskMode === "custom"
                            text: root.effectivePasswordMaskCharacter
                            color: root.elementColor("password")
                            opacity: 0.82
                            font.family: root.theme.fontFamily
                            font.pixelSize: Math.round(16 * root.uiScale * root.elementScale("password"))
                        }
                    }
                }
            }
        }

        Item {
            anchors.fill: parent
            z: 100
            visible: root.pointerEffectsEnabled && root.ghostOpacity > 0

            Repeater {
                model: root.ghostTrailLength
                Rectangle {
                    required property int index
                    readonly property var sample: root.ghostTrail[index]
                    readonly property real scaleFactor: 1 - index / root.ghostTrailLength
                    width: Math.max(3, Math.round((7 * scaleFactor) * root.uiScale))
                    height: width
                    radius: width / 2
                    x: Number(sample.x) - width / 2
                    y: Number(sample.y) - height / 2
                    color: root.theme.lockAccent
                    opacity: root.ghostOpacity * 0.34 * scaleFactor
                }
            }

            Rectangle {
                width: Math.round(18 * root.uiScale)
                height: width
                radius: width / 2
                x: root.ghostHeadX - width / 2
                y: root.ghostHeadY - height / 2
                color: root.theme.lockAccent
                opacity: root.ghostOpacity * 0.12
            }

            Rectangle {
                width: Math.round(8 * root.uiScale)
                height: width
                radius: width / 2
                x: root.ghostHeadX - width / 2
                y: root.ghostHeadY - height / 2
                color: root.theme.lockAccent
                opacity: root.ghostOpacity * 0.78
            }
        }
    }
    Timer {
        id: cursorFadeDelay
        interval: root.cursorFadeDelayMs
        repeat: false
        onTriggered: ghostFade.restart()
    }

    NumberAnimation {
        id: ghostFade
        target: root
        property: "ghostOpacity"
        to: 0
        duration: root.cursorFadeDurationMs
        easing.type: Easing.OutCubic
        onFinished: root.pointerActive = false
    }

    Timer {
        id: logoPhysicsTimer
        interval: root.logoPhysicsIntervalMs
        repeat: true
        running: root.logoSimulationActive
        onTriggered: root.stepLogoExplosion()
    }

    Timer {
        id: logoEntryPhaseTimer
        interval: root.logoEntryDurationMs
        repeat: false
        onTriggered: root.beginCustomImageEntry()
    }

    Timer {
        id: customImageEntryPhaseTimer
        interval: 620
        repeat: false
        onTriggered: root.presentationPhase = "settled"
    }

    Timer {
        interval: 15000
        repeat: true
        triggeredOnStart: true
        running: root.showTime || root.showDate
        onTriggered: root.updateClockText()
    }

    Component.onCompleted: {
        root.updateClockText();
        root.entered = true;
        if (root.previewMode && root.presentationReplayToken === 0)
            root.presentationPhase = "settled";
        else if (!root.effectiveEntryTransitionRunning)
            Qt.callLater(root.beginLogoEntry);
    }
}
