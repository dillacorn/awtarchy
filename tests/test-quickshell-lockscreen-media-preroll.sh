#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCENE="$ROOT/config/quickshell/awtarchy-lock/LockScene.qml"
PREVIEW_SCENE="$ROOT/config/quickshell/awtarchy/LockPreviewScene.qml"
SURFACE="$ROOT/config/quickshell/awtarchy-lock/LockSurface.qml"
TRANSITION="$ROOT/config/quickshell/awtarchy-lock/LockTransitionLayer.qml"
AUTH="$ROOT/config/quickshell/awtarchy-lock/LockAuth.qml"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
require_text() { grep -Fq -- "$2" "$1" || fail "$3"; }
reject_text() { ! grep -Fq -- "$2" "$1" || fail "$3"; }

require_text "$SCENE" 'property bool externalEntryTransitionPending: false' \
    'scene cannot represent video pre-roll as pending transition time'
require_text "$SCENE" 'externalEntryTransitionRunning || externalEntryTransitionPending' \
    'scene presentation gate does not include pending video pre-roll'
require_text "$SCENE" 'readonly property bool backgroundMediaNeedsPreroll:' \
    'scene does not expose whether the selected background needs video pre-roll'
require_text "$SCENE" 'wallpaperMedia.mediaKind === "video"' \
    'video pre-roll is not limited to MP4/video backgrounds'
require_text "$SCENE" 'readonly property bool backgroundMediaPlaybackAdvanced:' \
    'scene does not expose decoded-frame advancement readiness'
require_text "$SCENE" 'wallpaperMedia.playbackAdvanced' \
    'scene readiness does not use actual decoded video-frame progress'
cmp -s "$SCENE" "$PREVIEW_SCENE" \
    || fail 'secure and preview presentation scenes diverge after pre-roll support'

require_text "$SURFACE" 'property bool transitionStarted: false' \
    'secure surface does not track whether the entry transition has actually started'
require_text "$SURFACE" 'root.transitionStarted && !transitionLayer.running' \
    'transition completion can become true before the deferred transition starts'
require_text "$SURFACE" 'function startEntryTransition()' \
    'secure surface has no guarded entry-transition starter'
require_text "$SURFACE" 'function scheduleEntryTransition()' \
    'secure surface has no media-aware pre-roll scheduler'
require_text "$SURFACE" 'scene.backgroundMediaPlaybackAdvanced' \
    'secure surface does not release pre-roll when decoded video advances'
require_text "$SURFACE" 'id: videoPreRollTimeout' \
    'secure surface has no bounded video pre-roll fallback'
require_text "$SURFACE" 'interval: 750' \
    'video pre-roll fallback is not bounded to 750ms'
require_text "$SURFACE" 'repeat: false' \
    'video pre-roll fallback unexpectedly repeats'
require_text "$SURFACE" 'autoStart: false' \
    'entry transition still auto-starts before video can pre-roll'
require_text "$SURFACE" 'externalEntryTransitionRunning: transitionLayer.running' \
    'scene no longer receives the actual transition running state'
require_text "$SURFACE" 'externalEntryTransitionPending: !root.transitionStarted' \
    'scene is not told that presentation is waiting on video pre-roll'
require_text "$SURFACE" 'id: preRollCover' \
    'pre-roll does not keep the frozen desktop visually above the live video'
require_text "$SURFACE" 'sourceItem: transitionBacking' \
    'pre-roll cover does not use the secure frozen desktop transition source'
require_text "$SURFACE" 'visible: !root.transitionStarted' \
    'pre-roll cover can expose the destination before the transition starts'
reject_text "$AUTH" 'backgroundMediaPlaybackAdvanced' \
    'media readiness leaked into authentication ownership'
reject_text "$AUTH" 'videoPreRollTimeout' \
    'video pre-roll lifecycle leaked into authentication ownership'

python3 - "$TRANSITION" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
marker = "Component.onCompleted:"
start = text.find(marker)
if start < 0:
    raise SystemExit("FAIL: transition layer has no completion handler")
block = text[start:]
if "if (root.autoStart)" not in block or "root.restart()" not in block:
    raise SystemExit("FAIL: transition layer no longer preserves auto-start behavior")
if "root.transitionProgress = 1" in block or "root.transitionActive = false" in block:
    raise SystemExit(
        "FAIL: transition completion handler can reset a manually started deferred transition"
    )
PY

printf '%s\n' 'PASS: lockscreen video pre-roll presentation contracts'
