# Lockscreen Visualizer and Background Transparency Pass 3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a standalone configurable audio visualizer and opt-in background transparency to the native Quickshell lockscreen without changing authentication or lock authority.

**Architecture:** Persist visualizer configuration in a dedicated normalized `lockscreen_visualizer` object and background alpha in `lockscreen_background_opacity`. Reuse one fixed 64-band CAVA analyzer per secure lock root, pass only normalized band data into the byte-identical secure/preview scenes, and plug the visualizer into Pass 2's generic editor transform path. Apply transparency only to the existing background composition layer while leaving foreground/password presentation independent.

**Tech Stack:** Bash + jq persistence/validation, Quickshell QML, CAVA/PipeWire raw spectrum, GitHub Actions shell regressions.

**Spec:** `docs/superpowers/specs/2026-09-11-lockscreen-visualizer-transparency-pass3-design.md`

## Global Constraints

- `WlSessionLock` remains the sole lock authority.
- `LockAuth.qml` remains the PAM/authentication owner and must remain unchanged.
- Visualizer audio data is presentation-only and never receives authentication state.
- Background opacity defaults to 100 and affects only background composition.
- Visualizer defaults disabled.
- Secure/editor scene parity remains byte-identical.
- Production changes follow RED -> GREEN TDD.
- No release/tag changes.
- Runtime visual/audio/transparency behavior is not called verified until maintainer testing on real Hyprland.

---

### Task 1: Add the failing Pass 3 contract

**Files:**
- Create: `tests/test-quickshell-lockscreen-visualizer-transparency.sh`
- Modify: `.github/workflows/validate-quickshell-lockscreen-interactive-effects.yml`

**Interfaces:**
- Consumes: current Pass 2 state script, BarState, editor, secure/preview scenes, audio analyzer/helper.
- Produces: one executable contract covering Pass 3 persistence, analyzer lifecycle, renderer/editor integration, transparency isolation, and security boundaries.

- [ ] **Step 1: Write the failing structural/state contract**

Require symbols similar to:

```bash
require_text "$APP_STATE" 'lockscreen_visualizer' 'visualizer persistence is missing'
require_text "$APP_STATE" 'lockscreen_background_opacity' 'background opacity persistence is missing'
require_text "$SCENE" 'required property var visualizer' 'scene has no visualizer state'
require_text "$SCENE" 'required property var audioBands' 'scene has no analyzer spectrum input'
require_text "$EDITOR" 'draftVisualizer' 'editor has no visualizer draft'
require_text "$EDITOR" 'draftBackgroundOpacity' 'editor has no background-opacity draft'
require_text "$QUICK_SETTINGS" 'Visualizer' 'Quick Settings has no visualizer toggle'
require_text "$QUICK_SETTINGS" 'Background Opacity' 'Quick Settings has no background-opacity control'
reject_text "$QUICK_SETTINGS" 'Audio Reactive' 'obsolete audio-reactive logo control returned'
```

The same test creates a temporary state file and proves valid/invalid visualizer JSON, 0–100 background opacity, legacy defaults, atomic editor-save rejection, and reset behavior.

- [ ] **Step 2: Add security/lifecycle assertions**

Require `WlSessionLock` only in secure shell, unchanged `LockAuth.qml`, transparent `LockSurface` backing, background-only scene alpha, one secure analyzer, preview-local analyzer, and no visualizer data in auth code.

- [ ] **Step 3: Wire the test into the permanent lockscreen workflow**

Add Bash syntax/ShellCheck plus the focused test execution to `.github/workflows/validate-quickshell-lockscreen-interactive-effects.yml`.

- [ ] **Step 4: Commit RED evidence**

Run PR CI on the exact test-only SHA and confirm failure is specifically missing Pass 3 production behavior.

### Task 2: Add normalized Pass 3 persistence

**Files:**
- Modify: `config/hypr/scripts/quickshell_application_state.sh`
- Modify: `config/quickshell/awtarchy/BarState.qml`

**Interfaces:**
- Produces `lockscreen_background_opacity: int` in 0–100.
- Produces normalized `lockscreen_visualizer` object:

```json
{"enabled":false,"x":0.5,"y":0.8,"scale":1,"stretch_x":1,"stretch_y":1,"opacity":100,"color":"auto","bands":16,"gap":4,"height":100,"sensitivity":100,"shape":"straight","bend":45}
```

- [ ] **Step 1: Add exact validation/default helpers in Bash**

Add constants for shapes and defaults, then a jq normalizer that requires exact allowed keys when provided and validates:

```text
x 0.05..0.95
y 0.08..0.92
scale 0.50..2.00
stretch_x/stretch_y 0.25..4.00
opacity 0..100
color auto|#RRGGBB
bands 4..64
gap 0..24
height 25..300
sensitivity 25..300
shape straight|arc|circle
bend -100..100
enabled boolean
```

Missing entire state returns stock defaults.

- [ ] **Step 2: Add independent setters**

Add commands:

```text
set-lockscreen-visualizer-enabled <true|false>
set-lockscreen-background-opacity <0-100>
```

The visualizer-enabled setter normalizes the existing object first and changes only `.enabled`. The background-opacity setter writes only the validated integer.

- [ ] **Step 3: Extend atomic editor Save and Reset**

Extend the current maximum `save-lockscreen-editor` form with two final arguments: `<visualizer_json> <background_opacity>`. Preserve all existing legacy arg-count forms. Validate all inputs before writing. Save both values in the same jq replacement. Reset restores stock visualizer + opacity 100.

- [ ] **Step 4: Add BarState defaults/readers**

Add `defaultLockscreenVisualizer`, `lockscreenVisualizer()`, and `lockscreenBackgroundOpacity()`. Remove UI dependence on `lockscreenAudioReactiveEnabled()`; retaining the legacy reader temporarily is allowed only if no production logo/UI path consumes it.

- [ ] **Step 5: Run focused state tests**

Expected: persistence/default/reset assertions GREEN while renderer/editor assertions remain RED.

### Task 3: Convert the analyzer into a reusable spectrum source

**Files:**
- Modify: `config/quickshell/awtarchy-lock/cava.conf`
- Modify: `config/quickshell/awtarchy-lock/LockAudioAnalyzer.qml`
- Create: `config/quickshell/awtarchy/LockPreviewAudioAnalyzer.qml`
- Keep/validate: `config/hypr/scripts/quickshell_lockscreen_audio.sh`

**Interfaces:**
- `LockAudioAnalyzer.bands`: smoothed array of up to 64 normalized real values in 0–1.
- `enabled=false`: stops the Process and converges spectrum to zeros.

- [ ] **Step 1: Change CAVA to fixed 64-band output**

Keep:

```ini
framerate = 30
bars = 64
[input]
method = pipewire
source = auto
[output]
method = raw
channels = mono
mono_option = average
data_format = ascii
ascii_max_range = 1000
bar_delimiter = 59
frame_delimiter = 10
```

- [ ] **Step 2: Replace aggregate-only parsing with spectrum parsing**

`parseFrame()` accepts 4–64 numeric semicolon fields, clamps each to 0–1, applies silence threshold, and stores a target band array. Keep low/mid/high/overall only if an existing regression still consumes them; no logo code may consume them.

- [ ] **Step 3: Smooth each band at the existing 33 ms cadence**

Apply the current attack/release factors per index. Stop the smoothing timer after every band reaches its target. Process exit clears targets.

- [ ] **Step 4: Add desktop-root analyzer parity copy**

Create `LockPreviewAudioAnalyzer.qml` with byte-identical analyzer logic. The editor owns it only while editing and enabled; no cross-config QML import is introduced.

- [ ] **Step 5: Run analyzer/lifecycle tests**

Expected: 64-band/30-FPS/PipeWire and enable/disable lifecycle assertions GREEN.

### Task 4: Render visualizer and isolate background alpha

**Files:**
- Modify: `config/quickshell/awtarchy-lock/shell.qml`
- Modify: `config/quickshell/awtarchy-lock/LockSurface.qml`
- Modify: `config/quickshell/awtarchy-lock/LockScene.qml`
- Modify: `config/quickshell/awtarchy/LockPreviewScene.qml`

**Interfaces:**
- `LockScene.required property var visualizer`
- `LockScene.required property var audioBands`
- `LockScene.required property int backgroundOpacity`

- [ ] **Step 1: Normalize secure-shell state**

Add secure defaults/readers mirroring Bash/BarState bounds. Instantiate exactly one `LockAudioAnalyzer`:

```qml
LockAudioAnalyzer {
    id: lockAudioAnalyzer
    enabled: root.lockVisualizer.enabled
}
```

Pass the normalized visualizer, `lockAudioAnalyzer.bands`, and background opacity into every `LockSurface`.

- [ ] **Step 2: Keep LockSurface transparent but secure**

Set surface backing color to transparent and pass presentation-only properties into `LockScene`. Do not alter input capture, password TextInput, focus, `auth.submit`, unlock timers, or `WlSessionLock` behavior.

- [ ] **Step 3: Wrap existing background composition**

Create one `backgroundLayer` containing base black/color, wallpaper `MultiEffect`, and overlay. Set:

```qml
opacity: Math.max(0, Math.min(100, root.backgroundOpacity)) / 100
```

Keep `visualLayer` and password block outside this alpha multiplier.

- [ ] **Step 4: Add visualizer transform helpers**

Treat name `visualizer` as a presentation point sourced from `root.visualizer`, exposing x/y/scale/stretch/opacity/color/visual dimensions without adding it to the six-key persisted layout.

- [ ] **Step 5: Add band resampling**

Implement a pure helper that maps the fixed analyzer array into configured `bands` by averaging contiguous source ranges, then applies sensitivity and clamps 0–1.

- [ ] **Step 6: Render the three shapes with bounded Rectangle delegates**

Straight: horizontal bars. Arc: horizontal distribution plus bounded parabolic offset/tangent rotation using `bend`. Circle: 360-degree radial distribution. Use at most 64 delegates and no shader.

- [ ] **Step 7: Preserve exact secure/preview scene parity**

Copy finalized `LockScene.qml` byte-for-byte to `LockPreviewScene.qml` and enforce `cmp -s` in tests.

- [ ] **Step 8: Run scene/security regressions**

Expected: scene/transparency/analyzer secure-path assertions GREEN; `LockAuth.qml` unchanged.

### Task 5: Integrate the visualizer into the generic editor and Quick Settings

**Files:**
- Modify: `config/quickshell/awtarchy/LockscreenEditor.qml`
- Modify: `config/quickshell/awtarchy/QuickSettings.qml`

**Interfaces:**
- Editor snapshot gains `visualizer` and `backgroundOpacity`.
- `visualizer` becomes a generic selectable name routed through existing transform/history functions.

- [ ] **Step 1: Add draft state and preview analyzer**

Initialize:

```qml
property var draftVisualizer: defaultVisualizer()
property int draftBackgroundOpacity: 100

LockPreviewAudioAnalyzer {
    id: previewAudioAnalyzer
    enabled: root.editingActive && !root.pickerSuspended && root.draftVisualizer.enabled
}
```

Pass draft visualizer, preview bands, and opacity into `LockPreviewScene`.

- [ ] **Step 2: Route visualizer through generic element functions**

Extend `allElementNames()`, `elementExists()`, `elementPoint()`, point updates, color/visibility helpers, selection geometry, drag/snap/nudge/group/flick/resize, and reset-position logic so `visualizer` reuses the existing machinery. Do not add separate pointer handlers.

- [ ] **Step 3: Include Pass 3 state in undo/redo**

Snapshots clone/restore the complete visualizer object and background opacity. Cancel reloads persisted values; Save sends both new arguments atomically.

- [ ] **Step 4: Add selected-visualizer controls**

When selected, expose Enabled, Scale, Stretch X/Y, Opacity, Color, Bands, Gap, Height, Sensitivity, shape buttons, and Bend for Arc. Use the same bounded numeric-control patterns already used by the editor.

- [ ] **Step 5: Add background opacity + warning**

Background drawer exposes 0–100 opacity. Show text equivalent to:

```text
Transparency can reveal content from the unlocked desktop beneath the secure lockscreen.
```

when draft opacity is below 100.

- [ ] **Step 6: Add compact Quick Settings controls**

Inside existing Lockscreen section add Visualizer On/Off and Background Opacity presets 100/75/50/25/0. Show a short privacy warning below 100. Do not add detailed band controls or restore Audio Reactive.

- [ ] **Step 7: Run editor/UI regressions**

Expected: focused Pass 3 contract, element-system, live-editor, editor-tooling/presets/flick, Quick Settings layout, and capture/privacy tests pass.

### Task 6: Managed history, stale-description cleanup, and final verification

**Files:**
- Modify only if required: `local/share/awtarchy/quickshell-managed-history.sha256`
- Update: PR #181 body after implementation stabilizes.

**Interfaces:**
- Updater recognizes final managed hashes.
- PR description accurately describes click explosion + standalone visualizer rather than obsolete continuous/audio-reactive logo behavior.

- [ ] **Step 1: Register final managed hashes**

Add exact final hashes only after QML/shell content stops moving. Run the managed-history and updater migration/bootstrap tests using the same fixture environment as permanent `Validate Awtarchy`.

- [ ] **Step 2: Run focused verification**

Run/observe:

```bash
bash tests/test-quickshell-lockscreen-visualizer-transparency.sh
bash tests/test-quickshell-lockscreen-element-system.sh
bash tests/test-quickshell-lockscreen-runtime-regressions.sh
bash tests/test-quickshell-lockscreen-foundation.sh
bash tests/test-quickshell-lockscreen-interactive-effects.sh
bash tests/test-quickshell-lockscreen-interaction-polish.sh
bash tests/test-quickshell-lockscreen-live-editor.sh
bash tests/test-quickshell-lockscreen-editor-tooling.sh
bash tests/test-quickshell-lockscreen-editor-presets.sh
bash tests/test-quickshell-lockscreen-interactive-managed-history.sh
```

Also run Bash syntax/ShellCheck for changed shell/tests, scene parity, `git diff --check`, updater migration/bootstrap, and `LockAuth.qml` byte comparison against `main`.

- [ ] **Step 3: Update stale PR description**

Remove continuous per-block hover/audio-reactive-logo claims. Document cheap ghost cursor + click explosion, Pass 2 generic element system, standalone visualizer, and opt-in background transparency. Keep runtime status explicitly unverified.

- [ ] **Step 4: Require all normal PR CI on one exact candidate SHA**

All PR-triggered workflows, including `Validate Awtarchy`, lockscreen foundation, interactive effects, Quick Settings, and Runtime Stress Analysis, must complete successfully.

- [ ] **Step 5: Stop before merge**

Provide the exact 40-character runtime-test SHA. PR #181 stays draft/unmerged. No release/tag change. Final visual/audio/transparency/auth behavior remains runtime-unverified until the maintainer tests it on Hyprland.
