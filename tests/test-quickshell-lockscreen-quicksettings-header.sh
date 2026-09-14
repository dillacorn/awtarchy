#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
QUICK="$ROOT/config/quickshell/awtarchy/QuickSettings.qml"
LOCK="$ROOT/config/hypr/scripts/awtarchy_lock.sh"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

contains() {
    grep -Fq -- "$2" "$1" || fail "$3"
}

contains "$QUICK" 'readonly property int sectionActionColumnWidth:' \
    'Quick Settings has no shared section action-column width'
contains "$QUICK" 'id: cursorSectionActions' \
    'Cursor header has no aligned action column'
contains "$QUICK" 'id: lockscreenSectionActions' \
    'Lockscreen header has no aligned action column'
contains "$QUICK" 'label: root.cursorSectionOpen ? "Collapse Cursor" : "Expand Cursor"' \
    'Cursor expand action is still ambiguous'
contains "$QUICK" 'label: root.lockscreenSectionOpen ? "Collapse Lockscreen" : "Expand Lockscreen"' \
    'Lockscreen expand action is still ambiguous'

if grep -Fq -- 'label: "Reverse Iris"' "$QUICK" \
        || grep -Fq -- '"set-lockscreen-entry-transition", "iris"' "$QUICK"; then
    fail 'retired Iris transition is still exposed in Quick Settings'
fi

python3 - "$QUICK" <<'PY' || fail 'Cursor and Lockscreen action columns do not share the same alignment contract'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text()
for marker in ('id: cursorSectionActions', 'id: lockscreenSectionActions'):
    start = text.index(marker)
    block = text[start:text.index('\n                    }', start) + 22]
    for needle in (
        'Layout.preferredWidth: root.sectionActionColumnWidth',
        'Layout.alignment: Qt.AlignRight',
    ):
        if needle not in block:
            raise SystemExit(1)
PY

# The capture-visibility toggle is an ordinary compact action, like Expand
# Lockscreen and Edit Layout. It must not stretch across the entire grid cell.
python3 - "$QUICK" <<'PY' || fail 'Hide-before-capture toggle is still stretched wider than neighboring actions'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text()
match = re.search(
    r'SettingsButton\s*\{\s*'
    r'label:\s*QuickSettings\.lockscreenHideQuickshellBeforeCapture\s*\?\s*"On"\s*:\s*"Off"'
    r'.*?\n\s*\}',
    text,
    re.S,
)
if not match:
    raise SystemExit(1)
if 'Layout.fillWidth: true' in match.group(0):
    raise SystemExit(1)
PY

# Lock capture must consult the live QML preference before falling back to the
# asynchronously persisted state. When hiding is requested, capture must also
# wait until the actual Quick Settings backing window is gone rather than
# assuming a fixed sleep was enough for the compositor to unmap it.
contains "$QUICK" 'function prepareLockCapture(): bool' \
    'Quick Settings exposes no live pre-lock capture preparation IPC'
contains "$QUICK" 'if (!QuickSettings.lockscreenHideQuickshellBeforeCapture)' \
    'live pre-lock capture preparation ignores the in-memory hide preference'
contains "$QUICK" 'QuickSettings.close();' \
    'live pre-lock capture preparation does not close Quick Settings'
contains "$QUICK" 'function lockCaptureHidden(): bool' \
    'Quick Settings exposes no backing-window readiness check for lock capture'
contains "$QUICK" 'return !quickSettingsWindow.backingWindowVisible;' \
    'lock capture readiness does not verify the actual backing window is hidden'
contains "$LOCK" 'ipc call quicksettings prepareLockCapture' \
    'lock helper never consults live Quick Settings state before capture'
contains "$LOCK" 'ipc call quicksettings lockCaptureHidden' \
    'lock helper never verifies Quick Settings has actually unmapped before capture'

python3 - "$LOCK" <<'PY' || fail 'live Quick Settings preparation/readiness is not ordered before secure desktop capture'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text()
prepare = text.index('ipc call quicksettings prepareLockCapture')
persisted = text.index('get lockscreen_hide_quickshell_before_capture')
ready = text.index('ipc call quicksettings lockCaptureHidden')
capture = text.index('"$capture_helper" prepare')
if not (prepare < persisted < ready < capture):
    raise SystemExit(1)
PY

printf 'PASS: Lockscreen Quick Settings header, compact capture toggle, and pre-capture hiding contracts\n'
