#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCENE="$ROOT/config/quickshell/awtarchy-lock/LockScene.qml"
PREVIEW="$ROOT/config/quickshell/awtarchy/LockPreviewScene.qml"
EDITOR="$ROOT/config/quickshell/awtarchy/LockscreenEditor.qml"
BARSTATE="$ROOT/config/quickshell/awtarchy/BarState.qml"
LOCK_SHELL="$ROOT/config/quickshell/awtarchy-lock/shell.qml"
APP_STATE="$ROOT/config/hypr/scripts/quickshell_application_state.sh"

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
contains "$EDITOR" 'text: "Play Spawn"' \
    'selected image has no individual Play Spawn action'
contains "$EDITOR" 'text: "During logo"' \
    'editor does not expose during-logo image timing'
contains "$EDITOR" 'text: "After logo"' \
    'editor does not expose after-logo image timing'

contains "$BARSTATE" 'spawn_timing' \
    'desktop state normalization drops image spawn timing'
contains "$LOCK_SHELL" 'spawn_timing' \
    'secure state normalization drops image spawn timing'
contains "$APP_STATE" 'spawn_timing' \
    'persistent state backend drops image spawn timing'

printf 'PASS: custom-image settled editor preview, individual replay, and spawn timing contracts\n'
