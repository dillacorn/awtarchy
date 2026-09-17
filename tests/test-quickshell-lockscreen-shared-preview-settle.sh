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
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")

def between(start, end):
    start_index = text.find(start)
    if start_index < 0:
        raise SystemExit(f"FAIL: missing anchor: {start}")
    end_index = text.find(end, start_index + len(start))
    if end_index < 0:
        raise SystemExit(f"FAIL: missing boundary after {start}: {end}")
    return text[start_index:end_index]

begin_functions = (
    ("function beginRotateElement(", "function updateRotateElement("),
    ("function beginResizeElement(", "function updateResizeElement("),
    ("function beginVisualizerWidthResize(", "function updateVisualizerWidthResize("),
)
for start, end in begin_functions:
    body = between(start, end)
    if "beginSharedPreviewHold();" not in body:
        name = start.split("(", 1)[0].replace("function ", "")
        raise SystemExit(f"FAIL: {name} does not begin the Shared preview hold")

end_functions = (
    ("function endRotateElement(", "function beginGroupResize("),
    ("function endResizeElement(", "function setDraftVisualizerWidth("),
    ("function endVisualizerWidthResize(", "function pointBounds("),
)
for start, end in end_functions:
    body = between(start, end)
    if "settleSharedPreviewHold();" not in body:
        name = start.split("(", 1)[0].replace("function ", "")
        raise SystemExit(f"FAIL: {name} does not settle the Shared preview")

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
