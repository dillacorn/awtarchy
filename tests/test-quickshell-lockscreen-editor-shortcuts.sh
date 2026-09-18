#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
EDITOR="${ROOT}/config/quickshell/awtarchy/LockscreenEditor.qml"
SHELL_QML="${ROOT}/config/quickshell/awtarchy/shell.qml"
HYPRLAND="${ROOT}/config/hypr/hyprland.lua"
EDITOR_LAUNCHER="${ROOT}/config/hypr/scripts/quickshell_lockscreen_editor.sh"

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

require_text "$EDITOR" 'Shortcut { id: editorSaveShortcut; sequence: "Ctrl+S"; context: Qt.WindowShortcut; enabled: root.open && !root.pickerSuspended; autoRepeat: false; onActivated: root.save() }' \
    'Ctrl+S save is not owned by the focused editor window'
require_text "$EDITOR" 'Shortcut { id: editorCancelShortcut; sequence: "Escape"; context: Qt.WindowShortcut; enabled: root.open && !root.pickerSuspended; autoRepeat: false; onActivated: root.handleEscape() }' \
    'Escape cancel is not owned by the focused editor window'
require_text "$EDITOR" 'function handleEscape() {' \
    'Escape does not route through modal-aware editor cancellation'
require_text "$EDITOR" 'if (savedConfigurationNameDialogMode.length > 0) {' \
    'Escape does not cancel the saved-configuration naming dialog first'
require_text "$EDITOR" 'if (savedConfigurationConfirmMode.length > 0) {' \
    'Escape does not cancel saved-configuration confirmations first'
require_text "$EDITOR" 'onAccepted: root.confirmSavedConfigurationNameDialog()' \
    'Enter does not submit the saved-configuration naming field'
require_text "$EDITOR" 'Shortcut { id: savedConfigurationConfirmReturnShortcut; sequence: "Return"; context: Qt.WindowShortcut; enabled: root.open && !root.pickerSuspended && root.savedConfigurationConfirmMode.length > 0; autoRepeat: false; onActivated: root.confirmSavedConfigurationConfirmDialog() }' \
    'Return does not confirm saved-configuration delete/overwrite dialogs'
require_text "$EDITOR" 'Shortcut { id: savedConfigurationConfirmEnterShortcut; sequence: "Enter"; context: Qt.WindowShortcut; enabled: root.open && !root.pickerSuspended && root.savedConfigurationConfirmMode.length > 0; autoRepeat: false; onActivated: root.confirmSavedConfigurationConfirmDialog() }' \
    'Enter does not confirm saved-configuration delete/overwrite dialogs'
require_text "$EDITOR" 'function confirmSavedConfigurationConfirmDialog() {' \
    'saved-configuration confirmation dialogs have no shared keyboard-confirm action'
reject_text "$EDITOR" 'Shortcut { sequence: "Ctrl+S"; context: Qt.ApplicationShortcut' \
    'Ctrl+S still relies on a singleton-level application shortcut'
reject_text "$EDITOR" 'Shortcut { sequence: "Escape"; context: Qt.ApplicationShortcut' \
    'Escape still relies on a singleton-level application shortcut'

require_text "$SHELL_QML" 'function toggleLockscreenEditor(): void { if (LockscreenEditor.open) LockscreenEditor.close(); else LockscreenEditor.openFocused(); }' \
    'lockscreen editor IPC action is not a toggle'
reject_text "$SHELL_QML" 'function openLockscreenEditor(): void { LockscreenEditor.openFocused(); }' \
    'lockscreen editor IPC action is still open-only'
require_text "$EDITOR_LAUNCHER" 'ipc call control toggleLockscreenEditor' \
    'lockscreen editor launcher does not call toggleLockscreenEditor'
reject_text "$EDITOR_LAUNCHER" 'ipc call control openLockscreenEditor' \
    'lockscreen editor launcher still calls openLockscreenEditor'
[[ "$(grep -Fc -- 'hl.bind("SUPER + ALT + e", hl.dsp.exec_cmd(lockscreen_editor), {})' "$HYPRLAND")" -eq 2 ]] \
    || fail 'Super+Alt+E is not bound in both default and noalt modes'

python3 - "$EDITOR" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
window = text.find("    PanelWindow {\n        id: editorWindow")
save = text.find("Shortcut { id: editorSaveShortcut;")
confirm_return = text.find("Shortcut { id: savedConfigurationConfirmReturnShortcut;")
confirm_enter = text.find("Shortcut { id: savedConfigurationConfirmEnterShortcut;")
cancel = text.find("Shortcut { id: editorCancelShortcut;")
focus = text.find("        Rectangle {\n            id: editorFocus", window)
if min(window, save, confirm_return, confirm_enter, cancel, focus) < 0:
    raise SystemExit("FAIL: could not locate editor window shortcut structure")
if not (window < save < focus and window < confirm_return < focus
        and window < confirm_enter < focus and window < cancel < focus):
    raise SystemExit("FAIL: editor/modal shortcuts are not children of the editor PanelWindow")
PY

printf 'PASS: lockscreen editor shortcuts and toggle routing are correct\n'
