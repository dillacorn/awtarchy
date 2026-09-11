#!/usr/bin/env python3
from pathlib import Path
import hashlib
import re

ROOT = Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


def write(path, text):
    (ROOT / path).write_text(text, encoding="utf-8")


def replace_once(path, old, new):
    text = read(path)
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected exactly one literal match, found {count}: {old[:120]!r}")
    write(path, text.replace(old, new, 1))


def replace_re_once(path, pattern, replacement):
    text = read(path)
    next_text, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise SystemExit(f"{path}: expected exactly one regex match, found {count}: {pattern[:120]!r}")
    write(path, next_text)


APP = "config/hypr/scripts/quickshell_application_state.sh"
BAR = "config/quickshell/awtarchy/BarState.qml"
QS = "config/quickshell/awtarchy/QuickSettings.qml"
PICKER = "config/hypr/scripts/quickshell_lockscreen_wallpaper_picker.sh"
SURFACE = "config/quickshell/awtarchy-lock/LockSurface.qml"
SHELL = "config/quickshell/awtarchy-lock/shell.qml"
SCENE = "config/quickshell/awtarchy-lock/LockScene.qml"
PREVIEW = "config/quickshell/awtarchy/LockPreviewScene.qml"
EDITOR = "config/quickshell/awtarchy/LockscreenEditor.qml"

# ---------------------------------------------------------------------------
# Persistent 30 / 60 / 90 Hz logo physics preference.
# ---------------------------------------------------------------------------
replace_once(APP, '''set_lockscreen_animation() {
    local value="$1"
    validate_lockscreen_animation "$value"
    new_tmp
    jq --arg value "$value" '.lockscreen_animation = $value' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

set_lockscreen_option() {''', '''set_lockscreen_animation() {
    local value="$1"
    validate_lockscreen_animation "$value"
    new_tmp
    jq --arg value "$value" '.lockscreen_animation = $value' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

set_lockscreen_logo_physics_hz() {
    local value="$1"
    case "$value" in
        30|60|90) ;;
        *)
            printf 'lockscreen logo physics Hz must be 30, 60, or 90\\n' >&2
            exit 2
            ;;
    esac
    new_tmp
    jq --argjson value "$value" '.lockscreen_logo_physics_hz = $value' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}

set_lockscreen_option() {''')
replace_once(APP, '''        .lockscreen_animation = "split"
        | .lockscreen_audio_reactive = true''', '''        .lockscreen_animation = "split"
        | .lockscreen_logo_physics_hz = 30
        | .lockscreen_audio_reactive = true''')
replace_once(APP, '''    set-lockscreen-animation)
        [[ -n ${2:-} ]] || exit 2
        set_lockscreen_animation "$2"
        ;;
    set-lockscreen-audio-reactive)''', '''    set-lockscreen-animation)
        [[ -n ${2:-} ]] || exit 2
        set_lockscreen_animation "$2"
        ;;
    set-lockscreen-logo-physics-hz)
        [[ -n ${2:-} ]] || exit 2
        set_lockscreen_logo_physics_hz "$2"
        ;;
    set-lockscreen-audio-reactive)''')
replace_once(APP,
    'set-lockscreen-animation <random|swarm|edges|center|split|off>|set-lockscreen-audio-reactive <true|false>',
    'set-lockscreen-animation <random|swarm|edges|center|split|off>|set-lockscreen-logo-physics-hz <30|60|90>|set-lockscreen-audio-reactive <true|false>')

replace_once(BAR, '''            lockscreen_animation: "split",
            lockscreen_audio_reactive: true,''', '''            lockscreen_animation: "split",
            lockscreen_logo_physics_hz: 30,
            lockscreen_audio_reactive: true,''')
replace_once(BAR, '''    function lockscreenBooleanPreference(field, fallback) {
        const value = data()[field];
        return typeof value === "boolean" ? value : fallback;
    }

    function lockscreenAudioReactiveEnabled() {''', '''    function lockscreenBooleanPreference(field, fallback) {
        const value = data()[field];
        return typeof value === "boolean" ? value : fallback;
    }

    function lockscreenLogoPhysicsHz() {
        const value = Math.round(Number(data().lockscreen_logo_physics_hz));
        return [30, 60, 90].indexOf(value) >= 0 ? value : 30;
    }

    function lockscreenAudioReactiveEnabled() {''')

# Quick Settings retires logo audio movement and exposes explicit physics rates.
old_effect_grid = '''                                    GridLayout {
                                        Layout.fillWidth: true
                                        columns: 2
                                        columnSpacing: 8
                                        rowSpacing: 4

                                        Text { Layout.fillWidth: true; text: "Mouse Interaction"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: root.scaledText(9) }
                                        SettingsButton { label: BarState.lockscreenMouseInteractiveEnabled() ? "On" : "Off"; active: BarState.lockscreenMouseInteractiveEnabled(); textSize: root.scaledText(9); onClicked: root.queueStateCommand(["set-lockscreen-mouse-interactive", BarState.lockscreenMouseInteractiveEnabled() ? "false" : "true"]) }
                                        Text { Layout.fillWidth: true; text: "Audio Reactive"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: root.scaledText(9) }
                                        SettingsButton { label: BarState.lockscreenAudioReactiveEnabled() ? "On" : "Off"; active: BarState.lockscreenAudioReactiveEnabled(); textSize: root.scaledText(9); onClicked: root.queueStateCommand(["set-lockscreen-audio-reactive", BarState.lockscreenAudioReactiveEnabled() ? "false" : "true"]) }
                                    }'''
new_effect_grid = '''                                    GridLayout {
                                        Layout.fillWidth: true
                                        columns: 2
                                        columnSpacing: 8
                                        rowSpacing: 4

                                        Text { Layout.fillWidth: true; text: "Mouse Interaction"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: root.scaledText(9) }
                                        SettingsButton { label: BarState.lockscreenMouseInteractiveEnabled() ? "On" : "Off"; active: BarState.lockscreenMouseInteractiveEnabled(); textSize: root.scaledText(9); onClicked: root.queueStateCommand(["set-lockscreen-mouse-interactive", BarState.lockscreenMouseInteractiveEnabled() ? "false" : "true"]) }
                                        Text { Layout.fillWidth: true; text: "Logo Physics"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: root.scaledText(9) }
                                        RowLayout {
                                            spacing: 5
                                            SettingsButton { label: "30 Hz"; active: BarState.lockscreenLogoPhysicsHz() === 30; textSize: root.scaledText(9); onClicked: root.queueStateCommand(["set-lockscreen-logo-physics-hz", "30"]) }
                                            SettingsButton { label: "60 Hz"; active: BarState.lockscreenLogoPhysicsHz() === 60; textSize: root.scaledText(9); onClicked: root.queueStateCommand(["set-lockscreen-logo-physics-hz", "60"]) }
                                            SettingsButton { label: "90 Hz"; active: BarState.lockscreenLogoPhysicsHz() === 90; textSize: root.scaledText(9); onClicked: root.queueStateCommand(["set-lockscreen-logo-physics-hz", "90"]) }
                                        }
                                    }'''
replace_once(QS, old_effect_grid, new_effect_grid)

# ---------------------------------------------------------------------------
# Fullscreen Awtwall handoff for the standard Alacritty picker.
# ---------------------------------------------------------------------------
replace_once(PICKER, '''"$TERMINAL_CMD" --class awtarchy-lock-wallpaper -e "$awtwall_path" --select-only --type images --resume --select-result "$RESULT_FILE"

if [[ ! -s "$RESULT_FILE" ]]; then''', '''terminal_name="$(basename -- "$TERMINAL_CMD")"
if [[ "$terminal_name" == "alacritty" ]]; then
    "$TERMINAL_CMD" --option window.startup_mode=Fullscreen \\
        --class awtarchy-lock-wallpaper -e "$awtwall_path" \\
        --select-only --type images --resume --select-result "$RESULT_FILE"
else
    "$TERMINAL_CMD" --class awtarchy-lock-wallpaper -e "$awtwall_path" \\
        --select-only --type images --resume --select-result "$RESULT_FILE"
fi

if [[ ! -s "$RESULT_FILE" ]]; then''')

# ---------------------------------------------------------------------------
# Secure shell/surface: logo physics rate replaces logo audio deformation.
# ---------------------------------------------------------------------------
replace_once(SURFACE, '''    required property string animationPreference
    required property int randomFormationMode
    required property bool audioReactive
    required property real audioLow
    required property real audioMid
    required property real audioHigh
    required property real audioOverall
    required property bool mouseInteractive''', '''    required property string animationPreference
    required property int randomFormationMode
    required property int logoPhysicsHz
    required property bool mouseInteractive''')
replace_once(SURFACE, '''        animationPreference: root.animationPreference
        randomFormationMode: root.randomFormationMode
        audioReactive: root.audioReactive
        audioLow: root.audioLow
        audioMid: root.audioMid
        audioHigh: root.audioHigh
        audioOverall: root.audioOverall
        mouseInteractive: root.mouseInteractive''', '''        animationPreference: root.animationPreference
        randomFormationMode: root.randomFormationMode
        logoPhysicsHz: root.logoPhysicsHz
        mouseInteractive: root.mouseInteractive''')

replace_once(SHELL, '''    property string lockAnimationPreference: "split"
    property bool lockAudioReactive: true
    property bool lockMouseInteractive: true''', '''    property string lockAnimationPreference: "split"
    property int lockLogoPhysicsHz: 30
    property bool lockMouseInteractive: true''')
replace_once(SHELL, '''    function normalizedBoolean(value, fallback) {
        return typeof value === "boolean" ? value : fallback;
    }''', '''    function normalizedLogoPhysicsHz(value) {
        const numeric = Math.round(Number(value));
        return [30, 60, 90].indexOf(numeric) >= 0 ? numeric : 30;
    }

    function normalizedBoolean(value, fallback) {
        return typeof value === "boolean" ? value : fallback;
    }''')
replace_once(SHELL, '''        lockAnimationPreference = "split";
        lockAudioReactive = true;
        lockMouseInteractive = true;''', '''        lockAnimationPreference = "split";
        lockLogoPhysicsHz = 30;
        lockMouseInteractive = true;''')
replace_once(SHELL, '''            lockAnimationPreference = normalizedAnimationPreference(parsed.lockscreen_animation);
            lockAudioReactive = normalizedBoolean(parsed.lockscreen_audio_reactive, true);
            lockMouseInteractive = normalizedBoolean(parsed.lockscreen_mouse_interactive, true);''', '''            lockAnimationPreference = normalizedAnimationPreference(parsed.lockscreen_animation);
            lockLogoPhysicsHz = normalizedLogoPhysicsHz(parsed.lockscreen_logo_physics_hz);
            lockMouseInteractive = normalizedBoolean(parsed.lockscreen_mouse_interactive, true);''')
replace_once(SHELL, '''    LockAudioAnalyzer {
        id: lockAudioAnalyzer
        enabled: root.lockAudioReactive
    }

''', '')
replace_once(SHELL, '''                animationPreference: root.lockAnimationPreference
                randomFormationMode: root.randomFormationMode
                audioReactive: root.lockAudioReactive
                audioLow: lockAudioAnalyzer.low
                audioMid: lockAudioAnalyzer.mid
                audioHigh: lockAudioAnalyzer.high
                audioOverall: lockAudioAnalyzer.overall
                mouseInteractive: root.lockMouseInteractive''', '''                animationPreference: root.lockAnimationPreference
                randomFormationMode: root.randomFormationMode
                logoPhysicsHz: root.lockLogoPhysicsHz
                mouseInteractive: root.lockMouseInteractive''')

# ---------------------------------------------------------------------------
# Shared presentation scene: active-only explosion physics.  No audio or hover
# deformation touches the logo while idle or during ordinary pointer movement.
# ---------------------------------------------------------------------------
replace_once(SCENE, '''    required property string animationPreference
    required property int randomFormationMode
    required property bool audioReactive
    required property real audioLow
    required property real audioMid
    required property real audioHigh
    required property real audioOverall
    required property bool mouseInteractive''', '''    required property string animationPreference
    required property int randomFormationMode
    required property int logoPhysicsHz
    required property bool mouseInteractive''')

replace_re_once(SCENE,
    r'''    readonly property real audioLevel: audioOverall\n.*?    readonly property string usernameText: showUsername \? Quickshell\.env\("USER"\) : "";''',
    '''    readonly property bool pointerEffectsEnabled: mouseInteractive && pointerActive
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
    readonly property string usernameText: showUsername ? Quickshell.env("USER") : "";''')

replace_re_once(SCENE,
    r'''    property bool pointerActive: false\n.*?    property string dateText: "";''',
    '''    property bool pointerActive: false
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
    property string dateText: "";''')

physics_functions = r'''    function logoCellKey(row, column) {
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
        const margin = 90 * uiScale;
        if (local.x < -margin || local.y < -margin
                || local.x > wordmarkWidth + margin
                || local.y > wordmarkHeight + margin)
            return;

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
'''
replace_re_once(SCENE,
    r'''    function logoCellKey\(row, column\) \{.*?\n    function minuteTimeFormat\(\) \{''',
    physics_functions + '''
    function minuteTimeFormat() {''')

replace_re_once(SCENE,
    r'''    function updatePointerField\(x, y, speed\) \{.*?\n    NumberAnimation \{\n        id: clickFieldDecay.*?\n    \}\n''',
    '''    function handlePointerClick(x, y) {
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
''')

replace_re_once(SCENE,
    r'''                            readonly property var cohesionGroup: isFilledGlyph.*?                            readonly property real combinedOffsetY:.*?\n                                    pointerOffsetY \+ audioOffsetY\)\)\n''',
    '''                            readonly property var explosionOffset:
                                root.logoParticleOffset(wordmarkRow.rowIndex, columnIndex)
''')
replace_re_once(SCENE,
    r'''\n                            Component\.onCompleted: \{\n                                if \(wordmarkCell\.isFilledGlyph\).*?\n                            \}\n''', '\n')
replace_once(SCENE, '                                + combinedOffsetX', '                                + explosionOffset.x')
replace_once(SCENE, '                                + combinedOffsetY', '                                + explosionOffset.y')
replace_re_once(SCENE,
    r'''\n                            Behavior on pointerOffsetX \{.*?\n                            \}\n\n                            Behavior on pointerOffsetY \{.*?\n                            \}\n''', '\n')
replace_re_once(SCENE,
    r'''    Timer \{\n        interval: 33\n        repeat: true\n        running: root\.audioEffectsEnabled\n        onTriggered: \{\n            root\.audioPhase \+= 0\.22;\n        \}\n    \}''',
    '''    Timer {
        id: logoPhysicsTimer
        interval: root.logoPhysicsIntervalMs
        repeat: true
        running: root.logoExplosionActive
        onTriggered: root.stepLogoExplosion()
    }''')

# Copy exact secure scene bytes into editor config root.
write(PREVIEW, read(SCENE))

# ---------------------------------------------------------------------------
# Editor runtime shortcut ownership, direct pointer scaling, and color affordance.
# ---------------------------------------------------------------------------
replace_once(EDITOR, '''    property real guideX: -1
    property real guideY: -1
    property string inertiaOwner: ""
''', '''    property real guideX: -1
    property real guideY: -1
    property string inertiaOwner: ""
    property string resizeElementName: ""
    property real resizeStartDistance: 1
    property real resizeStartScale: 1
    property real resizeCenterX: 0
    property real resizeCenterY: 0
''')
replace_once(EDITOR, '''    function pointBounds(name) {
        const password = name === "password";
''', '''    function setDraftScaleSilently(name, scaleValue) {
        if (elementNames.indexOf(name) < 0)
            return;
        const numeric = Number(scaleValue);
        if (!Number.isFinite(numeric))
            return;
        const next = cloneLayout(draftLayout);
        next[name].scale = Math.max(0.50, Math.min(2.00, numeric));
        draftLayout = next;
        scheduleContrastRefresh();
    }

    function beginResizeElement(name, sceneX, sceneY) {
        if (elementNames.indexOf(name) < 0 || editorFocus.width <= 0 || editorFocus.height <= 0)
            return;
        selectElement(name, false);
        const point = draftLayout[name] || defaultLayout()[name];
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

    function pointBounds(name) {
        const password = name === "password";
''')

# Remove singleton-owned undo shortcuts, then add window-owned versions.
replace_re_once(EDITOR,
    r'''\n    Shortcut \{\n        sequence: "Ctrl\+Z".*?\n    \}\n\n    Shortcut \{\n        sequence: "Ctrl\+Shift\+Z".*?\n    \}\n\n    Shortcut \{\n        sequence: "Ctrl\+Y".*?\n    \}\n''', '\n')
replace_once(EDITOR, '''        implicitWidth: Math.max(1, screen ? screen.width : 1920)
        implicitHeight: Math.max(1, screen ? screen.height : 1080)

        Rectangle {''', '''        implicitWidth: Math.max(1, screen ? screen.width : 1920)
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

        Rectangle {''')
replace_once(EDITOR, '''                randomFormationMode: 3
                audioReactive: false
                audioLow: 0
                audioMid: 0
                audioHigh: 0
                audioOverall: 0
                mouseInteractive: BarState.lockscreenMouseInteractiveEnabled()''', '''                randomFormationMode: 3
                logoPhysicsHz: BarState.lockscreenLogoPhysicsHz()
                mouseInteractive: BarState.lockscreenMouseInteractiveEnabled()''')

resize_handle = '''
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
'''
replace_once(EDITOR, '''                    Timer {
                        id: inertiaTimer''', resize_handle + '''
                    Timer {
                        id: inertiaTimer''')

color_button = '''
                        SettingsButton {
                            id: selectedElementColorButton
                            label: root.elementColor(root.selectedElement) === "auto"
                                ? "Color: Auto" : "Color: " + root.elementColor(root.selectedElement)
                            textSize: 9
                            onClicked: {
                                if (root.activeDrawer !== "element")
                                    root.toggleDrawer("element");
                                root.elementPaletteOpen = true;
                            }
                        }
'''
replace_once(EDITOR, '''                        SettingsButton { label: "Undo"; textSize: 9; available: root.undoStack.length > 0; onClicked: root.undo() }''', color_button + '''
                        SettingsButton { label: "Undo"; textSize: 9; available: root.undoStack.length > 0; onClicked: root.undo() }''')

# ---------------------------------------------------------------------------
# Focused tests updated to the approved click-only model.
# ---------------------------------------------------------------------------
logo_test = r'''#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCENE="${ROOT}/config/quickshell/awtarchy-lock/LockScene.qml"
PREVIEW="${ROOT}/config/quickshell/awtarchy/LockPreviewScene.qml"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
require_text() { grep -Fq -- "$2" "$1" || fail "$3"; }
reject_text() { if grep -Fq -- "$2" "$1"; then fail "$3"; fi; }

[[ -f "$SCENE" ]] || fail 'secure lock scene is missing'
[[ -f "$PREVIEW" ]] || fail 'desktop lock preview scene is missing'

for forbidden in logoBridgeCanvas logoBridgePairs buildLogoBridgePairs \
    pointerFieldX pointerFieldY pointerFieldStrength updatePointerField \
    directCellDeformationOffset neighborCellDeformationOffset logoCellDeformationOffset \
    logoGroupAudioOffset combinedOffsetX combinedOffsetY audioPhase; do
    reject_text "$SCENE" "$forbidden" "retired continuous logo deformation remains: $forbidden"
done

require_text "$SCENE" 'property bool logoExplosionActive: false' \
    'logo has no active-only explosion state'
require_text "$SCENE" 'property var logoParticles: ({})' \
    'logo has no particle state'
require_text "$SCENE" 'function triggerLogoExplosion(x, y)' \
    'logo has no click explosion entrypoint'
require_text "$SCENE" 'function rebuildLogoBuckets()' \
    'logo collision path has no spatial buckets'
require_text "$SCENE" 'function resolveLogoCollisions()' \
    'logo has no bounded local collision resolver'
require_text "$SCENE" 'function stepLogoExplosion()' \
    'logo has no explosion simulation step'
require_text "$SCENE" 'id: logoPhysicsTimer' \
    'logo has no shared physics timer'
require_text "$SCENE" 'running: root.logoExplosionActive' \
    'logo physics does not stop while idle'
require_text "$SCENE" 'readonly property var explosionOffset:' \
    'wordmark blocks do not read active explosion offsets'
require_text "$SCENE" '+ explosionOffset.x' \
    'wordmark X position does not consume explosion physics'
require_text "$SCENE" '+ explosionOffset.y' \
    'wordmark Y position does not consume explosion physics'

cmp -s "$SCENE" "$PREVIEW" \
    || fail 'secure lock scene and desktop preview scene diverge'

printf '%s\n' 'PASS: lockscreen click-only block explosion contracts'
'''
write("tests/test-quickshell-lockscreen-logo-cohesion.sh", logo_test)

physics_test = r'''#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCENE_QML="${ROOT}/config/quickshell/awtarchy-lock/LockScene.qml"
AUDIO_QML="${ROOT}/config/quickshell/awtarchy-lock/LockAudioAnalyzer.qml"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
require_text() { grep -Fq -- "$2" "$1" || fail "$3"; }
reject_text() { if grep -Fq -- "$2" "$1"; then fail "$3"; fi; }

require_text "$SCENE_QML" 'const ghostDx = x - ghostHeadX;' \
    'ghost sampling does not accumulate movement from the rendered head'
require_text "$SCENE_QML" 'const ghostDy = y - ghostHeadY;' \
    'ghost sampling does not accumulate vertical movement from the rendered head'
require_text "$SCENE_QML" 'const ghostDistance = Math.sqrt(ghostDx * ghostDx + ghostDy * ghostDy);' \
    'ghost sampling has no cumulative movement distance'
require_text "$SCENE_QML" 'ghostDistance >= pointerMovementThreshold' \
    'ghost sampling still thresholds only individual raw mouse events'

require_text "$SCENE_QML" 'logoPhysicsHz >= 90 ? 11' \
    '90 Hz mode does not reduce the active simulation interval'
require_text "$SCENE_QML" 'logoPhysicsHz >= 60 ? 17 : 33' \
    '30/60 Hz active simulation intervals are missing'
require_text "$SCENE_QML" 'running: root.logoExplosionActive' \
    'logo physics timer is not strictly active-only'
require_text "$SCENE_QML" 'logoExplosionElapsedMs >= logoExplosionScatterMs' \
    'explosion has no scatter-to-return phase boundary'
require_text "$SCENE_QML" 'particle.vx += -Number(particle.x || 0) * spring * dt;' \
    'return phase does not spring blocks toward home'
require_text "$SCENE_QML" 'logoParticleBuckets' \
    'collision system does not use spatial buckets'
reject_text "$SCENE_QML" 'audioEffectsEnabled' \
    'logo physics still carries audio-reactive gating'
reject_text "$SCENE_QML" 'audioOffsetX' \
    'logo blocks still carry audio displacement'

# The existing analyzer component stays inert until the dedicated visualizer pass;
# its smoothing still has to settle safely if constructed later.
require_text "$AUDIO_QML" 'function settled()' \
    'audio analyzer has no explicit settled state'
require_text "$AUDIO_QML" 'if (root.settled())' \
    'audio smoothing does not stop after settling'

printf '%s\n' 'PASS: lockscreen active-only explosion physics regressions'
'''
write("tests/test-quickshell-lockscreen-interactive-physics-regressions.sh", physics_test)

interactive_test = r'''#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
APP_STATE="${ROOT}/config/hypr/scripts/quickshell_application_state.sh"
BAR_STATE="${ROOT}/config/quickshell/awtarchy/BarState.qml"
QUICK_SETTINGS="${ROOT}/config/quickshell/awtarchy/QuickSettings.qml"
SHELL_QML="${ROOT}/config/quickshell/awtarchy-lock/shell.qml"
SURFACE_QML="${ROOT}/config/quickshell/awtarchy-lock/LockSurface.qml"
SCENE_QML="${ROOT}/config/quickshell/awtarchy-lock/LockScene.qml"
AUDIO_QML="${ROOT}/config/quickshell/awtarchy-lock/LockAudioAnalyzer.qml"
WEATHER_QML="${ROOT}/config/quickshell/awtarchy-lock/LockWeatherCache.qml"
CAVA_CONFIG="${ROOT}/config/quickshell/awtarchy-lock/cava.conf"
AUDIO_HELPER="${ROOT}/config/hypr/scripts/quickshell_lockscreen_audio.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
require_file() { [[ -f "$1" ]] || fail "$2"; }
require_text() { grep -Fq -- "$2" "$1" || fail "$3"; }
reject_text() { if grep -Fq -- "$2" "$1"; then fail "$3"; fi; }

mkdir -p "$TMP/cache/awtarchy" "$TMP/home" "$TMP/config"
printf '%s\n' '{"enabled":true,"monitors":{},"launcher_sizes":{},"update_notifications_enabled":true}' \
    >"$TMP/cache/awtarchy/quickshell-state.json"

check_bool_setting() {
    local command="$1" field="$2"
    XDG_CACHE_HOME="$TMP/cache" XDG_CONFIG_HOME="$TMP/config" HOME="$TMP/home" \
        bash "$APP_STATE" "$command" true
    jq -e --arg field "$field" '.[$field] == true' "$TMP/cache/awtarchy/quickshell-state.json" >/dev/null \
        || fail "$command did not persist true to $field"
    XDG_CACHE_HOME="$TMP/cache" XDG_CONFIG_HOME="$TMP/config" HOME="$TMP/home" \
        bash "$APP_STATE" "$command" false
    jq -e --arg field "$field" '.[$field] == false' "$TMP/cache/awtarchy/quickshell-state.json" >/dev/null \
        || fail "$command did not persist false to $field"
}

check_bool_setting set-lockscreen-mouse-interactive lockscreen_mouse_interactive
check_bool_setting set-lockscreen-show-time lockscreen_show_time
check_bool_setting set-lockscreen-show-date lockscreen_show_date
check_bool_setting set-lockscreen-show-username lockscreen_show_username
check_bool_setting set-lockscreen-show-weather lockscreen_show_weather

require_text "$BAR_STATE" 'lockscreen_logo_physics_hz: 30' \
    'BarState stock logo physics rate is not 30 Hz'
require_text "$BAR_STATE" 'lockscreen_mouse_interactive: true' \
    'BarState stock mouse interaction is not enabled'
require_text "$BAR_STATE" 'function lockscreenLogoPhysicsHz()' \
    'BarState does not normalize the logo physics rate'
require_text "$BAR_STATE" 'function lockscreenMouseInteractiveEnabled()' \
    'BarState does not normalize mouse interaction'
require_text "$QUICK_SETTINGS" 'text: "Logo Physics"' \
    'Quick Settings has no Logo Physics control'
require_text "$QUICK_SETTINGS" 'text: "Mouse Interaction"' \
    'Quick Settings has no Mouse Interaction control'
reject_text "$QUICK_SETTINGS" 'text: "Audio Reactive"' \
    'retired audio-reactive logo control remains visible'

require_text "$SHELL_QML" 'property int lockLogoPhysicsHz: 30' \
    'secure lock shell does not default logo physics to 30 Hz'
require_text "$SHELL_QML" 'property bool lockMouseInteractive: true' \
    'secure lock shell has no mouse-interaction preference'
require_text "$SHELL_QML" 'lockLogoPhysicsHz = normalizedLogoPhysicsHz(parsed.lockscreen_logo_physics_hz);' \
    'secure lock shell does not load the persisted logo physics rate'
reject_text "$SHELL_QML" 'LockAudioAnalyzer {' \
    'secure lock still starts an analyzer solely to move the AWTARCHY logo'
require_text "$SHELL_QML" 'LockWeatherCache {' \
    'secure lock shell lost its cache-only weather reader'
require_text "$SHELL_QML" 'logoPhysicsHz: root.lockLogoPhysicsHz' \
    'secure lock surfaces do not receive logo physics rate'
require_text "$SHELL_QML" 'mouseInteractive: root.lockMouseInteractive' \
    'secure lock surfaces do not receive mouse interaction state'

require_text "$SURFACE_QML" 'cursorShape: Qt.BlankCursor' \
    'lockscreen exposes the real pointer'
require_text "$SURFACE_QML" 'required property int logoPhysicsHz' \
    'lock surface has no logo physics input'
require_text "$SURFACE_QML" 'scene.handlePointerClick(mouse.x, mouse.y)' \
    'secure surface drops pointer clicks before presentation physics'
require_text "$SURFACE_QML" 'password.forceActiveFocus()' \
    'click interaction no longer restores password focus'

require_text "$SCENE_QML" 'readonly property int ghostTrailLength: 6' \
    'ghost cursor no longer uses the bounded six-sample trail'
require_text "$SCENE_QML" 'readonly property int cursorFadeDelayMs: 180' \
    'ghost cursor idle delay changed unexpectedly'
require_text "$SCENE_QML" 'readonly property int cursorFadeDurationMs: 320' \
    'ghost cursor fade duration changed unexpectedly'
require_text "$SCENE_QML" 'function triggerLogoExplosion(x, y)' \
    'shared scene has no click explosion path'
require_text "$SCENE_QML" 'running: root.logoExplosionActive' \
    'logo physics runs while idle'
reject_text "$SCENE_QML" 'required property bool audioReactive' \
    'shared scene still exposes logo audio-reactive state'
reject_text "$SCENE_QML" 'function updatePointerField(' \
    'ordinary pointer motion still drives logo deformation'

require_file "$WEATHER_QML" 'lockscreen weather cache reader QML is missing'
require_text "$WEATHER_QML" 'lockscreen-weather.json' \
    'weather cache reader does not use the dedicated local cache'
reject_text "$WEATHER_QML" 'https://' \
    'secure weather reader contains network behavior'

# Analyzer/helper assets remain available for the dedicated visualizer pass but
# are not instantiated solely for the logo anymore.
require_file "$AUDIO_QML" 'lockscreen audio analyzer component is missing'
require_file "$CAVA_CONFIG" 'lockscreen CAVA configuration is missing'
require_file "$AUDIO_HELPER" 'lockscreen audio helper is missing'
require_text "$AUDIO_HELPER" 'command -v cava >/dev/null 2>&1 || exit 0' \
    'audio helper does not safely tolerate missing CAVA'
reject_text "$AUDIO_HELPER" 'microphone' \
    'audio helper contains microphone capture behavior'

for token in logoPhysicsHz LockAudioAnalyzer LockWeatherCache weatherText mouseInteractive; do
    reject_text "${ROOT}/config/quickshell/awtarchy-lock/LockAuth.qml" "$token" \
        "authentication owner was coupled to optional lockscreen state: $token"
done

printf '%s\n' 'PASS: lockscreen click-only interactive effects contracts'
'''
write("tests/test-quickshell-lockscreen-interactive-effects.sh", interactive_test)

# Update managed-history entries for every managed production file changed here.
history_path = ROOT / "local/share/awtarchy/quickshell-managed-history.sha256"
history = history_path.read_text(encoding="utf-8")
managed = {
    APP: ".config/hypr/scripts/quickshell_application_state.sh",
    PICKER: ".config/hypr/scripts/quickshell_lockscreen_wallpaper_picker.sh",
    BAR: ".config/quickshell/awtarchy/BarState.qml",
    QS: ".config/quickshell/awtarchy/QuickSettings.qml",
    EDITOR: ".config/quickshell/awtarchy/LockscreenEditor.qml",
    PREVIEW: ".config/quickshell/awtarchy/LockPreviewScene.qml",
    SHELL: ".config/quickshell/awtarchy-lock/shell.qml",
    SURFACE: ".config/quickshell/awtarchy-lock/LockSurface.qml",
    SCENE: ".config/quickshell/awtarchy-lock/LockScene.qml",
}
for source, installed in managed.items():
    digest = hashlib.sha256((ROOT / source).read_bytes()).hexdigest()
    entry = f"{digest}\t{installed}"
    if entry not in history.splitlines():
        if history and not history.endswith("\n"):
            history += "\n"
        history += entry + "\n"
history_path.write_text(history, encoding="utf-8")

# Guard against accidental security ownership edits by the patcher itself.
if "LockAuth.qml" in managed:
    raise SystemExit("LockAuth.qml must never be part of this patcher")

print("Pass 1 production patch applied")
