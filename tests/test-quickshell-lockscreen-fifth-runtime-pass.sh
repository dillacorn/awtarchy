#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STATE="$ROOT/config/hypr/scripts/quickshell_application_state.sh"
LOCK_MANAGER="$ROOT/config/hypr/scripts/awtarchy_lock.sh"
BAR_STATE="$ROOT/config/quickshell/awtarchy/BarState.qml"
QUICK_SETTINGS="$ROOT/config/quickshell/awtarchy/QuickSettings.qml"
EDITOR="$ROOT/config/quickshell/awtarchy/LockscreenEditor.qml"
SCENE="$ROOT/config/quickshell/awtarchy-lock/LockScene.qml"
PREVIEW_SCENE="$ROOT/config/quickshell/awtarchy/LockPreviewScene.qml"
SURFACE="$ROOT/config/quickshell/awtarchy-lock/LockSurface.qml"
LAYER="$ROOT/config/quickshell/awtarchy-lock/LockTransitionLayer.qml"
PREVIEW_LAYER="$ROOT/config/quickshell/awtarchy/LockPreviewTransitionLayer.qml"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

contains() {
    local file="$1" needle="$2" message="$3"
    grep -Fq -- "$needle" "$file" || fail "$message"
}

rejects() {
    local file="$1" needle="$2" message="$3"
    ! grep -Fq -- "$needle" "$file" || fail "$message"
}

# Fifth maintainer runtime pass: Iris Reveal is retired everywhere in the
# production transition path. Unknown/stale values must normalize to Fade.
contains "$STATE" 'LOCKSCREEN_ENTRY_TRANSITIONS_JSON=' \
    'state backend no longer declares the supported transition set'
rejects "$STATE" '"iris"' \
    'state backend still accepts or persists Iris Reveal'
rejects "$BAR_STATE" 'Iris Reveal' \
    'BarState still exposes Iris Reveal'
rejects "$EDITOR" '"iris"' \
    'editor still exposes or replays Iris Reveal'
rejects "$SCENE" '"iris"' \
    'scene still contains Iris-specific presentation logic'
rejects "$LAYER" 'iris' \
    'secure transition renderer still contains Iris-specific code'
contains "$LAYER" 'return ["fade", "pixel", "edges", "wipe"].indexOf(value) >= 0' \
    'transition renderer does not normalize stale/unknown modes to the supported set'
contains "$LAYER" 'Math.min(1, (root.progress - 0.45) / 0.10)' \
    'runtime-approved Pixel midpoint handoff changed'
contains "$LAYER" '+ 47 * Math.pow(Math.max(0, root.collapseAmount), 1.35)' \
    'runtime-approved Pixel coarse-factor curve changed'
cmp -s "$LAYER" "$PREVIEW_LAYER" \
    || fail 'secure/editor transition renderers diverged'

# Editor entry is configuration UI, not a lock event. Opening it must use only
# its quick editor fade and must not implicitly replay the configured transition.
contains "$EDITOR" 'id: editorEntranceFade' \
    'editor has no dedicated quick entrance fade'
contains "$EDITOR" 'duration: root.editorEntranceFadeDuration' \
    'editor entrance does not use its dedicated short fade duration'
contains "$LAYER" 'property bool autoStart: true' \
    'transition layer has no explicit auto-start control'
contains "$EDITOR" 'autoStart: false' \
    'editor transition preview still auto-starts on editor entry'
rejects "$EDITOR" 'closeAfterSave' \
    'Save still schedules editor dismissal'
contains "$EDITOR" 'root.statusMessage = exitCode === 0 ? "Saved"' \
    'Save no longer reports successful persistence while staying in editor'

# The settings bar now moves with plain Mouse1 only on its unused background.
# Child controls remain on top of the background MouseArea, and horizontal bar
# movement is intentionally absent. Hyprland runtime remains decisive.
contains "$EDITOR" 'id: settingsBarDragArea' \
    'settings bar has no blank-area Mouse1 drag surface'
contains "$EDITOR" 'cursorShape: Qt.SizeVerCursor' \
    'settings bar drag does not expose vertical-only movement'
contains "$EDITOR" 'root.settingsBarOffsetY = Math.max(0, Math.min(limit,' \
    'settings bar drag does not clamp its vertical offset to the editor viewport'
rejects "$EDITOR" 'id: settingsBarAltDrag' \
    'legacy Alt settings-bar drag still exists'
rejects "$EDITOR" 'acceptedModifiers: Qt.AltModifier' \
    'settings-bar movement still requires Alt'

# Interrupted logo hover owns an explicit return-to-rest state. Pointer exit
# must request that return without sharing the click/explosion trigger path.
contains "$SCENE" 'property bool logoReturnPending: false' \
    'logo hover has no explicit return-to-rest ownership state'
contains "$SCENE" 'function handlePointerExit()' \
    'logo hover has no pointer-exit return path'
contains "$SURFACE" 'onExited: scene.handlePointerExit()' \
    'secure pointer surface does not notify the logo state machine on exit'
rejects "$SURFACE" 'onExited: scene.handlePointerClick' \
    'ordinary hover exit is incorrectly coupled to logo explosion clicks'
cmp -s "$SCENE" "$PREVIEW_SCENE" \
    || fail 'secure/editor scene copies diverged'

# Power Menu locking now uses the clean snapshot staged before SUPER+P reveals the menu.
rejects "$STATE" 'lockscreen_hide_lock_settings_before_capture' \
    'retired capture-hide preference remains in shared state'
rejects "$QUICK_SETTINGS" 'Hide Quickshell Lock Settings Before Lock Capture' \
    'retired capture-hide control remains in Quick Settings'
contains "$LOCK_MANAGER" 'lock-prepared)' \
    'real lock path has no staged Power Menu capture mode'
contains "$LOCK_MANAGER" 'consume-prepared' \
    'staged Power Menu lock does not consume its prepared capture'
contains "$LOCK_MANAGER" 'quickshell_lockscreen_capture.sh' \
    'real lock path no longer uses the secure frozen capture helper'

# Each custom image owns one spawn-animation value throughout normalization,
# editor state, persistence, preview and secure rendering.
contains "$STATE" 'LOCKSCREEN_CUSTOM_IMAGE_SPAWNS_JSON=' \
    'state backend has no supported custom-image spawn-animation set'
contains "$STATE" '"spawn_animation"' \
    'custom-image persistence does not include per-image spawn animation'
contains "$BAR_STATE" 'spawn_animation' \
    'BarState does not normalize per-image spawn animation'
for label in \
    'No Spawn Animation' \
    'Pixel Warp In' \
    'Fly In From Closest Edge' \
    'Fly In From Top' \
    'Fly In From Bottom' \
    'Fly In From Left' \
    'Fly In From Right'; do
    contains "$EDITOR" "$label" "missing custom-image spawn option: $label"
done
contains "$SCENE" 'function customImageSpawnMode(' \
    'secure renderer has no per-image spawn-animation mode normalization'
contains "$SCENE" 'function customImageSpawnOffset(' \
    'secure renderer has no closest/forced-edge fly-in geometry'
contains "$SCENE" 'spawn_animation' \
    'secure renderer does not consume the persisted per-image spawn animation'

printf '%s\n' 'quickshell lockscreen fifth runtime pass contracts: PASS'
