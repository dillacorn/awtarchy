#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
EDITOR="${ROOT}/config/quickshell/awtarchy/LockscreenEditor.qml"
SCENE="${ROOT}/config/quickshell/awtarchy/LockPreviewScene.qml"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

require_text() {
    local file="$1" text="$2" message="$3"
    grep -Fq -- "$text" "$file" || fail "$message"
}

# Pickup feedback must affect the real rendered preview element, not only the
# transparent editor selection rectangle.
require_text "$EDITOR" 'property string heldElement: ""' \
    'editor has no held-element state for pickup feedback'
require_text "$EDITOR" 'property real heldScaleBoost: 1.0' \
    'editor has no transient pickup scale state'
require_text "$EDITOR" 'function beginEditorHold(name)' \
    'editor has no pickup transition helper'
require_text "$EDITOR" 'function endEditorHold(name)' \
    'editor has no release transition helper'
require_text "$EDITOR" 'editorHeldElement: root.heldElement' \
    'preview scene does not receive the held element'
require_text "$EDITOR" 'editorHoldScale: root.heldScaleBoost' \
    'preview scene does not receive pickup scale feedback'
require_text "$SCENE" 'property string editorHeldElement: ""' \
    'preview scene has no editor held-element input'
require_text "$SCENE" 'property real editorHoldScale: 1.0' \
    'preview scene has no editor pickup scale input'
require_text "$SCENE" 'name === editorHeldElement ? editorHoldScale : 1.0' \
    'pickup feedback does not scale the actual rendered element'

# Flicking is deliberately gated. Slow/precise placement must stop where the
# pointer is released instead of acquiring accidental momentum.
require_text "$EDITOR" 'readonly property real flickThreshold: 0.80' \
    'editor flick threshold is missing or too implicit to preserve precision'
require_text "$EDITOR" 'readonly property real flickVelocityCap: 2.50' \
    'editor flick velocity is not bounded'
require_text "$EDITOR" 'readonly property real flickFriction: 0.86' \
    'editor flick friction is missing'
require_text "$EDITOR" 'readonly property real flickBounceDamping: 0.38' \
    'editor edge bounce is not damped'
require_text "$EDITOR" 'readonly property real flickStopSpeed: 0.04' \
    'editor flick motion has no deterministic settle threshold'
require_text "$EDITOR" 'readonly property int flickReleaseFreshnessMs: 80' \
    'editor has no recent-motion window to distinguish a flick from a careful paused release'
require_text "$EDITOR" 'function shouldStartFlick(vx, vy)' \
    'editor has no explicit slow-release/flick gate'
require_text "$EDITOR" 'return Math.sqrt(vx * vx + vy * vy) >= flickThreshold;' \
    'slow drags are not explicitly excluded from inertia'
require_text "$EDITOR" 'Math.max(-flickVelocityCap, Math.min(flickVelocityCap' \
    'release velocity is not capped before inertia starts'
require_text "$EDITOR" 'Date.now() - parent.lastSampleTime > root.flickReleaseFreshnessMs' \
    'paused precise releases can still reuse stale high drag velocity'

# Recent pointer samples drive velocity; the inertial timer advances only after
# release and reflects/damps velocity when existing safe placement bounds clamp
# the proposed position.
require_text "$EDITOR" 'property real lastSampleTime: 0' \
    'drag delegate does not track recent sample time'
require_text "$EDITOR" 'property real flickVelocityX: 0' \
    'drag delegate does not track horizontal release velocity'
require_text "$EDITOR" 'property real flickVelocityY: 0' \
    'drag delegate does not track vertical release velocity'
require_text "$EDITOR" 'property bool inertiaActive: false' \
    'drag delegate has no explicit inertial state'
require_text "$EDITOR" 'onReleased: mouse => {' \
    'drag delegate has no release handler for flick gating'
require_text "$EDITOR" 'if (root.shouldStartFlick(parent.flickVelocityX, parent.flickVelocityY))' \
    'release does not gate inertia on deliberate flick velocity'
require_text "$EDITOR" 'interval: 16' \
    'editor inertia does not update at a smooth frame cadence'
require_text "$EDITOR" 'parent.flickVelocityX = -parent.flickVelocityX * root.flickBounceDamping;' \
    'horizontal edge collision does not bounce with damping'
require_text "$EDITOR" 'parent.flickVelocityY = -parent.flickVelocityY * root.flickBounceDamping;' \
    'vertical edge collision does not bounce with damping'
require_text "$EDITOR" 'parent.flickVelocityX *= root.flickFriction;' \
    'horizontal inertia does not lose energy'
require_text "$EDITOR" 'parent.flickVelocityY *= root.flickFriction;' \
    'vertical inertia does not lose energy'
require_text "$EDITOR" 'root.setDraftPoint(parent.elementName, clamped.x, clamped.y);' \
    'inertia does not update the same bounded draft position used by normal dragging'

printf '%s\n' 'PASS: lockscreen editor pickup, deliberate flick inertia, precision release, and damped edge bounce contracts'
