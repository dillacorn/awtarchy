#!/usr/bin/env bash
# shellcheck disable=SC2016
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STATE="${ROOT}/config/hypr/scripts/quickshell_application_state.sh"
BAR="${ROOT}/config/quickshell/awtarchy/BarState.qml"
EDITOR="${ROOT}/config/quickshell/awtarchy/LockscreenEditor.qml"
PREVIEW="${ROOT}/config/quickshell/awtarchy/LockPreviewScene.qml"
SECURE="${ROOT}/config/quickshell/awtarchy-lock/LockScene.qml"
SURFACE="${ROOT}/config/quickshell/awtarchy-lock/LockSurface.qml"
LOCK_SHELL="${ROOT}/config/quickshell/awtarchy-lock/shell.qml"
QUICK_SETTINGS="${ROOT}/config/quickshell/awtarchy/QuickSettings.qml"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
require_text() {
    local file="$1" text="$2" message="$3"
    grep -Fq -- "$text" "$file" || fail "$message"
}
forbid_text() {
    local file="$1" text="$2" message="$3"
    if grep -Fq -- "$text" "$file"; then
        fail "$message"
    fi
}

cmp -s "$PREVIEW" "$SECURE" || fail 'secure and preview presentation scenes diverged'

# Persistent presentation state is strict and backward-compatible.
require_text "$STATE" 'lockscreen_wallpaper_fit: "cover"' 'state default lacks wallpaper fit'
require_text "$STATE" 'lockscreen_wallpaper_focal_x: 0.5' 'state default lacks wallpaper focal x'
require_text "$STATE" 'lockscreen_wallpaper_focal_y: 0.5' 'state default lacks wallpaper focal y'
require_text "$STATE" 'lockscreen_overlay_mode: "none"' 'state default lacks overlay mode'
require_text "$STATE" 'lockscreen_overlay_strength: 0' 'state default lacks overlay strength'
require_text "$STATE" 'lockscreen_wallpaper_blur: 0' 'state default lacks wallpaper blur'
require_text "$STATE" 'lockscreen_blur_style: "smooth"' 'state default lacks blur style'
require_text "$STATE" 'LOCKSCREEN_WALLPAPER_FITS_JSON=' 'wallpaper fit enum is not validated'
require_text "$STATE" 'LOCKSCREEN_OVERLAY_MODES_JSON=' 'overlay mode enum is not validated'
require_text "$STATE" 'LOCKSCREEN_BLUR_STYLES_JSON=' 'blur style enum is not validated'
require_text "$STATE" 'normalize_unit_interval()' 'focal coordinates have no normalized validator'
require_text "$STATE" 'normalize_percent_integer()' 'overlay/blur percentages have no validator'
require_text "$STATE" 'local wallpaper_fit="${6:-cover}"' 'editor save does not accept wallpaper fit'
require_text "$STATE" 'local focal_x="${7:-0.5}"' 'editor save does not accept wallpaper focal x'
require_text "$STATE" 'local focal_y="${8:-0.5}"' 'editor save does not accept wallpaper focal y'
require_text "$STATE" 'local overlay_mode="${9:-none}"' 'editor save does not accept overlay mode'
require_text "$STATE" 'local overlay_strength="${10:-0}"' 'editor save does not accept overlay strength'
require_text "$STATE" 'local wallpaper_blur="${11:-0}"' 'editor save does not accept wallpaper blur'
require_text "$STATE" 'local blur_style="${19:-smooth}"' 'editor save does not accept blur style'

# BarState remains the persistent owner exposed to unlocked UI.
require_text "$BAR" 'lockscreen_wallpaper_fit: "cover"' 'BarState default lacks wallpaper fit'
require_text "$BAR" 'lockscreen_wallpaper_focal_x: 0.5' 'BarState default lacks focal x'
require_text "$BAR" 'lockscreen_wallpaper_focal_y: 0.5' 'BarState default lacks focal y'
require_text "$BAR" 'lockscreen_overlay_mode: "none"' 'BarState default lacks overlay mode'
require_text "$BAR" 'lockscreen_overlay_strength: 0' 'BarState default lacks overlay strength'
require_text "$BAR" 'lockscreen_wallpaper_blur: 0' 'BarState default lacks wallpaper blur'
require_text "$BAR" 'lockscreen_blur_style: "smooth"' 'BarState default lacks blur style'
require_text "$BAR" 'function lockscreenWallpaperFit()' 'BarState has no wallpaper fit getter'
require_text "$BAR" 'function lockscreenWallpaperFocalX()' 'BarState has no focal x getter'
require_text "$BAR" 'function lockscreenWallpaperFocalY()' 'BarState has no focal y getter'
require_text "$BAR" 'function lockscreenOverlayMode()' 'BarState has no overlay mode getter'
require_text "$BAR" 'function lockscreenOverlayStrength()' 'BarState has no overlay strength getter'
require_text "$BAR" 'function lockscreenWallpaperBlur()' 'BarState has no wallpaper blur getter'
require_text "$BAR" 'function lockscreenBlurStyle()' 'BarState has no blur style getter'

# Editor draft/history/save owns composition controls and passes them to preview.
require_text "$EDITOR" 'property string draftWallpaperFit: "cover"' 'editor has no wallpaper fit draft'
require_text "$EDITOR" 'property real draftWallpaperFocalX: 0.5' 'editor has no focal x draft'
require_text "$EDITOR" 'property real draftWallpaperFocalY: 0.5' 'editor has no focal y draft'
require_text "$EDITOR" 'property string draftOverlayMode: "none"' 'editor has no overlay-mode draft'
require_text "$EDITOR" 'property int draftOverlayStrength: 0' 'editor has no overlay-strength draft'
require_text "$EDITOR" 'property int draftWallpaperBlur: 0' 'editor has no blur draft'
require_text "$EDITOR" 'property string draftBlurStyle: "smooth"' 'editor has no blur-style draft'
require_text "$EDITOR" 'property bool draftWallpaperBlurExplicit: false' 'editor does not track explicit blur edits'
require_text "$EDITOR" 'wallpaperFit: draftWallpaperFit' 'undo snapshot does not include wallpaper fit'
require_text "$EDITOR" 'wallpaperFocalX: draftWallpaperFocalX' 'undo snapshot does not include focal x'
require_text "$EDITOR" 'wallpaperFocalY: draftWallpaperFocalY' 'undo snapshot does not include focal y'
require_text "$EDITOR" 'overlayMode: draftOverlayMode' 'undo snapshot does not include overlay mode'
require_text "$EDITOR" 'overlayStrength: draftOverlayStrength' 'undo snapshot does not include overlay strength'
require_text "$EDITOR" 'wallpaperBlur: draftWallpaperBlur' 'undo snapshot does not include blur'
require_text "$EDITOR" 'blurStyle: draftBlurStyle' 'undo snapshot does not include blur style'
require_text "$EDITOR" 'function setDraftWallpaperFit(value)' 'editor cannot switch cover/contain'
require_text "$EDITOR" 'function setDraftWallpaperFocal(x, y)' 'editor cannot change focal point'
require_text "$EDITOR" 'function setDraftOverlay(mode, strength)' 'editor cannot configure overlay'
require_text "$EDITOR" 'function setDraftWallpaperBlur(value)' 'editor cannot configure blur'
require_text "$EDITOR" 'function setDraftBlurStyle(value)' 'editor cannot configure blur style'
require_text "$EDITOR" '&& !draftWallpaperBlurExplicit' 'opacity reduction seeds blur even after an explicit blur choice'
require_text "$EDITOR" 'draftWallpaperBlurExplicit = true;' 'explicit blur edits are not remembered during the editor session'
require_text "$EDITOR" 'label: "Cover"' 'Cover control is missing'
require_text "$EDITOR" 'label: "Contain"' 'Contain control is missing'
require_text "$EDITOR" 'function setDraftBrightness(value)' 'direct signed brightness control is missing'
require_text "$EDITOR" 'text: "Brightness"' 'brightness slider UI is missing'
require_text "$EDITOR" 'setBrightnessFromPointer' 'brightness slider is not directly pointer-driven'
require_text "$EDITOR" 'text: "Blur"' 'desktop-backing blur UI is missing'
require_text "$EDITOR" 'label: "Smooth"' 'smooth blur-style control is missing'
require_text "$EDITOR" 'label: "Pixelated"' 'pixelated blur-style control is missing'
require_text "$EDITOR" 'id: wallpaperFocalHandle' 'editor has no draggable wallpaper focal marker'
require_text "$EDITOR" 'root.setDraftWallpaperFocal(' 'focal marker does not update draft focal point'
require_text "$EDITOR" 'wallpaperFit: root.draftWallpaperFit' 'preview does not receive wallpaper fit'
require_text "$EDITOR" 'wallpaperFocalX: root.draftWallpaperFocalX' 'preview does not receive focal x'
require_text "$EDITOR" 'wallpaperFocalY: root.draftWallpaperFocalY' 'preview does not receive focal y'
require_text "$EDITOR" 'overlayMode: root.draftOverlayMode' 'preview does not receive overlay mode'
require_text "$EDITOR" 'overlayStrength: root.draftOverlayStrength' 'preview does not receive overlay strength'
require_text "$EDITOR" 'wallpaperBlur: root.draftWallpaperBlur' 'preview does not receive blur'
require_text "$EDITOR" 'blurStyle: root.draftBlurStyle' 'preview does not receive blur style'

# LockScene independently blurs the wallpaper through a texture provider so
# smooth and pixelated effects can coexist without exposing a sharp source.
require_text "$PREVIEW" 'required property string wallpaperFit' 'scene has no wallpaper-fit input'
require_text "$PREVIEW" 'required property real wallpaperFocalX' 'scene has no focal-x input'
require_text "$PREVIEW" 'required property real wallpaperFocalY' 'scene has no focal-y input'
require_text "$PREVIEW" 'required property string overlayMode' 'scene has no overlay-mode input'
require_text "$PREVIEW" 'required property real overlayStrength' 'scene has no overlay-strength input'
require_text "$PREVIEW" 'required property real wallpaperBlur' 'scene has no blur input for shared editor/runtime state'
require_text "$PREVIEW" 'required property string blurStyle' 'scene has no blur-style input'
require_text "$PREVIEW" 'function wallpaperGeometry()' 'scene has no cover/contain focal geometry helper'
require_text "$PREVIEW" 'root.wallpaperFit === "contain"' 'scene does not distinguish contain from cover'
require_text "$PREVIEW" 'id: wallpaperTexture' 'wallpaper has no texture-provider path'
require_text "$PREVIEW" 'sourceItem: wallpaperImage' 'wallpaper texture does not source the wallpaper image'
require_text "$PREVIEW" 'hideSource: true' 'wallpaper source is not hidden through its texture provider'
require_text "$PREVIEW" 'id: wallpaperSmoothBlur' 'wallpaper smooth blur has no rendered effect path'
require_text "$PREVIEW" 'source: wallpaperTexture' 'wallpaper smooth blur does not source the texture provider'
require_text "$PREVIEW" 'id: wallpaperPixelatedBlur' 'wallpaper pixelated blur has no rendered effect path'
require_text "$PREVIEW" 'root.blurStyle === "pixelated"' 'wallpaper pixelated blur is not style-gated'
require_text "$PREVIEW" 'id: backgroundOverlay' 'scene has no readability overlay'
require_text "$PREVIEW" 'root.overlayMode === "light" ? "#ffffff" : "#000000"' 'overlay cannot switch dark/light'
require_text "$PREVIEW" 'Math.max(0, Math.min(100, root.overlayStrength)) / 100' 'overlay strength is not bounded'
require_text "$PREVIEW" 'opacity: Math.max(0, Math.min(100, root.backgroundOpacity)) / 100' 'scene background opacity is not bounded'

# Secure LockSurface owns the frozen-desktop blur. The capture is always fed
# through a texture provider, then smooth or pixelated composition blur covers
# it underneath every lockscreen background mode.
require_text "$SURFACE" 'import QtQuick.Effects' 'secure surface cannot blur the frozen desktop backing'
require_text "$SURFACE" 'color: "#000000"' 'secure surface does not fail closed to opaque black'
require_text "$SURFACE" 'id: desktopCapture' 'secure surface has no per-output frozen desktop image'
require_text "$SURFACE" 'id: desktopCaptureTexture' 'secure surface has no desktop texture provider'
require_text "$SURFACE" 'sourceItem: desktopCapture' 'desktop texture does not source the frozen capture'
require_text "$SURFACE" 'hideSource: true' 'desktop source is not hidden through its texture provider'
require_text "$SURFACE" 'id: desktopCaptureSmoothBlur' 'secure surface has no smooth desktop blur effect'
require_text "$SURFACE" 'source: desktopCaptureTexture' 'smooth desktop blur does not source the texture provider'
require_text "$SURFACE" 'desktopCapture.status === Image.Ready' 'desktop blur is not gated on a valid loaded capture'
require_text "$SURFACE" 'blurEnabled: true' 'smooth desktop blur is not enabled'
require_text "$SURFACE" 'blur: Math.max(0, Math.min(1, root.wallpaperBlur / 100))' 'desktop blur is not bounded'
require_text "$SURFACE" 'id: desktopCapturePixelatedBlur' 'secure surface has no pixelated desktop blur effect'
require_text "$SURFACE" 'root.blurStyle === "pixelated"' 'pixelated desktop blur is not style-gated'
require_text "$SURFACE" 'textureSize:' 'pixelated desktop blur does not downsample the frozen capture'

# Detailed composition stays editor-owned rather than duplicated in Quick Settings.
forbid_text "$QUICK_SETTINGS" 'Background Opacity' 'Quick Settings duplicates editor-owned background opacity control'
forbid_text "$QUICK_SETTINGS" 'wallpaper blur' 'Quick Settings duplicates editor-owned blur precision control'

# Secure shell independently validates persisted presentation fields.
require_text "$LOCK_SHELL" 'readonly property string wallpaperFit:' 'secure shell does not normalize wallpaper fit'
require_text "$LOCK_SHELL" 'readonly property real wallpaperFocalX:' 'secure shell does not normalize focal x'
require_text "$LOCK_SHELL" 'readonly property real wallpaperFocalY:' 'secure shell does not normalize focal y'
require_text "$LOCK_SHELL" 'readonly property string overlayMode:' 'secure shell does not normalize overlay mode'
require_text "$LOCK_SHELL" 'readonly property int overlayStrength:' 'secure shell does not normalize overlay strength'
require_text "$LOCK_SHELL" 'readonly property int wallpaperBlur:' 'secure shell does not normalize wallpaper blur'
require_text "$LOCK_SHELL" 'readonly property string blurStyle:' 'secure shell does not normalize blur style'
require_text "$LOCK_SHELL" 'wallpaperFit: root.wallpaperFit' 'secure scene does not receive wallpaper fit'
require_text "$LOCK_SHELL" 'overlayStrength: root.overlayStrength' 'secure scene does not receive overlay strength'
require_text "$LOCK_SHELL" 'wallpaperBlur: root.wallpaperBlur' 'secure scene does not receive blur'
require_text "$LOCK_SHELL" 'blurStyle: root.blurStyle' 'secure scene does not receive blur style'

if grep -Fq 'LockAuth' "$EDITOR"; then
    fail 'unlocked editor must not own authentication'
fi

printf '%s\n' 'PASS: lockscreen composition uses secure captured-desktop blur with editor-owned controls'
