#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
EDITOR="${ROOT}/config/quickshell/awtarchy/LockscreenEditor.qml"
SHELL_QML="${ROOT}/config/quickshell/awtarchy/shell.qml"
QUICK_SETTINGS="${ROOT}/config/quickshell/awtarchy/QuickSettings.qml"
HYPRLAND="${ROOT}/config/hypr/hyprland.lua"
EDITOR_LAUNCHER="${ROOT}/config/hypr/scripts/quickshell_lockscreen_editor.sh"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

require_file() {
    [[ -f "$1" ]] || fail "$2"
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

require_text "$SHELL_QML" 'function openLockscreenEditor(): void { LockscreenEditor.openFocused(); }' \
    'desktop shell has no focused lockscreen-editor IPC action'
require_file "$EDITOR_LAUNCHER" 'lockscreen editor launcher helper is missing'
require_text "$EDITOR_LAUNCHER" 'ipc call control openLockscreenEditor' \
    'lockscreen editor launcher does not call the focused IPC action'
require_text "$HYPRLAND" 'local lockscreen_editor = "~/.config/hypr/scripts/quickshell_lockscreen_editor.sh"' \
    'Hyprland does not define the lockscreen editor launcher'
require_text "$HYPRLAND" 'hl.bind("SUPER + ALT + e", hl.dsp.exec_cmd(lockscreen_editor), {})' \
    'Super+Alt+E is not bound to the lockscreen editor'
require_text "$QUICK_SETTINGS" 'label: "Edit Layout"' \
    'Quick Settings lost the lockscreen Edit Layout control'
require_text "$QUICK_SETTINGS" 'text: "Super + Alt + E"' \
    'Quick Settings does not advertise the direct editor shortcut'

printf 'PASS: lockscreen media/editor polish contracts\n'
