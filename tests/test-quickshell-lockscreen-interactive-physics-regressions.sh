#!/usr/bin/env bash
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
require_text "$SCENE_QML" 'running: root.logoSimulationActive' \
    'logo physics timer is not strictly active-only'
require_text "$SCENE_QML" 'logoExplosionElapsedMs >= logoExplosionScatterMs' \
    'explosion has no scatter-to-return phase boundary'
require_text "$SCENE_QML" 'particle.vx += (hoverTarget.x - Number(particle.x || 0)) * spring * dt;' \
    'return phase does not spring blocks toward the coherent hover/home target'
require_text "$SCENE_QML" 'logoParticleBuckets' \
    'collision system does not use spatial buckets'
reject_text "$SCENE_QML" 'audioEffectsEnabled' \
    'logo physics still carries audio-reactive gating'
reject_text "$SCENE_QML" 'audioOffsetX' \
    'logo blocks still carry audio displacement'

# Parsed CAVA frames are presented directly; a second QML smoothing cadence
# would reintroduce the lag observed in the first runtime pass.
require_text "$AUDIO_QML" 'bands = normalizedSpectrum(values);' \
    'audio analyzer does not publish frames directly'
reject_text "$AUDIO_QML" 'smoothingTimer' \
    'retired QML smoothing cadence remains'

printf '%s\n' 'PASS: lockscreen active-only explosion physics regressions'
