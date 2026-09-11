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
    required property var autoAccents
    required property var layout

    property bool previewMode: false
    property bool editorMode: false
    property var editorVisibility: ({})
    property string editorHeldElement: ""
    property real editorHoldScale: 1.0
    property bool unlocking: false
    property bool entered: false

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
    readonly property string usernameText: showUsername ? Quickshell.env("USER") : "";
    readonly property real passwordCenterX: normalizedX("password", 0.50) * width
    readonly property real passwordCenterY: normalizedY("password", 0.70) * height
    readonly property real passwordWidth: Math.round(420 * uiScale * elementScale("password"))
    readonly property real passwordHeight: Math.round(58 * uiScale * elementScale("password"))

    property bool pointerActive: false
    property bool logoExplosionActive: false
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
    property string timeText: ""
    property string dateText: "";

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

    function normalizedX(name, fallback) {
        const point = normalizedPoint(name);
        const value = point ? Number(point.x) : Number.NaN;
        return Number.isFinite(value) ? Math.max(0, Math.min(1, value)) : fallback;
    }

    function normalizedY(name, fallback) {
        const point = normalizedPoint(name);
        const value = point ? Number(point.y) : Number.NaN;
        return Number.isFinite(value) ? Math.max(0, Math.min(1, value)) : fallback;
    }

    function elementScale(name) {
        const point = normalizedPoint(name);
        const value = point ? Number(point.scale === undefined ? 1 : point.scale) : 1;
        const baseScale = Number.isFinite(value) ? Math.max(0.50, Math.min(2.00, value)) : 1;
        const holdScale = root.editorMode && name === editorHeldElement ? editorHoldScale : 1.0;
        const safeHoldScale = Number.isFinite(Number(holdScale))
            ? Math.max(1.0, Math.min(1.12, Number(holdScale))) : 1.0;
        return baseScale * safeHoldScale;
    }

    function elementColor(name) {
        const point = normalizedPoint(name);
        const value = String(point && point.color !== undefined ? point.color : "auto");
        const automatic = String(root.autoAccents && root.autoAccents[name] !== undefined
            ? root.autoAccents[name] : "#ffffff");
        const safeAuto = /^#[0-9a-fA-F]{6}$/.test(automatic) ? automatic : "#ffffff";
        return value === "auto" ? safeAuto
            : /^#[0-9a-fA-F]{6}$/.test(value) ? value : safeAuto;
    }

    function presentationVisible(name, configuredVisible) {
        return configuredVisible || root.editorMode;
    }

    function presentationOpacity(name) {
        return root.editorMode && root.editorVisibility[name] === false ? 0.30 : 1.0;
    }

    function elementVisualWidth(name) {
        if (name === "logo") return root.wordmarkWidth * root.elementScale("logo");
        if (name === "time") return timeItem.implicitWidth * root.elementScale("time");
        if (name === "date") return dateItem.implicitWidth * root.elementScale("date");
        if (name === "username") return usernameItem.implicitWidth * root.elementScale("username");
        if (name === "weather") return weatherItem.implicitWidth * root.elementScale("weather");
        if (name === "password") return root.passwordWidth;
        return 48 * root.uiScale;
    }

    function elementVisualHeight(name) {
        if (name === "logo") return root.wordmarkHeight * root.elementScale("logo");
        if (name === "time") return timeItem.implicitHeight * root.elementScale("time");
        if (name === "date") return dateItem.implicitHeight * root.elementScale("date");
        if (name === "username") return usernameItem.implicitHeight * root.elementScale("username");
        if (name === "weather") return weatherItem.implicitHeight * root.elementScale("weather");
        if (name === "password") return root.passwordHeight;
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
                const previous = logoParticles[key];
                const particle = previous ? Object.assign({}, previous) : ({
                    row: row,
                    column: column,
                    x: 0,
                    y: 0,
                    vx: 0,
                    vy: 0
                });
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
            const members = buckets[bucketKey] ? buckets[bucketKey].slice() : [];
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
        if (!logoExplosionActive)
            return;
        const dt = logoPhysicsIntervalMs / 1000;
        logoExplosionElapsedMs += logoPhysicsIntervalMs;
        const returning = logoExplosionElapsedMs >= logoExplosionScatterMs;
        const next = ({});
        let maxMotion = 0;
        for (const key in logoParticles) {
            const particle = Object.assign({}, logoParticles[key]);
            if (returning) {
                const spring = 28;
                particle.vx += -Number(particle.x || 0) * spring * dt;
                particle.vy += -Number(particle.y || 0) * spring * dt;
                const damping = Math.exp(-8.4 * dt);
                particle.vx *= damping;
                particle.vy *= damping;
            } else {
                const drag = Math.exp(-1.6 * dt);
                particle.vx *= drag;
                particle.vy *= drag;
            }
            particle.vx = clampedParticleVelocity(particle.vx);
            particle.vy = clampedParticleVelocity(particle.vy);
            particle.x = Math.max(-logoExplosionOffsetCap,
                Math.min(logoExplosionOffsetCap, Number(particle.x || 0) + particle.vx * dt));
            particle.y = Math.max(-logoExplosionOffsetCap,
                Math.min(logoExplosionOffsetCap, Number(particle.y || 0) + particle.vy * dt));
            maxMotion = Math.max(maxMotion,
                Math.abs(particle.x) + Math.abs(particle.y)
                + (Math.abs(particle.vx) + Math.abs(particle.vy)) * 0.02);
            next[key] = particle;
        }
        logoParticles = next;
        if (!returning) {
            rebuildLogoBuckets();
            resolveLogoCollisions();
        }
        if (logoExplosionElapsedMs >= logoExplosionMaxMs
                || (returning && maxMotion < 2.2)) {
            logoExplosionActive = false;
            logoExplosionElapsedMs = 0;
            logoParticles = ({});
            logoParticleBuckets = ({});
        }
    }

    function minuteTimeFormat() {
        const localeFormat = String(Qt.locale().timeFormat(Locale.ShortFormat) || "");
        const withoutSeconds = localeFormat
            .replace(/([:.\-\s])s{1,2}(?:\.z{1,3})?/g, "")
            .replace(/s{1,2}([:.\-\s])/g, "")
            .replace(/z{1,3}/g, "")
            .replace(/\s{2,}/g, " ")
            .trim();
        return withoutSeconds.length > 0 ? withoutSeconds : "HH:mm";
    }

    function updateClockText() {
        const now = new Date();
        timeText = Qt.formatTime(now, minuteTimeFormat());
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

    function handlePointerClick(x, y) {
        if (!mouseInteractive)
            return;
        pointerActive = true;
        pushGhostSample(x, y);
        root.triggerLogoExplosion(x, y);
        lastPointerX = x;
        lastPointerY = y;
        lastPointerSampleTime = Date.now();
    }

    function handlePointerMotion(x, y) {
        if (!mouseInteractive)
            return;

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
    }
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
        visible: false
        source: root.wallpaperSource
        fillMode: Image.Stretch
        asynchronous: true
        cache: true
    }

    MultiEffect {
        x: wallpaperImage.x
        y: wallpaperImage.y
        width: wallpaperImage.width
        height: wallpaperImage.height
        visible: root.backgroundMode === "wallpaper" && root.wallpaperSource.length > 0
        source: wallpaperImage
        autoPaddingEnabled: false
        blurEnabled: root.wallpaperBlur > 0
        blurMax: 32
        blur: Math.max(0, Math.min(1, root.wallpaperBlur / 100))
    }

    Rectangle {
        id: backgroundOverlay
        anchors.fill: parent
        visible: root.overlayMode !== "none" && root.overlayStrength > 0
        color: root.overlayMode === "light" ? "#ffffff" : "#000000"
        opacity: Math.max(0, Math.min(100, root.overlayStrength)) / 100
    }

    Item {
        id: visualLayer
        anchors.fill: parent
        opacity: root.unlocking ? 0 : root.entered ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: root.unlocking ? 160 : 220
                easing.type: Easing.OutCubic
            }
        }

        Item {
            id: wordmarkItem
            visible: root.presentationVisible("logo", root.showLogo)
            opacity: root.presentationOpacity("logo")
            x: root.normalizedX("logo", 0.50) * parent.width - width / 2
            y: root.normalizedY("logo", 0.34) * parent.height - height / 2
            width: root.wordmarkWidth
            height: root.wordmarkHeight
            scale: root.elementScale("logo")
            transformOrigin: Item.Center

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
                                root.animationPreference === "off" ? 1 : 0


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

                            SequentialAnimation on formationProgress {
                                running: wordmarkCell.isFilledGlyph
                                    && root.entered && !root.unlocking
                                    && root.animationPreference !== "off"

                                PauseAnimation { duration: wordmarkCell.formationDelay }
                                NumberAnimation {
                                    from: 0
                                    to: 1
                                    duration: wordmarkCell.formationDuration
                                    easing.type: Easing.OutCubic
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
            opacity: root.presentationOpacity("time")
            scale: root.elementScale("time")
            transformOrigin: Item.Center
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
            opacity: 0.78 * root.presentationOpacity("date")
            scale: root.elementScale("date")
            transformOrigin: Item.Center
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
            opacity: 0.72 * root.presentationOpacity("username")
            scale: root.elementScale("username")
            transformOrigin: Item.Center
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
            opacity: 0.76 * root.presentationOpacity("weather")
            scale: root.elementScale("weather")
            transformOrigin: Item.Center
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

            Rectangle {
                anchors.centerIn: parent
                width: Math.round(80 * root.uiScale * root.elementScale("password"))
                height: Math.round(14 * root.uiScale * root.elementScale("password"))
                color: root.elementColor("password")
                opacity: 0.09
            }

            Row {
                anchors.centerIn: parent
                spacing: Math.round(7 * root.uiScale * root.elementScale("password"))
                Repeater {
                    model: 4
                    Rectangle {
                        width: Math.round(7 * root.uiScale * root.elementScale("password"))
                        height: Math.round(10 * root.uiScale * root.elementScale("password"))
                        color: root.elementColor("password")
                        opacity: 0.82
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
        running: root.logoExplosionActive
        onTriggered: root.stepLogoExplosion()
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
    }
}
