#!/usr/bin/env bash
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
require_text "$SCENE" 'running: root.logoSimulationActive' \
    'logo physics does not stop while idle'
require_text "$SCENE" 'function logoHoverTarget(row, column)' \
    'coherent hover field was not restored'
require_text "$SCENE" 'readonly property var explosionOffset:' \
    'wordmark blocks do not read active explosion offsets'
require_text "$SCENE" '+ explosionOffset.x' \
    'wordmark X position does not consume explosion physics'
require_text "$SCENE" '+ explosionOffset.y' \
    'wordmark Y position does not consume explosion physics'

cmp -s "$SCENE" "$PREVIEW" \
    || fail 'secure lock scene and desktop preview scene diverge'

printf '%s\n' 'PASS: lockscreen coherent hover and block explosion contracts'
