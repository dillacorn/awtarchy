#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
EDITOR="$ROOT/config/quickshell/awtarchy/LockscreenEditor.qml"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
require_text() { grep -Fq -- "$2" "$1" || fail "$3"; }

require_text "$EDITOR" 'property var settledSharedProfile:' 'editor has no settled Shared profile snapshot'
require_text "$EDITOR" 'property bool sharedPreviewHoldActive:' 'editor has no Shared preview hold state'
require_text "$EDITOR" 'function beginSharedPreviewHold()' 'editor cannot freeze passive Shared previews'
require_text "$EDITOR" 'function settleSharedPreviewHold()' 'editor cannot publish the settled Shared preview'
require_text "$EDITOR" 'if (sharedPreviewHoldActive)' 'effective profile resolver does not gate passive Shared previews during manipulation'
require_text "$EDITOR" 'return cloneSnapshot(settledSharedProfile);' 'passive Shared previews do not use the settled snapshot'
require_text "$EDITOR" 'settledSharedProfile = cloneSnapshot(profileFromDraftScalars())' 'final Shared profile is not published after manipulation'

python3 - "$EDITOR" <<'PY'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")

# Continuous direct manipulation must freeze passive Shared previews.
for fn in ("beginRotateElement", "beginResizeElement", "beginVisualizerWidthResize"):
    match = re.search(rf"function {fn}\([^)]*\)\s*\{{(.*?)\n\s*\}}", text, re.S)
    if not match or "beginSharedPreviewHold();" not in match.group(1):
        raise SystemExit(f"FAIL: {fn} does not begin the Shared preview hold")

for fn in ("endRotateElement", "endResizeElement", "endVisualizerWidthResize"):
    match = re.search(rf"function {fn}\([^)]*\)\s*\{{(.*?)\n\s*\}}", text, re.S)
    if not match or "settleSharedPreviewHold();" not in match.group(1):
        raise SystemExit(f"FAIL: {fn} does not settle the Shared preview")

# Element drag and inertia are inline MouseArea/Timer handlers. The hold must
# begin only after the drag threshold is crossed and remain until inertia ends.
drag_anchor = 'dragActivated = true;'
idx = text.find(drag_anchor)
if idx < 0 or 'beginSharedPreviewHold();' not in text[idx:idx + 700]:
    raise SystemExit('FAIL: element drag does not freeze passive Shared previews')

inertia_anchor = 'if (Math.sqrt(parent.flickVelocityX * parent.flickVelocityX + parent.flickVelocityY * parent.flickVelocityY) < root.flickStopSpeed)'
idx = text.find(inertia_anchor)
if idx < 0 or 'settleSharedPreviewHold();' not in text[idx:idx + 1000]:
    raise SystemExit('FAIL: inertia completion does not publish final Shared position')

print('PASS: shared lockscreen previews settle after direct manipulation')
PY
