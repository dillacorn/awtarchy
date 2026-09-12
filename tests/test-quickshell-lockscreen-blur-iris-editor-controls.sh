#!/usr/bin/env bash
# shellcheck disable=SC2016
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STATE="$ROOT/config/hypr/scripts/quickshell_application_state.sh"
BAR="$ROOT/config/quickshell/awtarchy/BarState.qml"
EDITOR="$ROOT/config/quickshell/awtarchy/LockscreenEditor.qml"
PREVIEW="$ROOT/config/quickshell/awtarchy/LockPreviewScene.qml"
SECURE="$ROOT/config/quickshell/awtarchy-lock/LockScene.qml"
SURFACE="$ROOT/config/quickshell/awtarchy-lock/LockSurface.qml"
LOCK_SHELL="$ROOT/config/quickshell/awtarchy-lock/shell.qml"
LAYER="$ROOT/config/quickshell/awtarchy-lock/LockTransitionLayer.qml"
PREVIEW_LAYER="$ROOT/config/quickshell/awtarchy/LockPreviewTransitionLayer.qml"

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
cmp -s "$LAYER" "$PREVIEW_LAYER" || fail 'secure and preview transition renderers diverged'

# Blur is one persisted composition effect, independent of background mode.
require_text "$STATE" 'LOCKSCREEN_BLUR_STYLES_JSON=' 'blur style allowlist is missing'
require_text "$STATE" 'lockscreen_blur_style: "smooth"' 'composition defaults lack smooth blur style'
require_text "$STATE" 'validate_lockscreen_blur_style()' 'blur style validator is missing'
require_text "$STATE" 'local blur_style="${19:-smooth}"' 'editor save does not accept blur style as value 19'
require_text "$STATE" '6|12|13|14|16|17|18|19|20)' 'save-lockscreen-editor dispatcher does not accept the 19-value payload'
require_text "$STATE" '.lockscreen_blur_style = $blur_style' 'editor save does not persist blur style'
require_text "$STATE" '| .lockscreen_blur_style = "smooth"' 'presentation reset does not restore smooth blur style'

TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT
mkdir -p "$TMP/cache/awtarchy" "$TMP/home"
printf '%s\n' '{}' >"$TMP/cache/awtarchy/quickshell-state.json"
run_state() {
    HOME="$TMP/home" XDG_CACHE_HOME="$TMP/cache" bash "$STATE" "$@"
}
layout='{"logo":{"x":0.5,"y":0.34},"time":{"x":0.5,"y":0.51},"date":{"x":0.5,"y":0.555},"username":{"x":0.5,"y":0.595},"weather":{"x":0.5,"y":0.635},"password":{"x":0.5,"y":0.7}}'
visibility='{"logo":true,"time":false,"date":false,"username":false,"weather":false,"password":true}'
visualizer='{"enabled":false,"shape":"straight","sensitivity":140,"performance":"balanced"}'
run_state save-lockscreen-editor "$layout" "$visibility" black '#000000' '' \
    cover 0.5 0.5 none 0 45 auto '[]' "$visualizer" 55 pixel 1800 55 pixelated
[[ "$(jq -r '.lockscreen_blur_style' "$TMP/cache/awtarchy/quickshell-state.json")" == pixelated ]] \
    || fail 'pixelated blur style was not persisted'
[[ "$(jq -r '.lockscreen_wallpaper_blur' "$TMP/cache/awtarchy/quickshell-state.json")" == 45 ]] \
    || fail 'blur strength was not persisted with pixelated style'
state_before="$(sha256sum "$TMP/cache/awtarchy/quickshell-state.json" | awk '{print $1}')"
if run_state save-lockscreen-editor "$layout" "$visibility" black '#000000' '' \
    cover 0.5 0.5 none 0 45 auto '[]' "$visualizer" 55 pixel 1800 55 bogus >/dev/null 2>&1; then
    fail 'invalid blur style was accepted'
fi
[[ "$(sha256sum "$TMP/cache/awtarchy/quickshell-state.json" | awk '{print $1}')" == "$state_before" ]] \
    || fail 'invalid blur style partially changed persisted state'

# Unlocked state/editor expose the same persisted blur style.
require_text "$BAR" 'lockscreen_blur_style: "smooth"' 'BarState default lacks blur style'
require_text "$BAR" 'function lockscreenBlurStyle()' 'BarState blur style getter is missing'
require_text "$BAR" '{ key: "iris", label: "Iris Reveal" }' 'transition preset still calls iris Reverse Iris'
require_text "$EDITOR" 'property string draftBlurStyle: "smooth"' 'editor has no blur-style draft'
require_text "$EDITOR" 'blurStyle: draftBlurStyle' 'editor history snapshot does not include blur style'
require_text "$EDITOR" 'function setDraftBlurStyle(value)' 'editor cannot switch blur style'
require_text "$EDITOR" 'label: "Smooth"' 'smooth blur style control is missing'
require_text "$EDITOR" 'label: "Pixelated"' 'pixelated blur style control is missing'
require_text "$EDITOR" 'blurStyle: root.draftBlurStyle' 'editor preview does not receive blur style'
require_text "$EDITOR" 'String(draftBlurStyle)' 'editor save payload does not include blur style'

# Explicit reset controls restore the existing defaults through editor history.
require_text "$EDITOR" 'function resetDraftBrightness()' 'brightness reset helper is missing'
require_text "$EDITOR" 'function resetDraftWallpaperBlur()' 'blur reset helper is missing'
require_text "$EDITOR" 'function resetDraftBackgroundOpacity()' 'background-opacity reset helper is missing'
require_text "$EDITOR" 'function resetDraftWallpaperFocal()' 'wallpaper focal reset helper is missing'
require_text "$EDITOR" 'function resetDraftEntryTransitionDuration()' 'transition-duration reset helper is missing'
require_text "$EDITOR" 'label: "Reset"' 'slider reset buttons are missing'

# Alt-drag moves the editor settings bar vertically only; it is editor UI state.
require_text "$EDITOR" 'property real settingsBarOffsetY: 0' 'editor settings-bar offset state is missing'
require_text "$EDITOR" 'id: settingsBar' 'editor settings bar has no stable id'
require_text "$EDITOR" 'mouse.modifiers & Qt.AltModifier' 'settings bar drag is not gated by Alt'
require_text "$EDITOR" 'root.settingsBarOffsetY' 'settings bar drag does not update editor-only offset'
require_text "$EDITOR" 'Math.max(0, Math.min(' 'settings bar movement is not clamped on-screen'
forbid_text "$EDITOR" 'settingsBarOffsetY: root.settingsBarOffsetY' 'settings bar position leaked into presentation snapshot/save data'

# Secure runtime always renders the captured desktop through a texture source,
# so blur still exists with black/color backgrounds and underneath wallpaper.
require_text "$LOCK_SHELL" 'property string lockBlurStyle: "smooth"' 'secure shell has no blur-style state'
require_text "$LOCK_SHELL" 'readonly property string blurStyle:' 'secure shell does not normalize blur style'
require_text "$LOCK_SHELL" 'blurStyle: root.blurStyle' 'secure surface does not receive blur style'
require_text "$SURFACE" 'required property string blurStyle' 'secure surface has no blur-style input'
require_text "$SURFACE" 'id: desktopCaptureTexture' 'desktop capture has no texture-provider path'
require_text "$SURFACE" 'sourceItem: desktopCapture' 'desktop texture does not source the captured Hyprland frame'
require_text "$SURFACE" 'hideSource: true' 'captured desktop source is not hidden through the texture provider'
require_text "$SURFACE" 'id: desktopCaptureSmoothBlur' 'smooth desktop blur path is missing'
require_text "$SURFACE" 'id: desktopCapturePixelatedBlur' 'pixelated desktop blur path is missing'
require_text "$SURFACE" 'root.blurStyle === "pixelated"' 'desktop blur style does not switch to pixelated rendering'
require_text "$SURFACE" 'textureSize:' 'pixelated desktop blur does not downsample the captured session'

# Wallpaper uses the same blur strength/style, independently layered above the
# already blurred captured desktop.
require_text "$PREVIEW" 'required property string blurStyle' 'presentation scene has no blur-style input'
require_text "$PREVIEW" 'id: wallpaperTexture' 'wallpaper has no texture-provider path'
require_text "$PREVIEW" 'sourceItem: wallpaperImage' 'wallpaper texture does not source wallpaper image'
require_text "$PREVIEW" 'id: wallpaperSmoothBlur' 'smooth wallpaper blur path is missing'
require_text "$PREVIEW" 'id: wallpaperPixelatedBlur' 'pixelated wallpaper blur path is missing'
require_text "$PREVIEW" 'root.blurStyle === "pixelated"' 'wallpaper blur style does not switch to pixelated rendering'

# Iris Reveal must have a live texture-provider mask instead of a hidden source
# item that can render as an empty mask on Qt/Quickshell.
require_text "$LAYER" 'id: irisMaskTexture' 'Iris Reveal has no mask texture provider'
require_text "$LAYER" 'sourceItem: irisMaskShape' 'Iris Reveal mask texture does not source the circle'
require_text "$LAYER" 'hideSource: true' 'Iris Reveal mask source is not hidden safely'
require_text "$LAYER" 'maskSource: irisMaskTexture' 'Iris Reveal does not consume the live mask texture'
forbid_text "$LAYER" 'id: irisMaskShape\n        anchors.fill: parent\n        visible: false' 'Iris Reveal still disables its mask source'
require_text "$EDITOR" 'label: "Iris Reveal"' 'editor transition control still says Reverse Iris'

printf '%s\n' 'PASS: composition blur styles, explicit resets, Iris Reveal, and Alt-drag editor bar contracts'