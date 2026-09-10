#!/usr/bin/env bash
# shellcheck disable=SC2016
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STATE="${ROOT}/config/hypr/scripts/quickshell_application_state.sh"
BAR="${ROOT}/config/quickshell/awtarchy/BarState.qml"
EDITOR="${ROOT}/config/quickshell/awtarchy/LockscreenEditor.qml"
PREVIEW="${ROOT}/config/quickshell/awtarchy/LockPreviewScene.qml"
SECURE="${ROOT}/config/quickshell/awtarchy-lock/LockScene.qml"
LOCK_SHELL="${ROOT}/config/quickshell/awtarchy-lock/shell.qml"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
require_text() {
    local file="$1" text="$2" message="$3"
    grep -Fq -- "$text" "$file" || fail "$message"
}

cmp -s "$PREVIEW" "$SECURE" || fail 'secure and preview presentation scenes diverged'

# Persistent presentation state is strict and backward-compatible.
require_text "$STATE" 'lockscreen_wallpaper_fit: "cover"' 'state default lacks wallpaper fit'
require_text "$STATE" 'lockscreen_wallpaper_focal_x: 0.5' 'state default lacks wallpaper focal x'
require_text "$STATE" 'lockscreen_wallpaper_focal_y: 0.5' 'state default lacks wallpaper focal y'
require_text "$STATE" 'lockscreen_overlay_mode: "none"' 'state default lacks overlay mode'
require_text "$STATE" 'lockscreen_overlay_strength: 0' 'state default lacks overlay strength'
require_text "$STATE" 'lockscreen_wallpaper_blur: 0' 'state default lacks wallpaper blur'
require_text "$STATE" 'LOCKSCREEN_WALLPAPER_FITS_JSON=' 'wallpaper fit enum is not validated'
require_text "$STATE" 'LOCKSCREEN_OVERLAY_MODES_JSON=' 'overlay mode enum is not validated'
require_text "$STATE" 'normalize_unit_interval()' 'focal coordinates have no normalized validator'
require_text "$STATE" 'normalize_percent_integer()' 'overlay/blur percentages have no validator'
require_text "$STATE" 'local wallpaper_fit="${6:-cover}"' 'editor save does not accept wallpaper fit'
require_text "$STATE" 'local focal_x="${7:-0.5}"' 'editor save does not accept wallpaper focal x'
require_text "$STATE" 'local focal_y="${8:-0.5}"' 'editor save does not accept wallpaper focal y'
require_text "$STATE" 'local overlay_mode="${9:-none}"' 'editor save does not accept overlay mode'
require_text "$STATE" 'local overlay_strength="${10:-0}"' 'editor save does not accept overlay strength'
require_text "$STATE" 'local wallpaper_blur="${11:-0}"' 'editor save does not accept wallpaper blur'

# BarState remains the persistent owner exposed to unlocked UI.
require_text "$BAR" 'lockscreen_wallpaper_fit: "cover"' 'BarState default lacks wallpaper fit'
require_text "$BAR" 'lockscreen_wallpaper_focal_x: 0.5' 'BarState default lacks focal x'
require_text "$BAR" 'lockscreen_wallpaper_focal_y: 0.5' 'BarState default lacks focal y'
require_text "$BAR" 'lockscreen_overlay_mode: "none"' 'BarState default lacks overlay mode'
require_text "$BAR" 'lockscreen_overlay_strength: 0' 'BarState default lacks overlay strength'
require_text "$BAR" 'lockscreen_wallpaper_blur: 0' 'BarState default lacks wallpaper blur'
require_text "$BAR" 'function lockscreenWallpaperFit()' 'BarState has no wallpaper fit getter'
require_text "$BAR" 'function lockscreenWallpaperFocalX()' 'BarState has no focal x getter'
require_text "$BAR" 'function lockscreenWallpaperFocalY()' 'BarState has no focal y getter'
require_text "$BAR" 'function lockscreenOverlayMode()' 'BarState has no overlay mode getter'
require_text "$BAR" 'function lockscreenOverlayStrength()' 'BarState has no overlay strength getter'
require_text "$BAR" 'function lockscreenWallpaperBlur()' 'BarState has no wallpaper blur getter'

# Editor draft/history/save owns composition controls and passes them to preview.
require_text "$EDITOR" 'property string draftWallpaperFit: "cover"' 'editor has no wallpaper fit draft'
require_text "$EDITOR" 'property real draftWallpaperFocalX: 0.5' 'editor has no focal x draft'
require_text "$EDITOR" 'property real draftWallpaperFocalY: 0.5' 'editor has no focal y draft'
require_text "$EDITOR" 'property string draftOverlayMode: "none"' 'editor has no overlay-mode draft'
require_text "$EDITOR" 'property int draftOverlayStrength: 0' 'editor has no overlay-strength draft'
require_text "$EDITOR" 'property int draftWallpaperBlur: 0' 'editor has no blur draft'
require_text "$EDITOR" 'wallpaperFit: draftWallpaperFit' 'undo snapshot does not include wallpaper fit'
require_text "$EDITOR" 'wallpaperFocalX: draftWallpaperFocalX' 'undo snapshot does not include focal x'
require_text "$EDITOR" 'wallpaperFocalY: draftWallpaperFocalY' 'undo snapshot does not include focal y'
require_text "$EDITOR" 'overlayMode: draftOverlayMode' 'undo snapshot does not include overlay mode'
require_text "$EDITOR" 'overlayStrength: draftOverlayStrength' 'undo snapshot does not include overlay strength'
require_text "$EDITOR" 'wallpaperBlur: draftWallpaperBlur' 'undo snapshot does not include blur'
require_text "$EDITOR" 'function setDraftWallpaperFit(value)' 'editor cannot switch cover/contain'
require_text "$EDITOR" 'function setDraftWallpaperFocal(x, y)' 'editor cannot change focal point'
require_text "$EDITOR" 'function setDraftOverlay(mode, strength)' 'editor cannot configure overlay'
require_text "$EDITOR" 'function setDraftWallpaperBlur(value)' 'editor cannot configure blur'
require_text "$EDITOR" 'label: "Cover"' 'Cover control is missing'
require_text "$EDITOR" 'label: "Contain"' 'Contain control is missing'
require_text "$EDITOR" 'label: "Darken"' 'Dark overlay control is missing'
require_text "$EDITOR" 'label: "Lighten"' 'Light overlay control is missing'
require_text "$EDITOR" 'text: "Overlay"' 'overlay strength UI is missing'
require_text "$EDITOR" 'text: "Blur"' 'wallpaper blur UI is missing'
require_text "$EDITOR" 'id: wallpaperFocalHandle' 'editor has no draggable wallpaper focal marker'
require_text "$EDITOR" 'root.setDraftWallpaperFocal(' 'focal marker does not update draft focal point'
require_text "$EDITOR" 'wallpaperFit: root.draftWallpaperFit' 'preview does not receive wallpaper fit'
require_text "$EDITOR" 'wallpaperFocalX: root.draftWallpaperFocalX' 'preview does not receive focal x'
require_text "$EDITOR" 'wallpaperFocalY: root.draftWallpaperFocalY' 'preview does not receive focal y'
require_text "$EDITOR" 'overlayMode: root.draftOverlayMode' 'preview does not receive overlay mode'
require_text "$EDITOR" 'overlayStrength: root.draftOverlayStrength' 'preview does not receive overlay strength'
require_text "$EDITOR" 'wallpaperBlur: root.draftWallpaperBlur' 'preview does not receive blur'

# Presentation scene performs composition only. No auth/network ownership moves.
require_text "$PREVIEW" 'import QtQuick.Effects' 'scene does not use QtQuick.Effects for optional blur'
require_text "$PREVIEW" 'required property string wallpaperFit' 'scene has no wallpaper-fit input'
require_text "$PREVIEW" 'required property real wallpaperFocalX' 'scene has no focal-x input'
require_text "$PREVIEW" 'required property real wallpaperFocalY' 'scene has no focal-y input'
require_text "$PREVIEW" 'required property string overlayMode' 'scene has no overlay-mode input'
require_text "$PREVIEW" 'required property real overlayStrength' 'scene has no overlay-strength input'
require_text "$PREVIEW" 'required property real wallpaperBlur' 'scene has no blur input'
require_text "$PREVIEW" 'function wallpaperGeometry()' 'scene has no cover/contain focal geometry helper'
require_text "$PREVIEW" 'root.wallpaperFit === "contain"' 'scene does not distinguish contain from cover'
require_text "$PREVIEW" 'source: wallpaperImage' 'blur effect does not source the wallpaper image'
require_text "$PREVIEW" 'blur: Math.max(0, Math.min(1, root.wallpaperBlur / 100))' 'wallpaper blur is not bounded'
require_text "$PREVIEW" 'id: backgroundOverlay' 'scene has no readability overlay'
require_text "$PREVIEW" 'root.overlayMode === "light" ? "#ffffff" : "#000000"' 'overlay cannot switch dark/light'
require_text "$PREVIEW" 'Math.max(0, Math.min(100, root.overlayStrength)) / 100' 'overlay strength is not bounded'

# Secure shell independently validates persisted presentation fields.
require_text "$LOCK_SHELL" 'readonly property string wallpaperFit:' 'secure shell does not normalize wallpaper fit'
require_text "$LOCK_SHELL" 'readonly property real wallpaperFocalX:' 'secure shell does not normalize focal x'
require_text "$LOCK_SHELL" 'readonly property real wallpaperFocalY:' 'secure shell does not normalize focal y'
require_text "$LOCK_SHELL" 'readonly property string overlayMode:' 'secure shell does not normalize overlay mode'
require_text "$LOCK_SHELL" 'readonly property int overlayStrength:' 'secure shell does not normalize overlay strength'
require_text "$LOCK_SHELL" 'readonly property int wallpaperBlur:' 'secure shell does not normalize wallpaper blur'
require_text "$LOCK_SHELL" 'wallpaperFit: root.wallpaperFit' 'secure scene does not receive wallpaper fit'
require_text "$LOCK_SHELL" 'overlayStrength: root.overlayStrength' 'secure scene does not receive overlay strength'
require_text "$LOCK_SHELL" 'wallpaperBlur: root.wallpaperBlur' 'secure scene does not receive blur'

if grep -Fq 'LockAuth' "$EDITOR"; then
    fail 'unlocked editor must not own authentication'
fi

printf '%s\n' 'PASS: lockscreen wallpaper fit/focal, overlay, blur, persistence, and secure presentation contracts'
