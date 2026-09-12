#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SURFACE="$ROOT/config/quickshell/awtarchy-lock/LockSurface.qml"
LAYER="$ROOT/config/quickshell/awtarchy-lock/LockTransitionLayer.qml"
PREVIEW_LAYER="$ROOT/config/quickshell/awtarchy/LockPreviewTransitionLayer.qml"
SCENE="$ROOT/config/quickshell/awtarchy-lock/LockScene.qml"
PREVIEW_SCENE="$ROOT/config/quickshell/awtarchy/LockPreviewScene.qml"
EDITOR="$ROOT/config/quickshell/awtarchy/LockscreenEditor.qml"
STATE="$ROOT/config/hypr/scripts/quickshell_application_state.sh"
AUTH="$ROOT/config/quickshell/awtarchy-lock/LockAuth.qml"

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

# Pass A: secure password presentation is immediately usable above the running
# transition, but authentication ownership and logo sequencing do not move.
contains "$SURFACE" 'z: 1100' \
    'password presentation is not explicitly above the transition layer'
rejects "$SURFACE" '* (root.transitionComplete ? 1 : 0)' \
    'password opacity is still gated on transition completion'
rejects "$SURFACE" 'if (root.transitionComplete)' \
    'password focus is still gated on transition completion'
contains "$SURFACE" 'password.forceActiveFocus()' \
    'secure password input has no immediate focus path'
contains "$SURFACE" 'auth.submit(response)' \
    'secure password submission no longer delegates to LockAuth'
contains "$SURFACE" 'auth.statusIsError' \
    'secure password presentation does not consume existing auth failure state'
contains "$SURFACE" 'passwordFailureMaskCount' \
    'wrong-password feedback does not preserve a presentation-only failed mask count'
contains "$SURFACE" '#ff4d4d' \
    'wrong-password password squares have no visible red failure color'
rejects "$SURFACE" 'opacity: password.text.length > 0 ? 0.09 : 0' \
    'password background panel remains visible'
contains "$SURFACE" 'showLogo: root.showLogo && root.transitionComplete' \
    'logo formation is no longer gated until transition completion'
rejects "$AUTH" 'entryTransition' \
    'LockAuth must remain independent of transition presentation'

# Reverse Iris must directly reveal the destination rather than only erasing a
# start texture, and Edges must contract horizontally only. Pixel markers are
# pinned to prevent accidental retuning of the runtime-approved effect.
contains "$LAYER" 'id: irisStartSource' \
    'Reverse Iris has no explicit frozen-desktop base layer'
contains "$LAYER" 'source: root.endSource' \
    'Reverse Iris does not directly reveal the lockscreen destination'
contains "$LAYER" 'maskInverted: false' \
    'Reverse Iris still relies on the ineffective inverted start-source mask'
contains "$LAYER" 'height: root.height' \
    'Edges no longer keeps full output height'
rejects "$LAYER" 'height: Math.max(0, root.height * (1 - root.progress))' \
    'Edges still animates vertically from top/bottom'
contains "$LAYER" '1 + 47 * Math.pow(Math.max(0, root.collapseAmount), 1.35)' \
    'runtime-approved Pixel coarse-factor curve changed'
contains "$LAYER" 'Math.min(1, (root.progress - 0.45) / 0.10)' \
    'runtime-approved Pixel midpoint handoff changed'
cmp -s "$LAYER" "$PREVIEW_LAYER" \
    || fail 'secure/editor transition renderers diverged'

# Pass B: both wallpaper and captured-desktop blur need a real rendered effect
# source. The visible source must not simply remain stacked under its own blur
# output after the entry transition.
contains "$SCENE" 'id: wallpaperBlurEffect' \
    'wallpaper has no actual MultiEffect blur render path'
contains "$SCENE" 'source: wallpaperImage' \
    'wallpaper blur effect is not sourced from the wallpaper image'
contains "$SCENE" 'visible: root.backgroundMode === "wallpaper"' \
    'wallpaper blur effect is not tied to wallpaper presentation'
contains "$SURFACE" 'root.transitionComplete || root.wallpaperBlur <= 0' \
    'captured desktop source is not hidden after handoff when blur is active'
contains "$SURFACE" 'source: desktopCapture' \
    'captured desktop blur is not sourced from the secure capture image'
cmp -s "$SCENE" "$PREVIEW_SCENE" \
    || fail 'secure/editor scene copies diverged'

# Opaque is a reversible toggle using the same persisted background-opacity
# state path plus last-nonopaque metadata, not an independent render value.
contains "$EDITOR" 'property int draftLastBackgroundOpacity' \
    'editor does not retain the last non-opaque background opacity'
contains "$EDITOR" 'function toggleBackgroundOpaque()' \
    'Opaque is not implemented as a reversible toggle'
contains "$STATE" '.lockscreen_background_opacity_previous' \
    'last non-opaque background opacity is not retained in the existing state backend'
contains "$EDITOR" 'String(draftLastBackgroundOpacity)' \
    'editor does not persist the reversible Opaque metadata with the existing save path'

# Every percentage-based lockscreen editor control discovered in the current UI
# must expose direct numeric entry bound to the authoritative setter/state.
for field in \
    elementScaleField elementOpacityField elementStretchXField elementStretchYField \
    visualizerWidthField visualizerHeightField visualizerSensitivityField \
    brightnessField blurField backgroundOpacityField wallpaperFocalXField wallpaperFocalYField; do
    contains "$EDITOR" "id: $field" "missing precise numeric percentage entry: $field"
done
contains "$EDITOR" 'onEditingFinished: root.setDraftScale(' \
    'scale numeric entry is not bound to authoritative scale state'
contains "$EDITOR" 'onEditingFinished: root.setDraftOpacity(' \
    'opacity numeric entry is not bound to authoritative opacity state'
contains "$EDITOR" 'onEditingFinished: root.setDraftBrightness(text)' \
    'brightness numeric entry is not bound to authoritative brightness state'
contains "$EDITOR" 'onEditingFinished: root.setDraftWallpaperBlur(text)' \
    'blur numeric entry is not bound to authoritative blur state'
contains "$EDITOR" 'onEditingFinished: root.setDraftBackgroundOpacity(text)' \
    'background opacity numeric entry is not bound to authoritative opacity state'

# Pass C: one shared draft drives clean preview windows on every non-editing
# display. Selection/group operations remain transient while transforms and
# visibility share the existing atomic history/persistence state.
contains "$EDITOR" 'id: editorPreviewVariants' \
    'editor has no per-output preview variants'
contains "$EDITOR" 'model: Quickshell.screens' \
    'editor previews are not instantiated for all connected outputs'
contains "$EDITOR" 'id: secondaryPreviewScene' \
    'secondary displays do not render the shared draft preview scene'
rejects "$EDITOR" 'AWTARCHY_LOCK_CAPTURE_DIR' \
    'unlocked editor must not consume secure desktop captures'
contains "$EDITOR" 'function selectAllElements()' \
    'Ctrl+A select-all backing operation is missing'
contains "$EDITOR" 'sequence: "Ctrl+A"' \
    'Ctrl+A shortcut is missing'
contains "$EDITOR" 'Qt.ControlModifier' \
    'Ctrl+Mouse1 is not recognized as additive/toggle selection'
contains "$EDITOR" 'function setSelectedVisibility(visible)' \
    'group visibility operation is missing'
contains "$EDITOR" 'function beginGroupResize(' \
    'group proportional scaling operation is missing'
contains "$EDITOR" 'function updateGroupResize(' \
    'group proportional scaling update is missing'
contains "$EDITOR" 'translateSelectedElements(' \
    'group dragging no longer uses the shared relative translation path'
contains "$EDITOR" 'name !== "password"' \
    'group visibility does not preserve Password non-hideable behavior'

# Pass D: freeform and preset rotation use one normalized value. Numeric input
# accepts any finite angle and normalizes it rather than imposing ±180 input.
contains "$EDITOR" 'label: "0°"' \
    'custom-image 0-degree rotation preset is missing'
contains "$EDITOR" 'label: "90°"' \
    'custom-image 90-degree rotation preset is missing'
contains "$EDITOR" 'label: "180°"' \
    'custom-image 180-degree rotation preset is missing'
contains "$EDITOR" 'label: "270°"' \
    'custom-image 270-degree rotation preset is missing'
contains "$EDITOR" 'next[index].rotation = normalizedRotation(rotation)' \
    'rotation controls do not share normalized rotation state'
rejects "$EDITOR" 'numeric < -180 || numeric > 180' \
    'numeric rotation input is still artificially limited to ±180 degrees'
contains "$EDITOR" 'rotation: normalizedRotation(' \
    'custom-image draft cloning does not normalize arbitrary persisted/input rotation'

printf '%s\n' 'PASS: third Hyprland runtime-pass contracts'
