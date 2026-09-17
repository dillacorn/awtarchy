#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
EDITOR="${ROOT}/config/quickshell/awtarchy/LockscreenEditor.qml"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

require_text() {
    local text="$1" message="$2"
    grep -Fq -- "$text" "$EDITOR" || fail "$message"
}

reject_text() {
    local text="$1" message="$2"
    if grep -Fq -- "$text" "$EDITOR"; then
        fail "$message"
    fi
}

require_text 'Shortcut { id: editorSaveShortcut; sequence: "Ctrl+S"; context: Qt.WindowShortcut; enabled: root.open && !root.pickerSuspended; autoRepeat: false; onActivated: root.save() }' \
    'Ctrl+S save is not owned by the focused editor window'
require_text 'Shortcut { id: editorCancelShortcut; sequence: "Escape"; context: Qt.WindowShortcut; enabled: root.open && !root.pickerSuspended; autoRepeat: false; onActivated: root.close() }' \
    'Escape cancel is not owned by the focused editor window'
reject_text 'Shortcut { sequence: "Ctrl+S"; context: Qt.ApplicationShortcut' \
    'Ctrl+S still relies on a singleton-level application shortcut'
reject_text 'Shortcut { sequence: "Escape"; context: Qt.ApplicationShortcut' \
    'Escape still relies on a singleton-level application shortcut'

python3 - "$EDITOR" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
window = text.find("    PanelWindow {\n        id: editorWindow")
save = text.find("Shortcut { id: editorSaveShortcut;")
cancel = text.find("Shortcut { id: editorCancelShortcut;")
focus = text.find("        Rectangle {\n            id: editorFocus", window)
if min(window, save, cancel, focus) < 0:
    raise SystemExit("FAIL: could not locate editor window shortcut structure")
if not (window < save < focus and window < cancel < focus):
    raise SystemExit("FAIL: save/cancel shortcuts are not children of the editor PanelWindow")
PY

printf 'PASS: lockscreen editor save/cancel shortcuts are window-owned\n'
