# Lockscreen Runtime Corrections Design

## Purpose

Correct the runtime-rejected lockscreen presentation/editor behavior tracked by #187, with #188, #189, and #190 as subordinate work. The main architectural correction is that entry transitions must visibly transform the desktop frame that existed when locking was requested into the secure lockscreen scene. Decorative black covers on an already-established lockscreen are not acceptable.

## Security invariants

- `WlSessionLock` remains the only lock authority.
- `LockAuth.qml` remains the PAM/authentication owner.
- Password input remains inside `WlSessionLockSurface` and never enters editor, capture, audio, transition, wallpaper, or pointer helpers.
- No unlocked overlay is used to simulate locking.
- Any capture/load/output mismatch fails closed to opaque black while locking continues.
- Transition captures are sensitive presentation artifacts only: they live below `XDG_RUNTIME_DIR`, are owned by the current user, use owner-only directory/file permissions, contain no authentication data, and are deleted after handoff/unlock/failure plus stale-start cleanup.
- No release or tag changes are part of this work.

## Secure pre-lock capture

Add a focused helper at `config/hypr/scripts/quickshell_lockscreen_capture.sh`.

`prepare` will:

1. Require a valid, user-owned, non-symlink `XDG_RUNTIME_DIR`.
2. Create/validate `$XDG_RUNTIME_DIR/awtarchy-lock-transition` at mode `0700` under `umask 077`.
3. Remove only stale capture directories contained below that exact root.
4. Read the active Hyprland output names, reject unsafe names, and capture one PNG per output with `grim -o`.
5. Validate every capture as an owned, regular, readable, non-empty mode-`0600` file.
6. Return the unique capture directory only when the complete output set succeeds. Partial sets are removed and treated as capture failure.

`cleanup <dir>` will accept only an owned capture directory directly below the validated runtime root and remove only that directory.

`awtarchy_lock.sh` will call `prepare` immediately before launching `awtarchy-lock`, pass the validated directory only to that Quickshell process through `AWTARCHY_LOCK_CAPTURE_DIR`, and otherwise launch normally with no capture directory. Failure to capture never prevents the compositor lock from being requested.

Per-output matching uses `WlSessionLockSurface.screen.name`. A secure surface accepts only a conservative monitor name and the validated runtime capture root. Missing or unreadable matches render black.

## Transition renderer

Create `config/quickshell/awtarchy-lock/LockTransitionLayer.qml` so secure runtime and editor replay share one transition clock and effect implementation instead of duplicating timing logic.

Inputs are presentation-only items: a desktop/start source, a lock/end source, transition mode, duration, and replay token/state. The component never receives auth state or password text.

The total duration defaults to 1800 ms and is normalized to 800-6000 ms. The renderer uses one `0..1` progress clock.

### Resolution Collapse / Pixelate

Pixel becomes a true two-source resolution collapse:

- `0.00..0.45`: captured desktop remains the source while `ShaderEffectSource.textureSize` steps down from native size toward a coarse bounded texture.
- `0.45..0.55`: both sources remain maximally coarse and crossfade at the midpoint so the source handoff cannot expose black.
- `0.55..1.00`: the lock target remains the source while texture size rises back toward native size.
- `smooth: false` keeps nearest-neighbor blocks rather than Gaussian blur/interpolation.
- Texture dimensions are bounded at both ends and derived from the current surface/output size so workload cannot grow unbounded.

Qt documents `ShaderEffectSource.textureSize` specifically as a way to decrease source resolution, and non-smooth layer sampling uses nearest filtering. This avoids a custom shader dependency for the accepted resolution-collapse effect.

### Other entry transitions

Fade, Wipe, Edges, and Reverse Iris remain only as two-source desktop-to-lockscreen transitions. They may mask/clip the captured start source, but they do not paint a black decorative cover. The lock scene is the destination source throughout.

The secure surface keeps the actual lock target hidden behind the transition renderer until the handoff completes. Logo formation, password reveal, and other entrance motion are gated until transition completion.

## Secure captured-desktop backing and blur

`LockSurface.qml` becomes opaque black at the window/surface level and builds a presentation stack:

1. opaque black fail-closed base;
2. matching captured desktop image when successfully loaded;
3. `MultiEffect` blur of that captured image using the editor blur value;
4. existing `LockScene`, whose background opacity controls how much of the secure captured backing is visible;
5. password/auth presentation and pointer handling;
6. entry transition renderer above the presentation stack while active.

This makes blur/transparency operate on the secure captured backing instead of pretending wallpaper-only blur is desktop blur. If the capture is unavailable or later invalid, black remains behind the lock scene.

Capture cleanup is requested after the transition has handed off to already-loaded QML image/texture state and again on unlock/failure. Stale startup cleanup remains a final safety net.

## Editor replay and controls

The editor uses the same `LockTransitionLayer.qml` timing/effects, but its start source is a synthetic editor-only desktop mock (neutral desktop/window shapes generated inside QML), never a screencopy of unrelated live desktop content.

Transition duration is edited with the same custom track/thumb/value-entry interaction used by Awtarchy display brightness and maximum-volume controls. Replay consumes the same normalized duration as secure runtime.

Detailed background opacity, blur, and brightness remain editor-owned. Quick Settings retains useful global actions/toggles but not duplicate precision controls. First opacity reduction below 100% seeds a useful blur only when the user has not explicitly selected blur.

## Element transforms

Use one defensive scale ceiling of `100.0x` for every scalable presentation element. It exists only to reject corrupt/unbounded persisted state; the former 2.0x/200% composition ceiling is removed from built-ins, visualizer, and custom images.

Custom images gain persisted `rotation` in degrees. Storage normalizes rotation to an equivalent bounded angle; rendering, direct-manipulation rotation handle, numeric control, undo/redo, selected-element reset, preview, and secure runtime all use the same value.

Every selectable element gains `Reset to Default` in addition to the existing `Reset Position`; `Reset All` remains available. Reset uses stock position/scale/stretch/opacity/color plus element-specific values. Custom-image reset keeps the image asset but resets its presentation transform.

## Visualizer corrections

The visualizer keeps the direct-frame/no-visible-smoothing path. CAVA documents 60 FPS as its default; Awtarchy therefore keeps a reasonable 60 FPS balanced mode while offering explicit 90 FPS responsive and 120 FPS high-response modes that intentionally spend more CPU. Default visual sensitivity increases from the rejected candidate and the modes change the actual CAVA/source cadence, not an arbitrary QML tween.

Arc bend becomes a wide signed numeric value with a defensive range of `-2000..2000`. Visualizer width becomes independent persisted presentation state, directly resizable and numerically editable. Width/bend participate in undo/redo/reset/preview/secure parity.

## Awtwall lifecycle

The picker keeps Awtwall selection-only mode and the dedicated class/title. Instead of a short class-only poll, it waits a bounded interval for the exact mapped Hyprland client, captures that client's address, focuses that exact address, requests fullscreen, and verifies/retries the fullscreen state for that client. This preserves the startup-mode hint but no longer treats it as sufficient evidence.

## Logo interaction

Preserve the bounded active-only physics architecture already present: no idle simulation, no connector lines, coherent neighboring hover deformation, bounded velocity/collisions/bounce, repeated click impulse, and spring return. Tune constants only with focused tests and another Hyprland visual pass; automated checks cannot prove the subjective motion quality.

## Validation

Production changes use TDD. Focused tests cover capture validation/cleanup/fail-closed behavior, two-source transition contracts, duration normalization, no pre-transition logo/password entrance, secure/editor parity, scale/rotation/reset, visualizer width/bend/performance modes, and exact Awtwall mapped-window fullscreen targeting.

Then run the existing lockscreen tests, Bash syntax/ShellCheck where applicable, managed-history validation, full `validate-awtarchy` integration, and all PR-triggered CI. Runtime visual/audio/compositor behavior remains unverified until the maintainer tests the exact new branch head on Hyprland.
