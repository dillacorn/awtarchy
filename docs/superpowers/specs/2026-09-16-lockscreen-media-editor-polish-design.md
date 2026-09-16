# Lockscreen Media and Editor Polish Design

## Goal

Improve the Quickshell lockscreen editor interaction model and extend lockscreen media support to still images, GIFs, and MP4 video without weakening the existing WlSessionLock/authentication architecture.

## Approved editor behavior

- Clicking an element selects it without moving it.
- Dragging begins only after a small pointer movement threshold. A press/release below the threshold must not create a movement history entry, flick velocity, or reposition the element.
- `Ctrl+S` saves the lockscreen configuration and keeps the editor open.
- `Escape` remains the cancel/close shortcut and discards the unsaved draft through the existing close path.
- The editor should visibly advertise `Ctrl+S Save` and `Esc Cancel`.
- `Super+Alt+E` opens the lockscreen editor directly on the focused monitor.
- Quick Settings should show the `Super + Alt + E` hint directly below the lockscreen `Edit Layout` control.

## Approved media architecture

Awtwall is the media browser/selector. It should expose all media it already supports to the lockscreen picker instead of filtering the picker to still images.

Quickshell owns rendering. Do not use `awww`, `hyprpaper`, `mpvpaper`, or an external `mpv` window as the lockscreen renderer. External wallpaper/window surfaces are outside the secure lockscreen scene and cannot participate cleanly in the existing Quickshell opacity, blur, pixelation, overlay, and transition pipeline.

The lockscreen should dynamically select its internal renderer from the selected local file type:

- still image: `Image`
- GIF: `AnimatedImage`
- MP4: Qt Multimedia `MediaPlayer` + `VideoOutput`

The renderer must live inside the current lockscreen background composition so existing background opacity, smooth blur, pixelated blur, overlays, cover/contain geometry, and entry transitions continue to operate on the live media.

Custom image elements become media-aware custom elements as part of the same renderer architecture where practical: still images, GIFs, and silent looping MP4 video should keep the existing custom element position/scale/rotation/opacity/stretch/spawn controls.

## Video startup and lifecycle

- MP4 playback starts as soon as the secure destination scene is constructed, before the desktop-to-lockscreen transition reveals it.
- The transition should not intentionally reveal a frozen first frame. Gate transition readiness on actual decoded video progress rather than only `PlayingState`; require more than one valid decoded frame when possible.
- The readiness wait must be bounded so corrupt/unsupported/slow media can never stall the secure lockscreen presentation indefinitely.
- Video loops continuously while the lockscreen is active.
- Video audio must never play. Do not attach an audio output for lockscreen video.
- Stop/release unnecessary decoding when the owning scene is destroyed or otherwise no longer active.
- Media decode failure must fall back safely without affecting authentication or lock ownership.

## Contrast behavior

Auto contrast must remain deterministic for animated media. It must not recalculate continuously against changing frames. GIF/video should use a stable representative frame or a deterministic fallback for contrast analysis.

## Security invariants

- `WlSessionLock` remains the sole secure lock authority.
- `LockAuth.qml`/the current authentication owner remains unchanged in responsibility.
- Media readiness must never control whether the session is actually locked; it may only influence presentation timing inside the already-secure lock surface.
- Local media rendering must not expose compositor content outside the existing secure captured-desktop backing model.

## Validation

Automated tests must cover editor drag threshold behavior, save/cancel shortcuts and discoverability text, direct editor launch wiring, Awtwall all-media selection, renderer selection, silent/looping video, video pre-roll readiness with a bounded fallback, and preservation of the shared background effect pipeline. Real animated/video rendering and compositor presentation remain runtime-test claims and require maintainer testing on Hyprland after automated checks pass.
