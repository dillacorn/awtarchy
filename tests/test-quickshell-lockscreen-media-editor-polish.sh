#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
EDITOR="${ROOT}/config/quickshell/awtarchy/LockscreenEditor.qml"
SHELL_QML="${ROOT}/config/quickshell/awtarchy/shell.qml"
QUICK_SETTINGS="${ROOT}/config/quickshell/awtarchy/QuickSettings.qml"
HYPRLAND="${ROOT}/config/hypr/hyprland.lua"
EDITOR_LAUNCHER="${ROOT}/config/hypr/scripts/quickshell_lockscreen_editor.sh"
PICKER="${ROOT}/config/hypr/scripts/quickshell_lockscreen_wallpaper_picker.sh"
RUNTIME="${ROOT}/local/share/awtarchy/awtarchy-runtime.sh"
LOCK_MEDIA="${ROOT}/config/quickshell/awtarchy-lock/LockMedia.qml"
PREVIEW_MEDIA="${ROOT}/config/quickshell/awtarchy/LockMedia.qml"
LOCK_SCENE="${ROOT}/config/quickshell/awtarchy-lock/LockScene.qml"
PREVIEW_SCENE="${ROOT}/config/quickshell/awtarchy/LockPreviewScene.qml"

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

require_text "$PICKER" '--select-only --type all --resume' \
    'Awtwall lockscreen selection is still restricted to still images'
reject_text "$PICKER" '--select-only --type images --resume' \
    'Awtwall lockscreen picker still forces still-image mode'
require_text "$RUNTIME" 'quickshell qt6-multimedia qt6-multimedia-ffmpeg' \
    'mandatory Quickshell package group does not include Qt Multimedia and its FFmpeg backend'

require_file "$LOCK_MEDIA" 'secure lockscreen media renderer is missing'
require_file "$PREVIEW_MEDIA" 'preview lockscreen media renderer is missing'
cmp -s "$LOCK_MEDIA" "$PREVIEW_MEDIA" \
    || fail 'secure and preview media renderers diverge'
require_text "$LOCK_MEDIA" 'import QtMultimedia' \
    'lockscreen media renderer does not import Qt Multimedia'
require_text "$LOCK_MEDIA" 'normalized.endsWith(".gif")' \
    'lockscreen media renderer does not detect GIF media'
require_text "$LOCK_MEDIA" 'normalized.endsWith(".mp4")' \
    'lockscreen media renderer does not detect MP4 media'
require_text "$LOCK_MEDIA" 'AnimatedImage {' \
    'GIF media is not rendered with AnimatedImage'
require_text "$LOCK_MEDIA" 'MediaPlayer {' \
    'MP4 media has no MediaPlayer renderer'
require_text "$LOCK_MEDIA" 'VideoOutput {' \
    'MP4 media has no VideoOutput renderer'
require_text "$LOCK_MEDIA" 'loops: MediaPlayer.Infinite' \
    'lockscreen video does not loop continuously'
require_text "$LOCK_MEDIA" 'autoPlay: true' \
    'lockscreen video does not begin decoding immediately'
require_text "$LOCK_MEDIA" 'activeAudioTrack: -1' \
    'lockscreen video does not explicitly disable embedded audio tracks'
require_text "$LOCK_MEDIA" 'readonly property bool playbackAdvanced: videoFrameCount >= 2' \
    'lockscreen video does not expose decoded-frame advancement'
reject_text "$LOCK_MEDIA" 'AudioOutput' \
    'lockscreen media renderer attaches an audio output'
require_text "$LOCK_SCENE" 'LockMedia {' \
    'shared lockscreen scene does not use the media-aware renderer'
require_text "$LOCK_SCENE" 'id: wallpaperMedia' \
    'background wallpaper is not media-aware'
require_text "$LOCK_SCENE" 'wallpaperMedia.sourceSize' \
    'background geometry does not use media source dimensions'
require_text "$LOCK_SCENE" 'id: customImageSource' \
    'custom media renderer no longer preserves the existing delegate identity'
cmp -s "$LOCK_SCENE" "$PREVIEW_SCENE" \
    || fail 'secure and preview presentation scenes diverge'

printf 'PASS: lockscreen media/editor polish contracts\n'
