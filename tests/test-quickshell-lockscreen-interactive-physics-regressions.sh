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

python3 - "$SCENE_QML" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
try:
    step = text.split("function stepLogoExplosion()", 1)[1].split("function updateClockText()", 1)[0]
    expiry = step.split("if (logoExplosionActive && logoExplosionElapsedMs >= logoExplosionMaxMs)", 1)[1]
    expiry = expiry.split("if (returning && maxMotion < 1.2)", 1)[0]
except IndexError as exc:
    raise SystemExit("FAIL: logo explosion expiry structure changed unexpectedly") from exc

if "logoReturnPending = true;" not in expiry:
    raise SystemExit("FAIL: explosion expiry can strand logo blocks before their return-to-home finishes")
PY

require_text "$SCENE_QML" 'readonly property real logoHoverSpring: 110' \
    'logo hover response is still too soft'
require_text "$SCENE_QML" 'readonly property real logoHomeSpring: 72' \
    'logo return-to-home response is still too soft'
require_text "$SCENE_QML" 'readonly property real logoHoverDamping: 18' \
    'logo hover response is still too fluid'
require_text "$SCENE_QML" 'readonly property real logoHomeDamping: 14' \
    'logo return-to-home response is still too fluid'
require_text "$SCENE_QML" 'readonly property int logoExplosionScatterMs: 340' \
    'logo explosion lingers too long before returning'
require_text "$SCENE_QML" 'readonly property int logoExplosionMaxMs: 1100' \
    'logo explosion active phase still lasts too long'

# Parsed CAVA frames are presented directly; a second QML smoothing cadence
# would reintroduce the lag observed in the first runtime pass.
require_text "$AUDIO_QML" 'bands = result;' \
    'audio analyzer does not publish frames directly'
reject_text "$AUDIO_QML" 'function normalizedSpectrum' \
    'audio analyzer still performs a second normalization pass'
reject_text "$AUDIO_QML" 'smoothingTimer' \
    'retired QML smoothing cadence remains'

printf '%s\n' 'PASS: lockscreen active-only explosion physics regressions'
