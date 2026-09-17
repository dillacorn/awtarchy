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
# Pixelated 10% is the stock privacy-oriented default. Smooth blur keeps its
# existing 0-100 response and gains an extended 101-200 range for stronger
# obscuring of text/content under translucent lock backgrounds.
require_text "$STATE" 'LOCKSCREEN_BLUR_STYLES_JSON=' 'blur style allowlist is missing'
require_text "$STATE" 'lockscreen_wallpaper_blur: 10' 'composition defaults lack 10% blur'
require_text "$STATE" 'lockscreen_blur_style: "pixelated"' 'composition defaults lack pixelated blur style'
require_text "$STATE" 'normalize_lockscreen_blur_integer()' 'dedicated 0-200 blur normalizer is missing'
require_text "$STATE" 'local wallpaper_blur="${11:-10}"' 'editor save does not default blur to 10%'
require_text "$STATE" 'local blur_style="${19:-pixelated}"' 'editor save does not default blur style to pixelated'
require_text "$STATE" '6|12|13|14|16|17|18|19|20)' 'save-lockscreen-editor dispatcher does not accept the 19-value payload'
require_text "$STATE" '.lockscreen_blur_style = $blur_style' 'editor save does not persist blur style'
require_text "$STATE" '| .lockscreen_wallpaper_blur = 10' 'presentation reset does not restore 10% blur'
require_text "$STATE" '| .lockscreen_blur_style = "pixelated"' 'presentation reset does not restore pixelated blur style'

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
    cover 0.5 0.5 none 0 200 auto '[]' "$visualizer" 55 pixel 1800 55 smooth
[[ "$(jq -r '.lockscreen_blur_style' "$TMP/cache/awtarchy/quickshell-state.json")" == smooth ]] \
    || fail 'smooth blur style was not persisted'
[[ "$(jq -r '.lockscreen_wallpaper_blur' "$TMP/cache/awtarchy/quickshell-state.json")" == 200 ]] \
    || fail 'extended 200% blur strength was not persisted'
state_before="$(sha256sum "$TMP/cache/awtarchy/quickshell-state.json" | awk '{print $1}')"
if run_state save-lockscreen-editor "$layout" "$visibility" black '#000000' '' \
    cover 0.5 0.5 none 0 201 auto '[]' "$visualizer" 55 pixel 1800 55 smooth >/dev/null 2>&1; then
    fail 'blur strength above 200% was accepted'
fi
[[ "$(sha256sum "$TMP/cache/awtarchy/quickshell-state.json" | awk '{print $1}')" == "$state_before" ]] \
    || fail 'invalid blur strength partially changed persisted state'
if run_state save-lockscreen-editor "$layout" "$visibility" black '#000000' '' \
    cover 0.5 0.5 none 0 45 auto '[]' "$visualizer" 55 pixel 1800 55 bogus >/dev/null 2>&1; then
    fail 'invalid blur style was accepted'
fi
[[ "$(sha256sum "$TMP/cache/awtarchy/quickshell-state.json" | awk '{print $1}')" == "$state_before" ]] \
    || fail 'invalid blur style partially changed persisted state'

# Unlocked state/editor expose the same persisted blur style. Iris is retired;
# the editor and BarState must not advertise the removed transition.
require_text "$BAR" 'lockscreen_wallpaper_blur: 10' 'BarState default lacks 10% blur'
require_text "$BAR" 'lockscreen_blur_style: "pixelated"' 'BarState default lacks pixelated blur style'
require_text "$BAR" 'Math.min(200, Math.round(value))' 'BarState blur getter still caps the persisted value below 200%'
require_text "$BAR" 'function lockscreenBlurStyle()' 'BarState blur style getter is missing'
forbid_text "$BAR" '{ key: "iris"' 'retired Iris transition remains in BarState presets'
require_text "$EDITOR" 'property int draftWallpaperBlur: 10' 'editor does not start at the 10% blur default'
require_text "$EDITOR" 'property string draftBlurStyle: "pixelated"' 'editor does not start with pixelated blur'
require_text "$EDITOR" 'Math.min(200, Math.round(next))' 'editor blur setter still caps below 200%'
require_text "$EDITOR" 'setDraftWallpaperBlur(Number(pointerX) * 200 / Number(trackWidth))' 'editor blur slider does not span 0-200%'
require_text "$EDITOR" 'function resetDraftWallpaperBlur() { setDraftWallpaperBlur(10); }' 'blur reset does not restore 10%'
require_text "$EDITOR" 'blurStyle: draftBlurStyle' 'editor history snapshot does not include blur style'
require_text "$EDITOR" 'function setDraftBlurStyle(value)' 'editor cannot switch blur style'
require_text "$EDITOR" 'label: "Smooth"' 'smooth blur style control is missing'
require_text "$EDITOR" 'label: "Pixelated"' 'pixelated blur style control is missing'
require_text "$EDITOR" 'blurStyle: root.draftBlurStyle' 'editor preview does not receive blur style'
require_text "$EDITOR" 'lockscreen_blur_style: draftBlurStyle' 'profile-based editor save does not include blur style'
forbid_text "$EDITOR" 'Iris Reveal' 'retired Iris transition remains in editor controls'

# Explicit reset controls restore the existing defaults through editor history.
require_text "$EDITOR" 'function resetDraftBrightness()' 'brightness reset helper is missing'
require_text "$EDITOR" 'function resetDraftWallpaperBlur()' 'blur reset helper is missing'
require_text "$EDITOR" 'function resetDraftBackgroundOpacity()' 'background-opacity reset helper is missing'
require_text "$EDITOR" 'function resetDraftWallpaperFocal()' 'wallpaper focal reset helper is missing'
require_text "$EDITOR" 'function resetDraftEntryTransitionDuration()' 'transition-duration reset helper is missing'
require_text "$EDITOR" 'label: "Reset"' 'slider reset buttons are missing'

# Settings-bar movement is vertical-only editor UI state.
require_text "$EDITOR" 'property real settingsBarOffsetY: 0' 'editor settings-bar offset state is missing'
require_text "$EDITOR" 'id: settingsBar' 'editor settings bar has no stable id'
require_text "$EDITOR" 'root.settingsBarOffsetY' 'settings bar drag does not update editor-only offset'
require_text "$EDITOR" 'Math.max(0, Math.min(' 'settings bar movement is not clamped on-screen'
forbid_text "$EDITOR" 'settingsBarOffsetY: root.settingsBarOffsetY' 'settings bar position leaked into presentation snapshot/save data'

# Secure runtime passes the frozen desktop into the same final composition as
# the configured background. Smooth/Pixelated are profile-local per monitor.
require_text "$LOCK_SHELL" 'lockMonitorProfiles = LockscreenPresentationState.migratedMonitorProfiles(parsed);' 'secure shell does not normalize per-display presentation profiles'
require_text "$LOCK_SHELL" 'lockLastEditedProfile = LockscreenPresentationState.lastEditedProfile(parsed);' 'secure shell does not normalize the last-edited fallback profile'
require_text "$SURFACE" 'blurStyle: root.profile.lockscreen_blur_style' 'secure surface does not receive profile-local blur style'
require_text "$SURFACE" 'desktopBackingSource: desktopBacking' 'secure frozen desktop is not passed into final composition'
forbid_text "$SURFACE" 'id: desktopCapturePixelatedBlur' 'desktop still has an independent pixelated blur path'
forbid_text "$SURFACE" 'layer.enabled: root.transitionComplete' 'desktop still has an independent smooth blur path'

require_text "$PREVIEW" 'required property string blurStyle' 'presentation scene has no blur-style input'
require_text "$PREVIEW" 'property Item desktopBackingSource: null' 'presentation scene has no optional frozen desktop input'
require_text "$PREVIEW" 'id: backgroundCompositionContent' 'presentation scene has no final background composition'
require_text "$PREVIEW" 'sourceItem: root.desktopBackingSource' 'final composition cannot consume secure desktop backing'
require_text "$PREVIEW" 'layer.enabled: root.wallpaperBlur > 0' 'final composition has no smooth-blur layer'
require_text "$PREVIEW" 'layer.effect: MultiEffect' 'final composition has no MultiEffect smooth blur'
require_text "$PREVIEW" 'function smoothBlurMaximum()' 'smooth blur does not expose an extended 101-200 strength mapping'
require_text "$PREVIEW" 'blurMax: root.smoothBlurMaximum()' 'smooth blur renderer does not consume the extended radius'
require_text "$PREVIEW" 'id: backgroundCompositionPixelatedBlur' 'final composition has no pixelated blur path'
require_text "$PREVIEW" 'sourceItem: backgroundCompositionContent' 'pixelated blur does not consume final composition'
require_text "$PREVIEW" 'root.blurStyle === "pixelated"' 'final composition pixelated blur is not style-gated'
require_text "$PREVIEW" 'function pixelBlurFactor()' 'pixelated blur has no extended-strength mapping'
require_text "$PREVIEW" 'pixelFactor: root.pixelBlurFactor()' 'pixelated renderer does not consume extended strength'
forbid_text "$PREVIEW" 'id: wallpaperPixelatedBlur' 'wallpaper still has an independent pixelated blur path'

# Pixel/Resolution Collapse is the approved retained pixel transition. Its
# timing and collapse curve are pinned while all Iris renderer state stays gone.
require_text "$LAYER" 'Math.min(1, (root.progress - 0.45) / 0.10)' 'approved Pixel reveal timing changed'
require_text "$LAYER" '+ 47 * Math.pow(Math.max(0, root.collapseAmount), 1.35)' 'approved Pixel collapse curve changed'
forbid_text "$LAYER" 'irisMaskTexture' 'retired Iris mask texture remains in transition renderer'
forbid_text "$LAYER" 'irisMaskShape' 'retired Iris mask shape remains in transition renderer'
forbid_text "$LAYER" 'maskSource: iris' 'retired Iris mask source remains in transition renderer'

printf '%s\n' 'PASS: 0-200 composition blur, pixelated 10% default, resets, retired Iris transition, and Pixel constants'
