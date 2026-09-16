#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
EDITOR="${ROOT}/config/quickshell/awtarchy/LockscreenEditor.qml"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

require_text() {
    local file="$1" text="$2" message="$3"
    grep -Fq -- "$text" "$file" || fail "$message"
}

reject_text() {
    local file="$1" text="$2" message="$3"
    if grep -Fq -- "$text" "$file"; then
        fail "$message"
    fi
}

require_text "$EDITOR" 'readonly property real dragActivationThresholdPx: 5' \
    'editor has no five-pixel drag activation threshold'
require_text "$EDITOR" 'property bool dragActivated: false' \
    'element drag state does not distinguish click selection from dragging'
require_text "$EDITOR" 'if (!dragActivated)' \
    'element movement does not wait for drag activation'
require_text "$EDITOR" 'root.dragActivationThresholdPx' \
    'element drag activation does not use the shared threshold'
reject_text "$EDITOR" 'root.beginHistoryTransaction(); pressOffsetX = mouse.x' \
    'element press still begins movement history before the pointer is dragged'
require_text "$EDITOR" 'sequence: "Ctrl+S"' \
    'lockscreen editor has no Ctrl+S save shortcut'
require_text "$EDITOR" 'onActivated: root.save()' \
    'Ctrl+S is not routed through the existing save path'
require_text "$EDITOR" 'sequence: "Escape"' \
    'lockscreen editor lost the Escape cancel shortcut'
require_text "$EDITOR" 'onActivated: root.close()' \
    'Escape no longer uses the existing cancel/close path'
require_text "$EDITOR" 'Ctrl+S Save' \
    'editor does not advertise its save shortcut'
require_text "$EDITOR" 'Esc Cancel' \
    'editor does not advertise its cancel shortcut'

printf 'PASS: lockscreen media/editor polish contracts\n'
