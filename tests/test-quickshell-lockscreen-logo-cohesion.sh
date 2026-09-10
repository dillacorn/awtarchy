#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCENE="${ROOT}/config/quickshell/awtarchy-lock/LockScene.qml"
PREVIEW="${ROOT}/config/quickshell/awtarchy/LockPreviewScene.qml"

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

[[ -f "$SCENE" ]] || fail 'secure lock scene is missing'
[[ -f "$PREVIEW" ]] || fail 'desktop lock preview scene is missing'

# Pointer interaction is intentionally softer than rigid connected-letter
# motion: each filled block gets a local target and neighboring blocks contribute
# a smaller cohesion term so the wordmark stretches and reforms without bridges.
for forbidden in logoBridgeCanvas logoBridgePairs logoBridgeMaxDistance \
    logoBridgeInteractionBoost buildLogoBridgePairs logoBridgeInteractionEnergy; do
    reject_text "$SCENE" "$forbidden" \
        "legacy connector-line logo cohesion remains: $forbidden"
done

require_text "$SCENE" 'readonly property var logoCohesionGroups: buildLogoCohesionGroups()' \
    'logo does not precompute cohesive connected glyph groups'
require_text "$SCENE" 'function buildLogoCohesionGroups()' \
    'logo has no connected-component cohesion builder'
require_text "$SCENE" 'function logoGroupFor(row, column)' \
    'logo cells cannot resolve their cohesive movement group'
require_text "$SCENE" 'property real pointerFieldX:' \
    'logo hover deformation has no continuous pointer field x coordinate'
require_text "$SCENE" 'property real pointerFieldY:' \
    'logo hover deformation has no continuous pointer field y coordinate'
require_text "$SCENE" 'property real pointerFieldStrength:' \
    'logo hover deformation has no continuous field strength'
require_text "$SCENE" 'property real clickFieldStrength:' \
    'logo click deformation has no bounded field strength'
require_text "$SCENE" 'function directCellDeformationOffset(row, column)' \
    'logo does not calculate direct per-block pointer deformation'
require_text "$SCENE" 'function neighborCellDeformationOffset(row, column)' \
    'logo does not blend neighboring block deformation'
require_text "$SCENE" 'function logoCellDeformationOffset(row, column)' \
    'logo does not calculate the final gooey per-block deformation target'
require_text "$SCENE" 'root.logoCellDeformationOffset(wordmarkRow.rowIndex, columnIndex)' \
    'wordmark blocks do not consume their local deformation target'
reject_text "$SCENE" 'root.logoDeformationOffset(cohesionGroup)' \
    'wordmark blocks still share one rigid connected-group pointer target'
require_text "$SCENE" 'readonly property int pointerResponseDurationMs: 100' \
    'logo hover response is not the approved quick 100ms transition'
require_text "$SCENE" 'readonly property int pointerReturnDurationMs: 180' \
    'logo return-to-rest is not the approved softer transition'
require_text "$SCENE" 'Behavior on pointerOffsetX {' \
    'logo x deformation does not smoothly chase its target'
require_text "$SCENE" 'Behavior on pointerOffsetY {' \
    'logo y deformation does not smoothly chase its target'
require_text "$SCENE" 'easing.type: Easing.OutCubic' \
    'logo deformation does not use non-overshooting cubic easing'

for forbidden in 'Easing.OutBack' pointerReturnX pointerReturnY \
    'pointerReturnX.restart()' 'pointerReturnY.restart()'; do
    reject_text "$SCENE" "$forbidden" \
        "jumpy restart/overshoot pointer physics remains: $forbidden"
done

cmp -s "$SCENE" "$PREVIEW" \
    || fail 'secure lock scene and desktop preview scene diverge'

printf 'PASS: lockscreen cohesive smooth logo deformation contracts\n'
