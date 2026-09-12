#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
APP_STATE="${ROOT}/config/hypr/scripts/quickshell_application_state.sh"
BAR_STATE="${ROOT}/config/quickshell/awtarchy/BarState.qml"
QUICK_SETTINGS="${ROOT}/config/quickshell/awtarchy/QuickSettings.qml"
EDITOR="${ROOT}/config/quickshell/awtarchy/LockscreenEditor.qml"
PICKER="${ROOT}/config/hypr/scripts/quickshell_lockscreen_wallpaper_picker.sh"
SCENE="${ROOT}/config/quickshell/awtarchy-lock/LockScene.qml"
PREVIEW="${ROOT}/config/quickshell/awtarchy/LockPreviewScene.qml"
SURFACE="${ROOT}/config/quickshell/awtarchy-lock/LockSurface.qml"
LOCK_SHELL="${ROOT}/config/quickshell/awtarchy-lock/shell.qml"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

require_text() {
    local file="$1" text="$2" message="$3"
    grep -Fq -- "$text" "$file" || fail "$message"
}

reject_text() {
    local file="$1" text="$2" message="$3"
    if grep -Fq -- "$text" "$file"; then
        fail "$message"
    fi
}

run_state() {
    XDG_CACHE_HOME="$TMP/cache" XDG_CONFIG_HOME="$TMP/config" HOME="$TMP/home" \
        bash "$APP_STATE" "$@"
}

mkdir -p "$TMP/cache/awtarchy" "$TMP/config" "$TMP/home"
printf '%s\n' '{"enabled":true,"monitors":{},"launcher_sizes":{},"update_notifications_enabled":true}' \
    >"$TMP/cache/awtarchy/quickshell-state.json"
state_file="$TMP/cache/awtarchy/quickshell-state.json"

# Logo physics rate is explicit, bounded, persistent, and defaults to 30 Hz.
for hz in 30 60 90; do
    run_state set-lockscreen-logo-physics-hz "$hz"
    jq -e --argjson hz "$hz" '.lockscreen_logo_physics_hz == $hz' "$state_file" >/dev/null \
        || fail "logo physics rate ${hz} did not persist"
done
state_before="$(sha256sum "$state_file" | awk '{print $1}')"
if run_state set-lockscreen-logo-physics-hz 45 >/dev/null 2>&1; then
    fail 'unsupported 45 Hz logo physics rate was accepted'
fi
[[ "$(sha256sum "$state_file" | awk '{print $1}')" == "$state_before" ]] \
    || fail 'invalid logo physics rate changed persistent state'
require_text "$BAR_STATE" 'lockscreen_logo_physics_hz: 30' \
    'BarState does not default logo physics to 30 Hz'
require_text "$BAR_STATE" 'function lockscreenLogoPhysicsHz()' \
    'BarState does not normalize the logo physics rate'
require_text "$QUICK_SETTINGS" 'text: "Logo Physics"' \
    'Quick Settings has no logo physics rate control'
for label in '30 Hz' '60 Hz' '90 Hz'; do
    require_text "$QUICK_SETTINGS" "label: \"${label}\"" \
        "Quick Settings is missing ${label} logo physics choice"
done
require_text "$QUICK_SETTINGS" '"set-lockscreen-logo-physics-hz"' \
    'Quick Settings does not persist logo physics rate'

# Pointer motion feeds a coherent hover field into the same bounded, active-only
# solver used by logo-click explosions.
for legacy in \
    'property real pointerFieldX:' \
    'property real pointerFieldY:' \
    'property real pointerFieldStrength:' \
    'function updatePointerField(' \
    'function directCellDeformationOffset(' \
    'function neighborCellDeformationOffset(' \
    'function logoCellDeformationOffset(' \
    'function logoGroupAudioOffset(' \
    'readonly property real combinedOffsetX:' \
    'readonly property real combinedOffsetY:' \
    'property real audioPhase:'; do
    reject_text "$SCENE" "$legacy" "legacy continuous logo deformation remains: $legacy"
done
require_text "$SCENE" 'required property int logoPhysicsHz' \
    'scene has no persisted logo physics rate input'
require_text "$SCENE" 'property bool logoExplosionActive: false' \
    'scene has no active-only logo explosion gate'
require_text "$SCENE" 'property var logoParticles: ({})' \
    'scene has no root-owned logo particle state'
require_text "$SCENE" 'function triggerLogoExplosion(x, y)' \
    'scene has no click explosion entrypoint'
require_text "$SCENE" 'function logoContainsPoint(x, y)' \
    'scene has no logo-only pointer hit test'
require_text "$SCENE" 'const logoWidth = root.elementVisualWidth("logo");' \
    'logo click hit test does not follow the transformed logo width'
require_text "$SCENE" 'const logoHeight = root.elementVisualHeight("logo");' \
    'logo click hit test does not follow the transformed logo height'
require_text "$SCENE" 'const logoCenterX = root.normalizedX("logo", 0.50) * root.width;' \
    'logo click hit test does not follow the configured horizontal position'
require_text "$SCENE" 'const logoCenterY = root.normalizedY("logo", 0.34) * root.height;' \
    'logo click hit test does not follow the configured vertical position'
require_text "$SCENE" 'if (!root.logoContainsPoint(x, y))' \
    'pointer click is not gated to the actual logo bounds'
require_text "$SCENE" 'function rebuildLogoBuckets()' \
    'logo explosion has no spatial bucket rebuild path'
require_text "$SCENE" 'function resolveLogoCollisions()' \
    'logo explosion has no local collision path'
require_text "$SCENE" 'function stepLogoExplosion()' \
    'logo explosion has no bounded physics step'
require_text "$SCENE" 'id: logoPhysicsTimer' \
    'logo explosion has no root physics timer'
require_text "$SCENE" 'running: root.logoSimulationActive' \
    'logo physics timer runs while idle'
require_text "$SCENE" 'function logoHoverTarget(row, column)' \
    'coherent hover deformation is missing'
require_text "$SCENE" 'interval: root.logoPhysicsIntervalMs' \
    'logo physics timer does not follow the selected refresh rate'
require_text "$SCENE" 'particle.vx +=' \
    'clicking during an active explosion does not inject another impulse'
require_text "$SCENE" 'root.triggerLogoExplosion(x, y);' \
    'logo pointer click does not trigger the block explosion'
require_text "$SCENE" 'const ghostDx = x - ghostHeadX;' \
    'high-polling-rate ghost movement accumulation regressed'
require_text "$SCENE" 'logoHoverDirty = wasLogoHovering || logoContainsPoint(x, y);' \
    'logo-local pointer motion does not wake the bounded hover solver'
reject_text "$SCENE" 'const margin = 90 * uiScale;' \
    'logo hit testing regressed to the old oversized fixed margin'
reject_text "$QUICK_SETTINGS" 'text: "Audio Reactive"' \
    'retired audio-reactive logo control is still exposed'
reject_text "$SURFACE" 'required property bool audioReactive' \
    'secure surface still carries audio-reactive logo state'
reject_text "$SCENE" 'required property bool audioReactive' \
    'presentation scene still accepts audio-reactive logo state'

# Guard the scene splice boundaries themselves. These catches are deliberately
# textual because duplicate declarations can evade shell-only contract tests.
reject_text "$SCENE" 'function minuteTimeFormat() {    function minuteTimeFormat() {' \
    'scene contains a duplicated minuteTimeFormat declaration'
reject_text "$SCENE" ';    readonly property real passwordCenterX:' \
    'scene property splice joined password geometry onto usernameText'
reject_text "$SCENE" ';    function wallpaperGeometry() {' \
    'scene property splice joined wallpaperGeometry onto dateText'
reject_text "$SCENE" '}    Timer {' \
    'scene timer splice joined two QML objects on one line'

# Secure surface still refocuses the real password input after presentation clicks.
require_text "$SURFACE" 'scene.handlePointerClick(mouse.x, mouse.y)' \
    'secure surface no longer forwards click interaction'
require_text "$SURFACE" 'password.forceActiveFocus()' \
    'click interaction no longer restores password focus'
require_text "$SURFACE" 'logoPhysicsHz: root.logoPhysicsHz' \
    'secure surface does not pass the logo physics rate to the scene'
require_text "$LOCK_SHELL" 'property int lockLogoPhysicsHz: 30' \
    'secure lock shell has no 30 Hz default'

# Undo/redo shortcuts belong to the actual fullscreen editor window, and direct
# scaling is one reversible history transaction.
require_text "$EDITOR" 'id: editorUndoShortcut' \
    'editor window has no owned Ctrl+Z shortcut'
require_text "$EDITOR" 'id: editorRedoShortcut' \
    'editor window has no owned Ctrl+Shift+Z shortcut'
require_text "$EDITOR" 'id: editorRedoAlternateShortcut' \
    'editor window has no owned Ctrl+Y shortcut'
require_text "$EDITOR" 'function beginResizeElement(name, sceneX, sceneY)' \
    'editor has no direct resize start path'
require_text "$EDITOR" 'function updateResizeElement(sceneX, sceneY)' \
    'editor has no direct resize update path'
require_text "$EDITOR" 'function endResizeElement()' \
    'editor has no direct resize completion path'
require_text "$EDITOR" 'id: elementResizeHandle' \
    'selected element has no pointer resize handle'
require_text "$EDITOR" 'id: selectedElementColorButton' \
    'selected element color control is still buried'
require_text "$EDITOR" 'root.toggleDrawer("element")' \
    'selected color affordance does not open element controls'

# Standard Awtwall handoff uses a fullscreen Alacritty window so it cannot tile
# beside unrelated applications. Alternate terminal overrides remain supported.
require_text "$PICKER" 'window.startup_mode=Fullscreen' \
    'Alacritty lockscreen wallpaper picker is not fullscreen'
require_text "$PICKER" "basename -- \"\$TERMINAL_CMD\"" \
    'wallpaper picker does not distinguish the standard Alacritty launch path'

cmp -s "$SCENE" "$PREVIEW" \
    || fail 'secure lock scene and desktop preview scene diverge'

printf '%s\n' 'PASS: lockscreen interaction performance and direct-manipulation contracts'
