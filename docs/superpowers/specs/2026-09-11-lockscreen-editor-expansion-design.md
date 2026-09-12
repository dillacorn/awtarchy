# Lockscreen Editor Expansion Design

## Scope

This design extends draft PR #181 after the maintainer's first successful runtime pass. It covers issues #188, #189, and #190 without changing the lock authority or authentication architecture.

## Security invariants

- `WlSessionLock` remains the sole lock authority.
- `LockAuth.qml` remains the PAM/authentication owner.
- The real password `TextInput` remains inside `LockSurface.qml`.
- Presentation state, image paths, visualizer data, pointer physics, opacity, and editor state never enter the authentication path.
- The secure lock process performs no network access.
- Background transparency is presentation-only and opt-in. It may reveal the already-rendered unlocked desktop beneath the secure lock surface, so the default remains fully opaque and the UI must state the privacy tradeoff.
- Password presentation remains required. Its fade may be reduced but not to zero; the editor clamps password opacity to at least 0.20.

## Pass 1: interaction performance and direct manipulation

### Logo interaction

The existing continuous per-block pointer deformation and audio-driven block motion are removed. Normal pointer movement updates only the lightweight ghost cursor/trail.

A pointer click anywhere on the secure lock surface triggers the AWTARCHY block explosion. Every filled logo block receives an outward velocity relative to the click point plus deterministic per-cell variation. The blocks may travel substantially farther than the old bounded 38 px deformation.

Explosion physics runs only while an explosion is active. A root-level timer updates a compact particle-state table instead of maintaining continuous per-cell deformation bindings. The simulation uses a simple spatial bucket grid for nearby collision candidates rather than an all-pairs collision loop. The first phase scatters and collides; the second phase applies a damped spring toward each block's home offset until the wordmark reforms. Clicking again while active injects another impulse instead of resetting the animation.

The refresh rate is persisted as one of exactly `30`, `60`, or `90` Hz. Stock default is `30`. The timer interval is derived from that preference. Higher rates trade additional CPU/GPU work for smoother temporary explosion motion.

Formation animations remain independent from explosion physics. Connected wordmark groups may remain only where needed by formation readiness; they no longer drive pointer or audio deformation.

### Audio behavior

The AWTARCHY logo itself no longer responds to audio. The old `lockscreen_audio_reactive` state is not used to deform the logo. New audio behavior belongs exclusively to the optional visualizer from Pass 3.

### Editor keyboard shortcuts

Undo/redo history remains unchanged. The runtime failure is treated as a shortcut ownership/focus-routing problem: editor shortcuts must be attached to the actual editor `PanelWindow`, not only the singleton root. `Ctrl+Z`, `Ctrl+Shift+Z`, and `Ctrl+Y` remain the bindings.

### Direct mouse scaling

A selected element gets a visible resize handle at its lower-right selection boundary. Pressing the handle starts one history transaction. Drag distance from the element center scales the selected primary element uniformly between 0.50x and 2.00x, with no per-frame history snapshots. Releasing commits exactly one undo point. Existing +/- and numeric controls remain as secondary precision controls.

### Per-element color discoverability

The existing per-element color model remains authoritative. The base editor row gains an obvious color control/swatch for the currently selected element that opens the Element drawer/palette. Global `Auto All`, `White All`, and `Black All` controls remain secondary actions.

### Fullscreen Awtwall handoff

The standard Alacritty Awtwall selection-only terminal starts in fullscreen mode using Alacritty's `window.startup_mode=Fullscreen` override. The editor continues to suspend and release its fullscreen overlay while Awtwall owns focus, then resumes the same in-memory draft. A non-Alacritty terminal override keeps the existing compatibility launch path.

## Pass 2: generic element presentation and custom image

### Layout schema

Each fixed presentation element uses a normalized point with these fields:

```text
{x, y, scale, color, opacity}
```

`opacity` defaults to `1.0`. Missing opacity in older saved layouts is backward compatible. Non-password elements clamp to `0.0-1.0`; password clamps to `0.20-1.0`.

The fixed element list becomes:

```text
logo, time, date, username, weather, password, image, visualizer
```

`image` and `visualizer` are optional presentation elements and default hidden. This pass intentionally provides one custom-image slot rather than an unbounded dynamic layer list. That satisfies the requested local image insertion while keeping secure-state validation small and deterministic; the schema can be extended later if multiple independent image layers are explicitly requested.

### Custom image element

The editor can choose a local image using the same Awtwall selection-only handoff used by wallpaper selection. The selected path is held only in the editor draft until Save. It is persisted separately from the background wallpaper path.

The state helper validates the custom image as an absolute readable local file and resolves it before persistence. The secure lock shell validates only the persisted absolute local path format and renders it through a cache-only `Image`; it never reads Awtwall backend state.

The custom image participates in normal position, uniform scale, visibility, opacity, direct resize, undo/redo, Save/Cancel, and Reset Position behavior. Its color field remains accepted by the shared schema for compatibility but does not tint the image in this scope.

### Opacity/fade

The Element drawer exposes opacity for the selected element. Built-in stylistic alpha multipliers for date/username/weather remain, multiplied by the user's saved opacity. Editor-only dimming for hidden elements is applied separately and never changes saved opacity.

## Pass 3: standalone visualizer and background transparency

### Analyzer

CAVA remains PipeWire output-only and presentation-only. It produces a fixed 64-band raw ASCII spectrum at 30 frames per second. `LockAudioAnalyzer.qml` parses a variable-length frame into a normalized `bands` array and smooths that array. The analyzer runs only while the visualizer is enabled.

The visualizer chooses the requested displayed band count from the 64-band analyzer data by grouping/averaging samples. Display-band configuration does not restart CAVA.

### Visualizer settings

Persisted visualizer settings use safe normalized ranges:

- enabled: boolean, default `false`
- bands: integer `8-64`, default `24`
- gap: integer `0-100`, default `20` percent of each allocated bar slot
- height: integer `25-300`, default `100` percent
- sensitivity: integer `25-300`, default `100` percent
- stretch X: integer `50-300`, default `100` percent
- stretch Y: integer `50-300`, default `100` percent
- shape: `line | arc | circle`, default `line`
- arc: integer `15-300`, default `120` degrees; used only for `arc`

The generic layout point owns position, uniform scale, color, and opacity. Visualizer-specific stretch modifies geometry after generic scale.

### Visualizer geometry

`line` renders vertical bars in a centered horizontal row. `arc` distributes bars across the configured arc angle around the visualizer center, rotating each bar radially. `circle` distributes bars through 360 degrees. Bars extend outward from their baseline/radius and are colored by the selected element color.

The Visualizer editor drawer exposes bands, gap, response height, sensitivity, stretch X/Y, and shape. The visualizer also uses the common drag/resize/color/opacity workflow.

### Background transparency

A new persisted `lockscreen_background_transparency` integer uses `0-100`, default `0` (fully opaque). It affects only the background composition layer: black/color fill, wallpaper, and overlay. Presentation elements and the secure password surface remain independently rendered above it.

The secure `WlSessionLockSurface` itself uses a transparent surface color so the background layer's alpha can expose content beneath it when explicitly configured. Quick Settings/editor copy warns that increasing transparency can reveal the unlocked desktop while the session is securely locked.

## Persistence and compatibility

- `BarState.qml`, `quickshell_application_state.sh`, the unlocked editor, and the secure lock shell normalize the same defaults/ranges.
- Existing layouts lacking `opacity`, `image`, or `visualizer` migrate in memory to safe defaults.
- Reset restores stock settings: 30 Hz physics, visualizer disabled, custom image empty/hidden, all normal element opacity 1.0, password opacity 1.0, background transparency 0.
- Atomic editor Save persists layout, visibility, background composition/transparency, custom image path, and visualizer settings together.
- No stable release/tag changes are part of this work.

## Validation boundary

Focused regressions must be written and observed failing before each production pass. They cover state normalization, scene parity, click-only logo physics, 30/60/90 Hz validation, removal of logo audio deformation, fullscreen Awtwall launch, window-owned undo/redo shortcuts, direct resize transaction behavior, opacity compatibility, local custom-image validation, visualizer settings/geometry/analyzer isolation, and transparent-background security boundaries.

Static tests and CI cannot prove animation smoothness, collision feel, fullscreen compositor behavior, keyboard routing, transparency appearance, or audio visualization on the maintainer's Hyprland session. PR #181 remains draft until the maintainer runtime-tests the final candidate.