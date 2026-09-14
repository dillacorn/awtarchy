#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
QUICK="$ROOT/config/quickshell/awtarchy/QuickSettings.qml"

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

printf 'PASS: Cursor and Lockscreen Quick Settings headers are aligned, explicit, and Iris-free\n'
