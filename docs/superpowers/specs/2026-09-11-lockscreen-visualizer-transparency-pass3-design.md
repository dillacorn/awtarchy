# Lockscreen Visualizer and Background Transparency Pass 3 Design

## Scope

This spec implements issue #190 on draft PR #181. It consumes the generic transform model completed in Pass 2 and replaces the obsolete audio-reactive AWTARCHY-logo concept with a separate optional audio visualizer element. It also adds opt-in lockscreen background transparency without changing lock authority or authentication ownership.

This spec supersedes the audio-reactive-wordmark sections of `docs/superpowers/specs/2026-09-08-lockscreen-interactive-effects-design.md`. Logo formation, click explosion physics, ghost cursor behavior, and the Pass 2 element system remain unchanged.

## Security boundaries

- `config/quickshell/awtarchy-lock/shell.qml` remains the sole `WlSessionLock` owner.
- `config/quickshell/awtarchy-lock/LockAuth.qml` remains the PAM/authentication owner and is not modified.
- The real password `TextInput`, focus routing, submission, and PAM conversation remain in `LockSurface.qml`.
- Audio analysis receives only CAVA spectrum data and never receives password/authentication data.
- Background transparency changes only presentation alpha. It never releases, bypasses, or weakens `WlSessionLock`.
- Password presentation and the real password input are not multiplied by background opacity.
- Default background opacity is 100%, preserving the current opaque appearance.
- Runtime compositor behavior for a translucent session-lock surface is not considered verified until maintainer testing on real Hyprland.

## Persisted state

Continue using the existing shared Quickshell state file and `quickshell_application_state.sh` as the single write authority.

Add:

```json
{
  "lockscreen_background_opacity": 100,
  "lockscreen_visualizer": {
    "enabled": false,
    "x": 0.5,
    "y": 0.80,
    "scale": 1.0,
    "stretch_x": 1.0,
    "stretch_y": 1.0,
    "opacity": 100,
    "color": "auto",
    "bands": 16,
    "gap": 4,
    "height": 100,
    "sensitivity": 100,
    "shape": "straight",
    "bend": 45
  }
}
```

Validation:

- background opacity: integer 0–100, default 100;
- visualizer `enabled`: boolean, default false;
- x/y: existing general element bounds, x 0.05–0.95 and y 0.08–0.92;
- overall scale: 0.50–2.00;
- `stretch_x` / `stretch_y`: 0.25–4.00;
- opacity: 0–100;
- color: `auto` or `#RRGGBB`;
- bands: integer 4–64, default 16;
- gap: integer 0–24 logical pixels, default 4;
- response height: integer 25–300 percent, default 100;
- sensitivity: integer 25–300 percent, default 100;
- shape: `straight|arc|circle`, default `straight`;
- bend: integer -100–100, default 45. Straight and circle ignore bend.

Missing or malformed legacy state falls back to these defaults. The old `lockscreen_audio_reactive` key may remain readable during this branch for backward compatibility but does not move the logo and is not the visualizer source of truth.

`save-lockscreen-editor` persists the complete visualizer object and background opacity atomically with the existing layout, custom images, visibility, background composition, and weather-unit state. A malformed visualizer or opacity value rejects the complete save without partial mutation.

`reset-lockscreen-presentation` restores visualizer defaults and background opacity 100.

## Audio analyzer

Reuse the existing CAVA/PipeWire helper instead of adding a second audio stack.

- CAVA uses PipeWire `source = auto`, mono average, raw ASCII stdout, 30 FPS.
- The analyzer emits a fixed 64-band spectrum. A fixed maximum-band source avoids restarting CAVA when the user changes visualizer band count.
- `LockAudioAnalyzer.qml` parses all available values, normalizes them to 0–1, applies the existing silence threshold and attack/release smoothing, and exposes a `bands` array.
- The analyzer starts only while the visualizer is enabled and stops/settles to zero when disabled.
- Secure mode owns one analyzer in `awtarchy-lock/shell.qml`; all monitor surfaces consume that same band array.
- The unlocked editor gets a config-local analyzer copy because the desktop and secure Quickshell roots remain isolated. It runs only while the editor is open, the visualizer draft is enabled, and the Awtwall picker is not suspending the editor.
- Missing CAVA, helper failure, or malformed frames resolve to a zero/empty spectrum rather than synthetic movement.

The scene resamples the fixed 64-band source into the configured visible band count by averaging contiguous source ranges. Sensitivity is applied after normalization and before clamping; response height controls rendered amplitude only.

## Visualizer scene element

The visualizer is a presentation element, not a logo effect.

Pass 2's six built-ins remain in `lockscreen_layout`; visualizer-specific state remains in `lockscreen_visualizer`. `LockScene.qml` receives the normalized visualizer object plus the analyzer band array.

The scene exposes the visualizer through the same transform-facing helpers used by the editor:

- normalized x/y center;
- overall scale;
- independent X/Y stretch;
- opacity;
- color;
- visual width/height for selection geometry.

`auto` visualizer color resolves to the lock theme accent. A valid custom `#RRGGBB` override replaces it. Visualizer color is independent from custom images, which remain non-colorized.

Rendering uses bounded QML Rectangle delegates rather than a full-screen shader. Maximum visible delegates are 64.

### Straight

Bands are laid out horizontally around the visualizer center. Each band grows upward/downward around a stable center baseline, using configured gap, response height, sensitivity, scale, stretch, opacity, and color.

### Arc

Bands are distributed across the same horizontal span, with their centers offset along a bounded parabola and rotated to the local tangent. `bend=-100..100` controls direction and curvature; zero degenerates to straight geometry.

### Circle

Bands are distributed around 360 degrees and point radially outward. The configured band count controls angular spacing. Bend is ignored. Overall scale and stretch allow circular or elliptical presentation.

No visualizer geometry writes back into logo physics, formation state, ghost cursor state, or authentication state.

## Editor integration

The editor treats `visualizer` as a generic selectable element in addition to the six built-ins and custom-image IDs.

`elementExists`, `elementPoint`, selection, drag, snapping, keyboard nudge, group motion, flick, direct resize, numeric position, undo/redo, and selection geometry route `visualizer` through the persisted draft visualizer object. Do not fork a separate drag/resize implementation.

The visualizer remains selectable in editor mode even when disabled, using the existing faded-editor convention so it can be positioned and re-enabled.

Selected visualizer controls expose:

- Enabled;
- Reset Position;
- overall scale;
- Stretch X / Stretch Y;
- Opacity;
- color controls;
- Bands;
- Gap;
- Height;
- Sensitivity;
- Straight / Arc / Circle;
- Bend when Arc is selected.

Undo/redo snapshots include the complete draft visualizer and background opacity.

The Background drawer adds a Background Opacity control and a clear privacy warning whenever the draft value is below 100%: transparency may reveal content from the unlocked desktop underneath the still-secure lock surface.

## Quick Settings integration

Keep controls inside the existing expandable Awtarchy > Lockscreen section.

Quick Settings exposes only the high-value global controls:

- Visualizer: On/Off;
- Background Opacity: 100 / 75 / 50 / 25 / 0 percent presets;
- a short privacy warning when saved background opacity is below 100%.

Detailed visualizer geometry/tuning remains in the visual editor to avoid rebuilding the large editor control surface inside Quick Settings.

The old Audio Reactive Quick Settings control remains absent.

## Background transparency composition

`LockScene.qml` groups the existing black/color base, wallpaper effect, and dark/light overlay into a background-only layer. That layer receives `lockscreen_background_opacity / 100`.

The visual layer containing custom images, visualizer, logo, time/date/username/weather, ghost cursor, and password anchor remains independent of background alpha.

`LockSurface.qml` must not paint an opaque black surface behind the scene when transparency is requested. Its surface color becomes transparent; the scene's background layer supplies the current fully opaque appearance at the default 100% setting.

The secure surface still covers the monitor and continues consuming input while translucent. Transparency is a visual disclosure choice, not an unlock path.

## Multi-monitor and lifecycle behavior

- One secure-shell analyzer feeds every `WlSessionLockSurface`; no per-monitor CAVA processes.
- Each surface renders the same persisted visualizer state against its own logical geometry.
- Editor preview owns at most one analyzer and stops it when the editor closes or suspends for Awtwall.
- Disabled visualizer means no secure/editor analyzer process.
- Background opacity is global and resolves identically on each monitor while actual compositor blending remains runtime-dependent.
- No new persistent service or daemon is introduced.

## TDD and validation

Add `tests/test-quickshell-lockscreen-visualizer-transparency.sh` before production changes and observe RED because the new state/render/editor symbols do not exist.

Focused coverage must assert at least:

- persisted defaults and validation for every visualizer field and background opacity;
- malformed visualizer/editor saves fail atomically;
- legacy state loads safe defaults;
- reset restores disabled visualizer and 100% background opacity;
- the obsolete audio-reactive-logo preference is not wired to logo motion;
- CAVA is one 64-band 30-FPS PipeWire analyzer and analyzer lifecycle follows visualizer enable state;
- secure shell owns one analyzer and passes only band data to surfaces;
- desktop preview uses its own config-local analyzer, active only while editing;
- visualizer is selectable through the generic editor transform model and history;
- straight, arc, and circle modes are present with bounded band count/bend;
- Background Opacity affects only the background layer;
- `LockSurface` remains a `WlSessionLockSurface`, the real password TextInput remains secure, and `LockAuth.qml` remains unchanged;
- secure/editor scene parity remains exact;
- Quick Settings exposes Visualizer and Background Opacity but no Audio Reactive logo control;
- managed-history, updater, foundation, runtime-regression, interactive-effects, Runtime Stress, and full Awtarchy integration validation remain green.

Static tests and CI cannot prove CAVA output quality, rendered visualizer aesthetics, compositor transparency behavior, or multi-monitor runtime appearance. Those remain unverified until the maintainer tests the exact candidate on a real Hyprland session.
