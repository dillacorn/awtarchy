#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SURFACE="$ROOT/config/quickshell/awtarchy-lock/LockSurface.qml"
SCENE="$ROOT/config/quickshell/awtarchy-lock/LockScene.qml"
PREVIEW="$ROOT/config/quickshell/awtarchy/LockPreviewScene.qml"

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

# Smooth composition blur must transform the captured Hyprland frame itself.
# A separately visible ShaderEffectSource leaves a sharp copy in the scene and
# defeats the intended no-wallpaper blur composition.
contains "$SURFACE" 'layer.enabled: root.transitionComplete' \
    'captured Hyprland frame does not enable its own post-transition blur layer'
contains "$SURFACE" 'layer.effect: MultiEffect' \
    'captured Hyprland frame has no direct MultiEffect layer'
contains "$SURFACE" 'root.blurStyle === "smooth"' \
    'captured Hyprland smooth blur is not style-gated'
rejects "$SURFACE" 'id: desktopCaptureTexture' \
    'sharp desktop texture provider is still rendered alongside smooth blur'
contains "$SURFACE" 'id: desktopCapturePixelatedBlur' \
    'captured Hyprland pixelated blur path is missing'
contains "$SURFACE" 'hideSource: root.transitionComplete' \
    'pixelated desktop path does not hide the sharp captured frame'

# Wallpaper follows the same single-visible-source rule so the one Blur slider
# has identical semantics for wallpaper and captured-session composition.
contains "$SCENE" 'layer.enabled: root.wallpaperBlur > 0' \
    'wallpaper does not enable its own smooth blur layer'
contains "$SCENE" 'layer.effect: MultiEffect' \
    'wallpaper has no direct MultiEffect layer'
contains "$SCENE" 'root.blurStyle === "smooth"' \
    'wallpaper smooth blur is not style-gated'
rejects "$SCENE" 'id: wallpaperTexture' \
    'sharp wallpaper texture provider is still rendered alongside smooth blur'
contains "$SCENE" 'id: wallpaperPixelatedBlur' \
    'wallpaper pixelated blur path is missing'
contains "$SCENE" 'hideSource: root.wallpaperBlur > 0' \
    'pixelated wallpaper path does not hide the sharp wallpaper image'

cmp -s "$SCENE" "$PREVIEW" \
    || fail 'secure/editor presentation scenes diverged'

printf '%s\n' 'PASS: composition blur renders exactly one blurred source for session and wallpaper'
