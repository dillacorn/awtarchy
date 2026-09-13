#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
EDITOR="${ROOT}/config/quickshell/awtarchy/LockscreenEditor.qml"
QUICK_SETTINGS="${ROOT}/config/quickshell/awtarchy/QuickSettings.qml"
FLYOUT_SETTINGS="${ROOT}/config/quickshell/awtarchy/FlyoutSettings.qml"
LOCK_SCENE="${ROOT}/config/quickshell/awtarchy-lock/LockScene.qml"
PREVIEW_SCENE="${ROOT}/config/quickshell/awtarchy/LockPreviewScene.qml"
PICKER_HELPER="${ROOT}/config/hypr/scripts/quickshell_lockscreen_wallpaper_picker.sh"

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

# External picker lifecycle: the editor remains logically active while its
# fullscreen layer-shell surface is suspended so Awtwall can become visible.
require_text "$EDITOR" 'property bool editingActive: false' \
    'editor has no logical active state independent from window visibility'
require_text "$EDITOR" 'readonly property bool open: editingActive' \
    'editor open state still depends directly on fullscreen window visibility'
require_text "$EDITOR" 'property bool pickerSuspended: false' \
    'editor has no picker-suspension state'
require_text "$EDITOR" 'function suspendForWallpaperPicker()' \
    'editor cannot suspend its fullscreen surface before launching Awtwall'
require_text "$EDITOR" 'function resumeAfterWallpaperPicker()' \
    'editor cannot restore the same draft after Awtwall closes'
require_text "$EDITOR" 'FlyoutManager.releaseOverlay("lockscreen-editor")' \
    'picker suspension does not release the editor overlay'
require_text "$EDITOR" 'wallpaperPickerProcess.exec(["bash", wallpaperPickerBackend])' \
    'picker suspension does not launch the existing selection-only helper'
require_text "$EDITOR" 'enabled: root.open && !root.pickerSuspended' \
    'editor shortcuts can remain active while Awtwall owns keyboard focus'
require_text "$PICKER_HELPER" '--select-only' \
    'Awtarchy picker helper no longer requires Awtwall selection-only mode'
require_text "$PICKER_HELPER" '--select-result' \
    'Awtarchy picker helper no longer uses a detached result file'

# Editor controls must be a compact content-driven dock with mutually exclusive
# drawers rather than the fixed 282/432px settings slab from the first test pass.
require_text "$EDITOR" 'property string activeDrawer: ""' \
    'editor has no compact drawer state'
require_text "$EDITOR" 'function toggleDrawer(name)' \
    'editor has no mutually exclusive drawer toggle'
require_text "$EDITOR" 'id: editorDockContent' \
    'editor has no compact dock content container'
require_text "$EDITOR" 'height: editorDockContent.implicitHeight + 18' \
    'editor dock height is not content-driven'
reject_text "$EDITOR" 'height: 282 +' \
    'oversized fixed editor control slab is still present'
for label in Element Layout Background Weather; do
    require_text "$EDITOR" "label: \"${label}\"" \
        "editor dock is missing the ${label} drawer"
done
require_text "$EDITOR" 'visible: root.activeDrawer === "element"' \
    'element controls are not isolated in their drawer'
require_text "$EDITOR" 'visible: root.activeDrawer === "layout"' \
    'layout controls are not isolated in their drawer'
require_text "$EDITOR" 'visible: root.activeDrawer === "background"' \
    'background controls are not isolated in their drawer'
require_text "$EDITOR" 'visible: root.activeDrawer === "weather"' \
    'weather controls are not isolated in their drawer'

# Awtarchy must be a compact settings hub. Cursor belongs here only, not in the
# generic Quick Settings cog/settings surface.
require_text "$QUICK_SETTINGS" 'property bool awtarchyEditMode: false' \
    'Awtarchy card has no compact edit mode'
require_text "$QUICK_SETTINGS" 'property bool cursorSectionExpanded: false' \
    'Awtarchy card has no independent Cursor subsection state'
require_text "$QUICK_SETTINGS" 'label: root.awtarchyEditMode ? "Done" : "Edit"' \
    'Awtarchy card has no compact Edit/Done control'
require_text "$QUICK_SETTINGS" 'text: "Cursor"' \
    'Awtarchy edit mode has no Cursor subsection'
require_text "$QUICK_SETTINGS" 'text: "Lockscreen"' \
    'Awtarchy edit mode has no Lockscreen subsection'
require_text "$QUICK_SETTINGS" 'visible: root.awtarchyEditMode && root.cursorSectionExpanded' \
    'Cursor settings are not collapsed under the Awtarchy edit section'
require_text "$QUICK_SETTINGS" 'visible: root.awtarchyEditMode && root.lockscreenSectionExpanded' \
    'Lockscreen settings are not collapsed under the Awtarchy edit section'
reject_text "$FLYOUT_SETTINGS" 'CursorThemeSettings {' \
    'generic Quick Settings cog still duplicates Awtarchy cursor controls'
reject_text "$FLYOUT_SETTINGS" 'cursorThemeSection.implicitHeight' \
    'generic settings panel still reserves height for duplicate cursor controls'

# Pointer movement drives one coherent, active-only hover/explosion solver.
require_text "$LOCK_SCENE" 'function triggerLogoExplosion(x, y)' \
    'logo has no explosion entrypoint'
require_text "$LOCK_SCENE" 'id: logoPhysicsTimer' \
    'logo has no bounded shared physics timer'
require_text "$LOCK_SCENE" 'running: root.logoSimulationActive' \
    'logo physics timer is not idle after hover/explosion motion settles'
require_text "$LOCK_SCENE" 'readonly property var explosionOffset:' \
    'wordmark blocks do not consume per-cell explosion offsets'
require_text "$LOCK_SCENE" 'function logoHoverTarget(row, column)' \
    'smooth coherent hover deformation is missing'
require_text "$LOCK_SCENE" 'const weight = unit * unit * (3 - 2 * unit);' \
    'hover field does not blend smoothly across neighboring cells'
reject_text "$LOCK_SCENE" 'ShapePath' \
    'retired connector-line/bridge rendering returned'
reject_text "$LOCK_SCENE" 'logoGroupAudioOffset' \
    'AWTARCHY logo still carries audio-driven block displacement'
cmp -s "$LOCK_SCENE" "$PREVIEW_SCENE" \
    || fail 'secure lock scene and unlocked preview scene diverge'

printf 'PASS: lockscreen runtime polish UI feedback contracts\n'
