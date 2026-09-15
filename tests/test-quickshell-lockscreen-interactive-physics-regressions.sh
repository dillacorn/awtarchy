#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCENE_QML="${ROOT}/config/quickshell/awtarchy-lock/LockScene.qml"
SURFACE_QML="${ROOT}/config/quickshell/awtarchy-lock/LockSurface.qml"
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

# Keep the established physics engine, but advance it at a second active-only
# cadence on the real secure surface so hover/explosion response is materially
# quicker without adding idle work. When explosion state drops, explicitly keep
# return-to-home active until the scene's own settle condition clears it.
require_text "$SURFACE_QML" 'id: logoInteractionBoost' \
    'secure lock surface has no active-only interaction speed boost'
require_text "$SURFACE_QML" 'interval: scene.logoPhysicsIntervalMs' \
    'interaction speed boost does not track the configured physics cadence'
require_text "$SURFACE_QML" 'running: scene.logoSimulationActive' \
    'interaction speed boost runs while the logo is idle'
require_text "$SURFACE_QML" 'onTriggered: scene.stepLogoExplosion()' \
    'interaction speed boost does not advance the existing physics engine'
require_text "$SURFACE_QML" 'function onLogoExplosionActiveChanged()' \
    'secure lock surface does not observe explosion expiry'
require_text "$SURFACE_QML" 'scene.logoReturnPending = true;' \
    'explosion expiry can strand logo blocks before their return-to-home finishes'
require_text "$SURFACE_QML" 'scene.logoHoverDirty = true;' \
    'explosion expiry does not keep the active-only physics timer alive'

# Parsed CAVA frames are presented directly; a second QML smoothing cadence
# would reintroduce the lag observed in the first runtime pass.
require_text "$AUDIO_QML" 'bands = result;' \
    'audio analyzer does not publish frames directly'
reject_text "$AUDIO_QML" 'function normalizedSpectrum' \
    'audio analyzer still performs a second normalization pass'
reject_text "$AUDIO_QML" 'smoothingTimer' \
    'retired QML smoothing cadence remains'

printf '%s\n' 'PASS: lockscreen active-only explosion physics regressions'
