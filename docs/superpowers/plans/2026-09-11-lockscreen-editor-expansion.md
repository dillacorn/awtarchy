# Lockscreen Editor Expansion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend PR #181 with cheaper click-only AWTARCHY block physics, reliable/direct editor interaction, generic opacity/custom-image support, a standalone configurable audio visualizer, and opt-in background transparency.

**Architecture:** Preserve the current secure/editor split and fixed validated state model. Expand the normalized lockscreen layout point, add bounded presentation settings to the existing application-state helper/BarState path, keep secure/editor `LockScene.qml` byte-identical, and run expensive simulation/analyzer work only while its feature is active.

**Tech Stack:** QML/QtQuick, Quickshell, Bash, jq, CAVA/PipeWire, GitHub Actions shell regressions.

**Spec:** `docs/superpowers/specs/2026-09-11-lockscreen-editor-expansion-design.md`

## Global Constraints

- `WlSessionLock` remains the sole lock authority.
- `LockAuth.qml` remains the PAM/authentication owner.
- PR #181 remains draft and unmerged during implementation/runtime testing.
- No release/tag changes.
- `LockScene.qml` and `LockPreviewScene.qml` remain byte-identical.
- Production changes use TDD: focused regression first, confirm RED, then implementation, then GREEN.
- Runtime/visual/audio/fullscreen behavior is not claimed verified until the maintainer tests the exact final branch commit in Hyprland.

---

### Task 1: Interaction performance, shortcuts, resize, color affordance, and fullscreen picker

**Files:**
- Modify: `tests/test-quickshell-lockscreen-logo-cohesion.sh`
- Modify: `tests/test-quickshell-lockscreen-interactive-physics-regressions.sh`
- Modify: `tests/test-quickshell-lockscreen-interactive-effects.sh`
- Modify: `tests/test-quickshell-lockscreen-editor-tooling.sh`
- Modify: `tests/test-quickshell-lockscreen-runtime-polish-ui.sh`
- Modify: `config/hypr/scripts/quickshell_application_state.sh`
- Modify: `config/hypr/scripts/quickshell_lockscreen_wallpaper_picker.sh`
- Modify: `config/quickshell/awtarchy/BarState.qml`
- Modify: `config/quickshell/awtarchy/QuickSettings.qml`
- Modify: `config/quickshell/awtarchy/LockscreenEditor.qml`
- Modify: `config/quickshell/awtarchy-lock/LockScene.qml`
- Modify: `config/quickshell/awtarchy/LockPreviewScene.qml`
- Modify: `config/quickshell/awtarchy-lock/LockSurface.qml`
- Modify: `config/quickshell/awtarchy-lock/shell.qml`

**Interfaces:**
- Produces: `lockscreen_logo_physics_hz` with normalized `30|60|90` reader and setter.
- Produces: click-only `triggerLogoExplosion(x, y)` / active physics timer in the shared scene.
- Produces: window-owned `Ctrl+Z`, `Ctrl+Shift+Z`, `Ctrl+Y` editor shortcuts.
- Produces: direct resize-handle transaction for `draftLayout[selectedElement].scale`.
- Produces: Alacritty fullscreen picker override.

- [ ] **Step 1: Rewrite the focused regressions for the approved behavior**

Require the tests to assert all of the following before implementation exists:

```text
- default logo physics rate is 30 Hz
- only 30/60/90 are accepted by persistent state
- old pointerField/directCellDeformation/neighborCellDeformation/audio logo offsets are rejected
- logo explosion has one root timer, particle state, spatial-bucket collision path, scatter/return phases, and reinjection path
- ordinary pointer motion only updates ghost visuals
- editor undo/redo Shortcuts live inside the editor window
- selected-element resize handle starts/commits one history transaction
- base editor row exposes the selected element color affordance
- standard Alacritty picker command contains window.startup_mode=Fullscreen
- secure/editor scene parity remains exact
```

- [ ] **Step 2: Push the tests and confirm RED**

Run through the branch CI/focused workflows. Expected failures must identify missing click-only explosion/rate/shortcut/resize/fullscreen contracts, not shell syntax errors.

- [ ] **Step 3: Add persistent logo physics rate**

In `quickshell_application_state.sh`, add exact validation for `30|60|90` and command `set-lockscreen-logo-physics-hz`. Reset to 30. In `BarState.qml`, add the stock field and normalized reader. In Quick Settings, add 30/60/90 controls under Lockscreen.

- [ ] **Step 4: Replace continuous logo deformation with bounded active-only explosion physics**

Remove pointer-field and logo-audio displacement functions/properties from both shared scenes. Keep ghost sampling. Register filled cells into root particle state. Implement deterministic outward impulse, spatial buckets, local collision response, scatter duration, damped spring return, stop threshold, and click reinjection. Derive timer interval from the validated rate and run it only while explosion state is active.

- [ ] **Step 5: Preserve secure click/password focus behavior**

Keep `LockSurface.qml`'s full-surface MouseArea and `password.forceActiveFocus()` after click. Wire the persisted physics rate through secure `shell.qml` -> `LockSurface.qml` -> `LockScene.qml`.

- [ ] **Step 6: Fix editor shortcut ownership**

Move/define Undo/Redo `Shortcut` objects inside `editorWindow` so they belong to the actual window. Keep the same three bindings and picker-suspension/history gates.

- [ ] **Step 7: Add direct resize handle and clearer color affordance**

Add one lower-right handle to the primary selected element overlay. Press records center/start scale and begins a history transaction; move computes uniform bounded scale; release/cancel commits once. Add a compact selected-color control/swatch in the base dock that opens the Element drawer.

- [ ] **Step 8: Fullscreen standard Awtwall picker**

When `TERMINAL_CMD` resolves to Alacritty, launch with:

```text
--option window.startup_mode=Fullscreen
```

before the existing class/`-e` arguments. Preserve the compatibility path for a non-Alacritty terminal override.

- [ ] **Step 9: Run focused and broad validation**

Run the interaction/editor/runtime-polish tests, `bash -n`/ShellCheck for the changed helper/state scripts, scene parity, then the PR's existing validation workflows. Expected: GREEN. Commit the pass with a concise message.

---

### Task 2: Opacity and one custom image element

**Files:**
- Modify: `tests/test-quickshell-lockscreen-editor.sh`
- Modify: `tests/test-quickshell-lockscreen-runtime-polish.sh`
- Modify: `tests/test-quickshell-lockscreen-background-composition.sh`
- Modify: `config/hypr/scripts/quickshell_application_state.sh`
- Modify: `config/quickshell/awtarchy/BarState.qml`
- Modify: `config/quickshell/awtarchy/LockscreenEditor.qml`
- Modify: `config/quickshell/awtarchy-lock/shell.qml`
- Modify: `config/quickshell/awtarchy-lock/LockSurface.qml`
- Modify: `config/quickshell/awtarchy-lock/LockScene.qml`
- Modify: `config/quickshell/awtarchy/LockPreviewScene.qml`

**Interfaces:**
- Expands each layout point to `{x,y,scale,color,opacity}`.
- Adds fixed optional element `image` with persisted `lockscreen_image_path` and visibility.
- Reuses the selection-only Awtwall process with an editor picker-purpose state instead of creating a wallpaper backend dependency.

- [ ] **Step 1: Add failing compatibility/security tests**

Tests require opacity defaults/backward compatibility, password opacity clamp >= 0.20, optional image layout/visibility defaults, absolute readable image validation, atomic editor persistence, and secure/editor scene parity. Confirm old implementation fails for missing fields/path/rendering.

- [ ] **Step 2: Expand normalized layout state**

Update layout defaults/normalizers in Bash, `BarState.qml`, editor, and secure shell. Old `{x,y}`, `{x,y,scale}`, and `{x,y,scale,color}` points normalize with `opacity:1`. Password opacity is clamped to `0.20-1.00`; other fixed elements to `0-1`.

- [ ] **Step 3: Add local custom-image persistence**

Add `lockscreen_image_path`, `lockscreen_show_image`, reader/validation/reset/save support. State helper resolves only readable absolute local files. Secure shell performs format-only normalization and passes the path into the presentation scene.

- [ ] **Step 4: Extend editor selection and picker-purpose flow**

Add `image` to the fixed element list/default layout/visibility. Reuse the current suspend/resume picker process with `pickerPurpose = "wallpaper" | "image"`; wallpaper result updates draft background, image result updates draft image path and enables/selects Image. Cancel preserves the current draft.

- [ ] **Step 5: Render and manipulate the image**

Add a cached/asynchronous `Image` presentation item at the normalized point. It uses uniform common scale and common opacity. Add Choose/Replace Image and Remove Image controls in the Element drawer when Image is selected. Direct drag/resize works through the existing generic editor overlay.

- [ ] **Step 6: Add selected-element fade control**

Element drawer provides opacity/fade controls for every fixed element. Date/username/weather retain their stylistic base alpha multiplied by saved presentation opacity. Hidden editor elements retain separate editor-only dimming.

- [ ] **Step 7: Validate and commit**

Run focused editor/state/background tests plus Bash syntax/ShellCheck and scene parity. Then run broad PR validation. Expected: GREEN.

---

### Task 3: Standalone audio visualizer and opt-in background transparency

**Files:**
- Modify: `tests/test-quickshell-lockscreen-interactive-effects.sh`
- Modify: `tests/test-quickshell-lockscreen-interactive-physics-regressions.sh`
- Modify: `tests/test-quickshell-lockscreen-background-composition.sh`
- Modify: `tests/test-quickshell-lockscreen-runtime-services.sh`
- Modify: `config/quickshell/awtarchy-lock/cava.conf`
- Modify: `config/quickshell/awtarchy-lock/LockAudioAnalyzer.qml`
- Modify: `config/hypr/scripts/quickshell_application_state.sh`
- Modify: `config/quickshell/awtarchy/BarState.qml`
- Modify: `config/quickshell/awtarchy/QuickSettings.qml`
- Modify: `config/quickshell/awtarchy/LockscreenEditor.qml`
- Modify: `config/quickshell/awtarchy-lock/shell.qml`
- Modify: `config/quickshell/awtarchy-lock/LockSurface.qml`
- Modify: `config/quickshell/awtarchy-lock/LockScene.qml`
- Modify: `config/quickshell/awtarchy/LockPreviewScene.qml`

**Interfaces:**
- Adds fixed optional `visualizer` layout element.
- Adds normalized visualizer settings: enabled, bands, gap, height, sensitivity, stretch X/Y, shape, arc.
- `LockAudioAnalyzer.bands` becomes the spectrum input; analyzer runs only when visualizer enabled.
- Adds `lockscreen_background_transparency` 0-100, default 0.

- [ ] **Step 1: Add failing visualizer/transparency tests**

Tests reject audio offsets on logo cells and require 64-band analyzer input, normalized visualizer state/ranges, line/arc/circle geometry paths, analyzer enable gating, common element transforms/opacity, background transparency default 0, privacy copy, and secure-surface transparent base color. Confirm RED on the old analyzer/UI/state.

- [ ] **Step 2: Upgrade analyzer to fixed 64-band spectrum**

Set CAVA `bars = 64` and keep `framerate = 30`, PipeWire `source = auto`, mono averaged raw ASCII output. Parse all frame fields into normalized target/current arrays. Smooth each band; stop the smoothing timer when the current array settles to its target. Missing CAVA remains a safe zero-spectrum state.

- [ ] **Step 3: Add normalized visualizer persistence**

Persist the exact settings/ranges from the design spec. Stock visualizer disabled. Reset restores defaults. Retain legacy `lockscreen_audio_reactive` only as ignored compatibility state; do not use it to move the logo.

- [ ] **Step 4: Render visualizer element**

Downsample/group the 64-band spectrum to requested displayed bands. Render `line`, `arc`, and `circle` modes. Apply sensitivity and height to response, gap to bar thickness, common scale/color/opacity to the element, and visualizer stretch X/Y to geometry.

- [ ] **Step 5: Add visualizer editor/settings controls**

Quick Settings exposes Visualizer On/Off and logo physics rate. Editor gains a Visualizer drawer for bands/gap/height/sensitivity/stretch/shape/arc. The common selection overlay handles drag/direct uniform scaling/color/fade.

- [ ] **Step 6: Add opt-in background transparency**

Persist 0-100 percent, default 0. Change secure surface base color to transparent and wrap only the background fill/wallpaper/overlay composition in the computed alpha. Keep all presentation/auth elements above and unaffected. Add explicit privacy copy beside the control.

- [ ] **Step 7: Run full verification**

Run all focused lockscreen tests, Bash syntax/ShellCheck, managed-history/update integration, Quick Settings layout, secure-lock foundation, scene parity, runtime stress analysis, and full Awtarchy integration CI. Re-read `LockAuth.qml`/security diff and confirm it was not modified.

- [ ] **Step 8: Update PR and runtime candidate**

Update PR #181 body to describe the final implementation and issues #188/#189/#190, while retaining the explicit real-Hyprland runtime boundary. Do not merge. Provide the exact final 40-character branch SHA for `awtarchy git update --branch feature/lockscreen-interactive-effects --commit <sha>` and a consolidated runtime checklist.