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

# Reversible editor state. History is editor-only, bounded, and drag/flick is
# collapsed into one transaction instead of one snapshot per pointer frame.
require_text 'readonly property int historyLimit: 50' 'editor history is not bounded'
require_text 'property var undoStack: []' 'editor has no undo stack'
require_text 'property var redoStack: []' 'editor has no redo stack'
require_text 'function editorSnapshot()' 'editor has no complete snapshot helper'
require_text 'function restoreEditorSnapshot(snapshot)' 'editor has no snapshot restore helper'
require_text 'function pushUndoSnapshot(snapshot)' 'editor cannot record undo state'
require_text 'function undo()' 'editor has no undo action'
require_text 'function redo()' 'editor has no redo action'
require_text 'function beginHistoryTransaction()' 'editor has no interaction history transaction'
require_text 'function commitHistoryTransaction()' 'editor cannot collapse drag/flick history into one action'
require_text 'historyTransactionActive' 'editor does not track active history transactions'
require_text 'sequence: "Ctrl+Z"' 'Ctrl+Z undo shortcut is missing'
require_text 'sequence: "Ctrl+Shift+Z"' 'Ctrl+Shift+Z redo shortcut is missing'
require_text 'sequence: "Ctrl+Y"' 'Ctrl+Y redo shortcut is missing'

# Multi-selection and group translation remain within each element's existing
# bounds. A normal click replaces selection; Shift toggles membership.
require_text 'property var selectedElements: ["logo"]' 'editor has no multi-selection state'
require_text 'function selectElement(name, additive)' 'editor has no additive selection helper'
require_text 'function selectedContains(name)' 'editor cannot test group membership'
require_text 'function translateSelectedElements(dx, dy, selectPrimary)' 'editor cannot move a selected group'
require_text 'function clampedGroupDelta(dx, dy)' 'group movement does not clamp against all member bounds'
require_text 'function writeDraftPoint(name, x, y, selectPrimary)' 'point writer shadows the selectElement() helper'
require_text 'mouse.modifiers & Qt.ShiftModifier' 'Shift-click multi-selection is missing'
require_text 'root.selectElement(parent.elementName, additive);' 'pointer selection does not use group selection helper'

# Smart alignment uses screen center and peer centers, while Alt explicitly
# disables snapping for free placement. Guide coordinates are editor-only.
require_text 'readonly property real snapThreshold: 0.008' 'editor snap threshold is missing'
require_text 'property real guideX: -1' 'editor has no vertical snap-guide state'
require_text 'property real guideY: -1' 'editor has no horizontal snap-guide state'
require_text 'function snapPoint(name, x, y, bypassSnap)' 'editor has no smart snap helper'
require_text 'const xTargets = [0.5];' 'screen horizontal center is not a snap target'
require_text 'const yTargets = [0.5];' 'screen vertical center is not a snap target'
require_text 'if (!root.selectedContains(peer))' 'selected group members are not excluded from peer snapping'
require_text 'mouse.modifiers & Qt.AltModifier' 'Alt snap bypass is missing'
require_text 'visible: root.guideX >= 0' 'vertical alignment guide is not rendered'
require_text 'visible: root.guideY >= 0' 'horizontal alignment guide is not rendered'

# Precise non-pointer placement reuses bounded group movement.
require_text 'readonly property real keyboardNudge: 0.002' 'fine keyboard nudge size is missing'
require_text 'readonly property real keyboardNudgeLarge: 0.01' 'large keyboard nudge size is missing'
require_text 'function nudgeSelection(dx, dy)' 'editor has no keyboard nudge helper'
require_text 'Keys.onPressed: event => {' 'editor has no arrow-key handling'
require_text 'event.key === Qt.Key_Left' 'left-arrow nudge is missing'
require_text 'event.key === Qt.Key_Right' 'right-arrow nudge is missing'
require_text 'event.key === Qt.Key_Up' 'up-arrow nudge is missing'
require_text 'event.key === Qt.Key_Down' 'down-arrow nudge is missing'
require_text 'event.modifiers & Qt.ShiftModifier' 'Shift-arrow large nudge is missing'
require_text 'function setSelectedCoordinate(axis, percentValue)' 'numeric coordinate entry does not reuse bounded movement'
require_text 'text: "X"' 'numeric X control is missing'
require_text 'text: "Y"' 'numeric Y control is missing'
require_text 'Number(root.primaryPoint().x * 100).toFixed(1)' 'X field does not expose normalized position as percent'
require_text 'Number(root.primaryPoint().y * 100).toFixed(1)' 'Y field does not expose normalized position as percent'

# Inertia must not steal selection and must finish the open history transaction
# only when it actually settles.
require_text 'root.setDraftPointSilently(parent.elementName, clamped.x, clamped.y);' 'flick motion no longer updates position silently'
require_text 'root.commitHistoryTransaction();' 'editor interactions never commit their single undo transaction'

printf '%s\n' 'PASS: lockscreen editor undo/redo, group selection, snapping, guides, nudging, and numeric positioning contracts'
