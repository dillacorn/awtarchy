#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCENE="$ROOT/config/quickshell/awtarchy-lock/LockScene.qml"
PREVIEW="$ROOT/config/quickshell/awtarchy/LockPreviewScene.qml"
EDITOR="$ROOT/config/quickshell/awtarchy/LockscreenEditor.qml"
LOCK_SHELL="$ROOT/config/quickshell/awtarchy-lock/shell.qml"
SAVE="$ROOT/config/hypr/scripts/quickshell_lockscreen_editor_save.sh"
PRESENTATION_STATE="$ROOT/config/quickshell/awtarchy-lock/LockscreenPresentationState.js"
PREVIEW_PRESENTATION_STATE="$ROOT/config/quickshell/awtarchy/LockscreenPresentationState.js"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

contains() {
    grep -Fq -- "$2" "$1" || fail "$3"
}

contains "$SCENE" 'property string individualImageReplayId: ""' \
    'shared scene has no targeted custom-image replay id'
contains "$SCENE" 'property int individualImageReplayEpoch: 0' \
    'shared scene has no targeted custom-image replay epoch'
contains "$SCENE" 'readonly property bool customImageAnimationActive:' \
    'custom image movement is not gated by active playback'
contains "$SCENE" 'spawn_timing' \
    'shared scene does not consume per-image spawn timing'
contains "$SCENE" 'during-logo' \
    'shared scene does not support during-logo image entry'
contains "$SCENE" 'after-logo' \
    'shared scene does not support after-logo image entry'
contains "$SCENE" 'root.editorMode && !customImageAnimationActive' \
    'idle editor image presentation is not explicitly settled'
cmp -s "$SCENE" "$PREVIEW" || fail 'secure/editor scene parity drifted'

contains "$EDITOR" 'property string previewIndividualImageReplayId: ""' \
    'editor has no targeted image replay id state'
contains "$EDITOR" 'property int previewIndividualImageReplayEpoch: 0' \
    'editor has no targeted image replay epoch state'
contains "$EDITOR" 'function replaySelectedImageSpawn()' \
    'editor cannot replay only the selected custom image'
contains "$EDITOR" 'spawn_timing: "during-logo"' \
    'new custom images do not default to during-logo timing'
contains "$EDITOR" 'label: "Play Spawn"' \
    'selected image has no individual Play Spawn action'
contains "$EDITOR" 'label: "During logo"' \
    'editor does not expose during-logo image timing'
contains "$EDITOR" 'label: "After logo"' \
    'editor does not expose after-logo image timing'

cmp -s "$PRESENTATION_STATE" "$PREVIEW_PRESENTATION_STATE" || \
    fail 'secure/editor presentation helper parity drifted'
contains "$PRESENTATION_STATE" 'function normalizeSpawnTiming(value)' \
    'shared presentation normalizer has no image spawn timing contract'
contains "$PRESENTATION_STATE" 'normalized.spawn_timing = normalizeSpawnTiming(raw.spawn_timing);' \
    'shared presentation normalizer drops image spawn timing'
contains "$SAVE" 'backend_custom_images=' \
    'save wrapper does not project extended custom-image state through the legacy validator'
contains "$SAVE" 'spawn_timing:' \
    'save wrapper does not merge image spawn timing after validation'
contains "$LOCK_SHELL" 'LockscreenPresentationState.js' \
    'secure state loader is not wired to the shared presentation normalizer'

printf 'PASS: custom-image settled editor preview, individual replay, and spawn timing contracts\n'
