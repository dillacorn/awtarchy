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
POWER_MENU_QML="${ROOT}/config/quickshell/awtarchy/PowerMenu.qml"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
require_text() { local file="$1" text="$2" message="$3"; grep -Fq -- "$text" "$file" || fail "$message"; }
reject_text() { local file="$1" text="$2" message="$3"; if grep -Fq -- "$text" "$file"; then fail "$message"; fi; }
run_state() { XDG_CACHE_HOME="$TMP/cache" XDG_CONFIG_HOME="$TMP/config" HOME="$TMP/home" bash "$APP_STATE" "$@"; }

mkdir -p "$TMP/cache/awtarchy" "$TMP/config" "$TMP/home"
printf '%s\n' '{"enabled":true,"monitors":{},"launcher_sizes":{},"update_notifications_enabled":true}' >"$TMP/cache/awtarchy/quickshell-state.json"
state_file="$TMP/cache/awtarchy/quickshell-state.json"

for hz in 30 60 90; do
    run_state set-lockscreen-logo-physics-hz "$hz"
    jq -e --argjson hz "$hz" '.lockscreen_logo_physics_hz == $hz' "$state_file" >/dev/null || fail "logo physics rate ${hz} did not persist"
done
state_before="$(sha256sum "$state_file" | awk '{print $1}')"
if run_state set-lockscreen-logo-physics-hz 45 >/dev/null 2>&1; then fail 'unsupported 45 Hz logo physics rate was accepted'; fi
[[ "$(sha256sum "$state_file" | awk '{print $1}')" == "$state_before" ]] || fail 'invalid logo physics rate changed persistent state'
require_text "$BAR_STATE" 'lockscreen_logo_physics_hz: 30' 'BarState does not default logo physics to 30 Hz'
require_text "$BAR_STATE" 'function lockscreenLogoPhysicsHz()' 'BarState does not normalize the logo physics rate'
require_text "$QUICK_SETTINGS" 'text: "Logo Physics"' 'Quick Settings has no logo physics rate control'
for label in '30 Hz' '60 Hz' '90 Hz'; do require_text "$QUICK_SETTINGS" "label: \"${label}\"" "Quick Settings is missing ${label} logo physics choice"; done
require_text "$QUICK_SETTINGS" '"set-lockscreen-logo-physics-hz"' 'Quick Settings does not persist logo physics rate'

for legacy in 'property real pointerFieldX:' 'property real pointerFieldY:' 'property real pointerFieldStrength:' 'function updatePointerField(' 'function directCellDeformationOffset(' 'function neighborCellDeformationOffset(' 'function logoCellDeformationOffset(' 'function logoGroupAudioOffset(' 'readonly property real combinedOffsetX:' 'readonly property real combinedOffsetY:' 'property real audioPhase:'; do
    reject_text "$SCENE" "$legacy" "legacy continuous logo deformation remains: $legacy"
done
require_text "$SCENE" 'required property int logoPhysicsHz' 'scene has no persisted logo physics rate input'
require_text "$SCENE" 'property bool logoExplosionActive: false' 'scene has no active-only logo explosion gate'
require_text "$SCENE" 'property var logoParticles: ({})' 'scene has no root-owned logo particle state'
require_text "$SCENE" 'function triggerLogoExplosion(x, y)' 'scene has no click explosion entrypoint'
require_text "$SCENE" 'function logoContainsPoint(x, y)' 'scene has no logo-only pointer hit test'
require_text "$SCENE" 'const logoWidth = root.elementVisualWidth("logo");' 'logo click hit test does not follow the transformed logo width'
require_text "$SCENE" 'const logoHeight = root.elementVisualHeight("logo");' 'logo click hit test does not follow the transformed logo height'
require_text "$SCENE" 'const logoCenterX = root.normalizedX("logo", 0.50) * root.width;' 'logo click hit test does not follow the configured horizontal position'
require_text "$SCENE" 'const logoCenterY = root.normalizedY("logo", 0.34) * root.height;' 'logo click hit test does not follow the configured vertical position'
require_text "$SCENE" 'if (!root.logoContainsPoint(x, y))' 'pointer click is not gated to the actual logo bounds'
require_text "$SCENE" 'function rebuildLogoBuckets()' 'logo explosion has no spatial bucket rebuild path'
require_text "$SCENE" 'function resolveLogoCollisions()' 'logo explosion has no local collision path'
require_text "$SCENE" 'function stepLogoExplosion()' 'logo explosion has no bounded physics step'
require_text "$SCENE" 'id: logoPhysicsTimer' 'logo explosion has no root physics timer'
require_text "$SCENE" 'running: root.logoSimulationActive' 'logo physics timer runs while idle'
require_text "$SCENE" 'function logoHoverTarget(row, column, localPointer)' 'coherent hover deformation does not use cached local pointer state'
require_text "$SCENE" 'interval: root.logoPhysicsIntervalMs' 'logo physics timer does not follow the selected refresh rate'
require_text "$SCENE" 'particle.vx +=' 'clicking during an active explosion does not inject another impulse'
require_text "$SCENE" 'root.triggerLogoExplosion(x, y);' 'logo pointer click does not trigger the block explosion'
require_text "$SCENE" 'const ghostDx = x - ghostHeadX;' 'high-polling-rate ghost movement accumulation regressed'
require_text "$SCENE" 'const isLogoHovering = logoContainsPoint(x, y);' 'logo-local pointer motion no longer computes bounded hover state'
require_text "$SCENE" 'logoHoverDirty = wasLogoHovering || isLogoHovering;' 'logo-local pointer motion does not wake the bounded hover solver'
reject_text "$SCENE" 'const margin = 90 * uiScale;' 'logo hit testing regressed to the old oversized fixed margin'
reject_text "$QUICK_SETTINGS" 'text: "Audio Reactive"' 'retired audio-reactive logo control is still exposed'
reject_text "$SURFACE" 'required property bool audioReactive' 'secure surface still carries audio-reactive logo state'
reject_text "$SCENE" 'required property bool audioReactive' 'presentation scene still accepts audio-reactive logo state'

reject_text "$SCENE" 'function minuteTimeFormat() {    function minuteTimeFormat() {' 'scene contains a duplicated minuteTimeFormat declaration'
reject_text "$SCENE" ';    readonly property real passwordCenterX:' 'scene property splice joined password geometry onto usernameText'
reject_text "$SCENE" ';    function wallpaperGeometry() {' 'scene property splice joined wallpaperGeometry onto dateText'
reject_text "$SCENE" '}    Timer {' 'scene timer splice joined two QML objects on one line'

require_text "$SURFACE" 'scene.handlePointerClick(mouse.x, mouse.y)' 'secure surface no longer forwards click interaction'
require_text "$SURFACE" 'password.forceActiveFocus()' 'click interaction no longer restores password focus'
require_text "$SURFACE" 'logoPhysicsHz: root.logoPhysicsHz' 'secure surface does not pass the logo physics rate to the scene'
require_text "$LOCK_SHELL" 'property int lockLogoPhysicsHz: 30' 'secure lock shell has no 30 Hz default'

require_text "$EDITOR" 'id: editorUndoShortcut' 'editor window has no owned Ctrl+Z shortcut'
require_text "$EDITOR" 'id: editorRedoShortcut' 'editor window has no owned Ctrl+Shift+Z shortcut'
require_text "$EDITOR" 'id: editorRedoAlternateShortcut' 'editor window has no owned Ctrl+Y shortcut'
require_text "$EDITOR" 'function beginResizeElement(name, sceneX, sceneY)' 'editor has no direct resize start path'
require_text "$EDITOR" 'function updateResizeElement(sceneX, sceneY)' 'editor has no direct resize update path'
require_text "$EDITOR" 'function endResizeElement()' 'editor has no direct resize completion path'
require_text "$EDITOR" 'id: elementResizeHandle' 'selected element has no pointer resize handle'
require_text "$EDITOR" 'id: selectedElementColorButton' 'selected element color control is still buried'
require_text "$EDITOR" 'root.toggleDrawer("element")' 'selected color affordance does not open element controls'

require_text "$PICKER" 'window.startup_mode=Fullscreen' 'Alacritty lockscreen wallpaper picker is not fullscreen'
require_text "$PICKER" "basename -- \"\$TERMINAL_CMD\"" 'wallpaper picker does not distinguish the standard Alacritty launch path'

# Pressing L must hard-hide every Power Menu surface without running its normal
# opacity animation. Capture may only start after the real backing windows are
# gone and a short compositor-settle interval has elapsed.
require_text "$POWER_MENU_QML" 'property bool lockHardHide: false' \
    'Power Menu lock path has no explicit animation-free hard-hide state'
require_text "$POWER_MENU_QML" 'readonly property int lockCaptureSettleDuration: 50' \
    'Power Menu lock path has no compositor-settle interval before capture'
require_text "$POWER_MENU_QML" 'enabled: !root.lockHardHide' \
    'Power Menu opacity animation is not disabled during the lock hard hide'
require_text "$POWER_MENU_QML" 'id: lockCaptureSettleTimer' \
    'Power Menu lock path has no post-unmap settle timer'
require_text "$POWER_MENU_QML" 'interval: root.lockCaptureSettleDuration' \
    'Power Menu settle timer does not use the configured compositor-settle interval'
require_text "$POWER_MENU_QML" 'lockCaptureSettleTimer.restart();' \
    'Power Menu starts lock capture immediately when backing windows first report hidden'

python3 - "$POWER_MENU_QML" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
try:
    begin_body = text.split("function beginLockAction(action)", 1)[1].split("function abortLockHandoff", 1)[0]
    handoff_body = text.split("id: lockHandoffTimer", 1)[1].split("id: lockCaptureSettleTimer", 1)[0]
    settle_body = text.split("id: lockCaptureSettleTimer", 1)[1].split("Process {", 1)[0]
except IndexError as exc:
    raise SystemExit(f"FAIL: unable to locate Power Menu hard-hide sequencing block: {exc}")

hard_hide_index = begin_body.find("lockHardHide = true")
hide_index = begin_body.find("powerWindow.visible = false")
if hard_hide_index < 0 or hide_index < 0 or hard_hide_index > hide_index:
    raise SystemExit("FAIL: Power Menu does not disable animation before hiding the lock surface")
if "freshLockCommand" in handoff_body:
    raise SystemExit("FAIL: fresh screenshot capture can still begin immediately on first backing-window unmap")
if "powerMenuBackingHidden()" not in settle_body or "LockscreenEditor.lockCaptureBackingHidden()" not in settle_body:
    raise SystemExit("FAIL: post-unmap settle stage does not revalidate every hidden backing window")
if "root.startAction(action, root.freshLockCommand);" not in settle_body:
    raise SystemExit("FAIL: fresh screenshot capture is not deferred until the compositor-settle stage")
PY

bash "$ROOT/tests/test-quickshell-lockscreen-pretest-optimizations.sh"
cmp -s "$SCENE" "$PREVIEW" || fail 'secure lock scene and desktop preview scene diverge'

printf '%s\n' 'PASS: lockscreen interaction performance and direct-manipulation contracts'
