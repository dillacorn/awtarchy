#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
LAYER="${ROOT}/config/quickshell/awtarchy-lock/LockTransitionLayer.qml"
SURFACE="${ROOT}/config/quickshell/awtarchy-lock/LockSurface.qml"
SCENE="${ROOT}/config/quickshell/awtarchy-lock/LockScene.qml"
SHELL="${ROOT}/config/quickshell/awtarchy-lock/shell.qml"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

require_text() {
    local file="$1" text="$2" message="$3"
    grep -Fq -- "$text" "$file" || fail "$message"
}

forbid_text() {
    local file="$1" text="$2" message="$3"
    if grep -Fq -- "$text" "$file"; then
        fail "$message"
    fi
}

[[ -f "$LAYER" ]] || fail 'shared LockTransitionLayer.qml is missing'

require_text "$LAYER" 'property Item startSource' \
    'transition layer does not accept the frozen desktop source'
require_text "$LAYER" 'property Item endSource' \
    'transition layer does not accept the real lockscreen destination'
require_text "$LAYER" 'property string mode' \
    'transition layer does not expose the selected transition mode'
require_text "$LAYER" 'property int duration' \
    'transition layer does not expose transition duration'
require_text "$LAYER" 'property int replayToken' \
    'transition layer cannot be replayed by the editor/runtime coordinator'
require_text "$LAYER" 'signal finished()' \
    'transition layer does not signal the secure handoff completion'
require_text "$LAYER" 'Math.max(800, Math.min(6000' \
    'transition duration is not bounded to the approved 800-6000 ms range'
require_text "$LAYER" ': 1800' \
    'transition layer does not retain the approved 1800 ms default'

shader_count="$(grep -Fc -- 'ShaderEffectSource {' "$LAYER")"
[[ "$shader_count" -ge 2 ]] || fail 'pixel transition does not use two ShaderEffectSource inputs'
require_text "$LAYER" 'textureSize:' \
    'pixel transition does not downsample its source resolution'
require_text "$LAYER" 'smooth: false' \
    'pixel transition is not using nearest-neighbor block sampling'
require_text "$LAYER" 'sourceBlend' \
    'pixel transition does not hand off sources at peak pixelation'
require_text "$LAYER" 'collapseAmount' \
    'pixel transition does not collapse then restore resolution'
forbid_text "$LAYER" 'Repeater {' \
    'shared transition layer reintroduced a tile/repeater fake pixel effect'

require_text "$SURFACE" 'color: "#000000"' \
    'secure surface does not fail closed to opaque black'
require_text "$SURFACE" 'LockTransitionLayer {' \
    'secure surface is not using the shared two-source transition layer'
require_text "$SURFACE" 'captureDirectory' \
    'secure surface does not receive the validated pre-lock capture directory'
require_text "$SURFACE" 'screen.name' \
    'secure surface does not select the capture for its actual Wayland output'
require_text "$SURFACE" 'externallyManagedEntryTransition: true' \
    'secure LockScene still owns the rejected black-cover transition'
require_text "$SURFACE" 'externalEntryTransitionRunning:' \
    'secure LockScene logo/password gating is not tied to the shared transition'
require_text "$SURFACE" 'transitionLayer.running' \
    'secure surface does not gate entry presentation on transition completion'

require_text "$SCENE" 'property bool externallyManagedEntryTransition' \
    'LockScene cannot defer secure transition timing to LockSurface'
require_text "$SCENE" 'property bool externalEntryTransitionRunning' \
    'LockScene cannot delay logo formation for the external secure transition'
require_text "$SCENE" '!root.externallyManagedEntryTransition' \
    'legacy black-cover transition remains active in secure runtime'

require_text "$SHELL" 'AWTARCHY_LOCK_CAPTURE_DIR' \
    'secure shell does not consume the scoped capture directory'
require_text "$SHELL" 'captureDirectory:' \
    'secure shell does not pass the validated capture directory to each lock surface'

printf 'PASS: secure desktop-to-lockscreen transition layer contract\n'
