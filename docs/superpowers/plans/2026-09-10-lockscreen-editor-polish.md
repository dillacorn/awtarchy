# Lockscreen Editor Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the lockscreen visual editor into a precise but playful layout tool with reversible edits, smart positioning, grouped movement, wallpaper composition controls, background treatment, weather units, numeric placement, and stock layout presets.

**Architecture:** Keep transient editing mechanics inside `LockscreenEditor.qml`. Persist only presentation state through the existing `quickshell_application_state.sh` -> `BarState.qml` state model, then normalize the same fields independently in the secure `awtarchy-lock/shell.qml`. Keep `LockPreviewScene.qml` and secure `LockScene.qml` byte-identical presentation components and keep all authentication ownership unchanged.

**Tech Stack:** QML/Qt Quick, QtQuick.Controls, QtQuick.Effects `MultiEffect`, Bash, jq, existing GitHub Actions regression suite.

**Spec:** `docs/superpowers/specs/2026-09-08-lockscreen-interactive-effects-design.md`

## Global Constraints

- Work only on `feature/lockscreen-interactive-effects` / draft PR #181.
- `WlSessionLock` remains the sole lock authority.
- `LockAuth.qml` remains the PAM/authentication owner.
- No editor state or control may submit or observe password/authentication data.
- `LockPreviewScene.qml` and `awtarchy-lock/LockScene.qml` remain byte-identical.
- `BarState.qml` remains the persistent Quickshell state owner; do not create a second persistent state file.
- Editor-only guides, selections, history, velocity, and keyboard state are never persisted.
- Runtime/visual behavior is not considered verified until the maintainer tests on a real Hyprland session.
- Do not merge PR #181 and do not create/edit/delete releases or tags.

---

### Task 1: Undo/Redo, grouped selection, snapping, guides, nudging, and numeric placement

**Files:**
- Modify: `config/quickshell/awtarchy/LockscreenEditor.qml`
- Test: `tests/test-quickshell-lockscreen-editor-tooling.sh`
- Modify: `.github/workflows/validate-quickshell-lockscreen-interactive-effects.yml`

**Interfaces:**
- Consumes: existing `draftLayout`, `draftVisibility`, background draft state, `clampPoint()`, drag/flick delegate.
- Produces: `undo()`, `redo()`, transaction-safe history, `selectedElements`, `snapPoint()`, group translation, keyboard nudging, editor-only guide coordinates, numeric X/Y setters.

- [ ] **Step 1: Write the failing editor-tooling contract**

Require the editor to expose bounded undo/redo stacks, a single transaction per drag/flick, Shift multi-selection, group translation clamped against every member's safe bounds, snap guides for screen center and peer alignment with Alt bypass, arrow-key nudging, and numeric X/Y editing through the same bounded group translation path.

- [ ] **Step 2: Run the contract and verify RED**

Run:

```bash
bash tests/test-quickshell-lockscreen-editor-tooling.sh
```

Expected: failure because undo/redo/group/snap/nudge/numeric editor APIs do not yet exist.

- [ ] **Step 3: Implement transient tooling**

Use full editor snapshots for history:

```qml
({
    layout: cloneLayout(draftLayout),
    visibility: cloneVisibility(draftVisibility),
    backgroundMode: draftBackgroundMode,
    backgroundColor: draftBackgroundColor,
    wallpaperPath: draftWallpaperPath,
    wallpaperFit: draftWallpaperFit,
    wallpaperFocalX: draftWallpaperFocalX,
    wallpaperFocalY: draftWallpaperFocalY,
    overlayMode: draftOverlayMode,
    overlayStrength: draftOverlayStrength,
    wallpaperBlur: draftWallpaperBlur
})
```

Limit each stack to 50 snapshots. Begin one history transaction on pointer press and commit it only when the drag/flick settles; intermediate pointer frames must not create history entries. `Ctrl+Z` undoes, `Ctrl+Shift+Z` and `Ctrl+Y` redo.

Shift-click toggles elements in `selectedElements`; a normal click selects only that element. Dragging any selected member translates the whole selection by one normalized delta. The delta is clamped so every selected member remains inside its existing `clampPoint()` limits.

Snapping uses a 0.008 normalized threshold against x/y 0.5 and the centers of non-selected elements. Holding Alt bypasses snapping. Editor-only `guideX` / `guideY` are visible only while an active drag is snapped.

Arrow keys nudge the selected group by 0.002 normalized units; Shift+Arrow uses 0.01. Numeric X/Y fields display 0-100 percentages for the primary selected element and translate the selected group by the resulting delta.

- [ ] **Step 4: Re-run focused editor tests**

```bash
bash tests/test-quickshell-lockscreen-editor-tooling.sh
bash tests/test-quickshell-lockscreen-editor-flick.sh
bash tests/test-quickshell-lockscreen-live-editor.sh
bash tests/test-quickshell-lockscreen-editor-config-boundary.sh
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add config/quickshell/awtarchy/LockscreenEditor.qml tests/test-quickshell-lockscreen-editor-tooling.sh .github/workflows/validate-quickshell-lockscreen-interactive-effects.yml
git commit -m "feat: add lockscreen editor layout tooling"
```

### Task 2: Wallpaper fit, focal point, overlay dimming/lightening, and optional blur

**Files:**
- Modify: `config/hypr/scripts/quickshell_application_state.sh`
- Modify: `config/quickshell/awtarchy/BarState.qml`
- Modify: `config/quickshell/awtarchy/LockscreenEditor.qml`
- Modify: `config/quickshell/awtarchy/LockPreviewScene.qml`
- Modify: `config/quickshell/awtarchy-lock/LockScene.qml`
- Modify: `config/quickshell/awtarchy-lock/shell.qml`
- Test: `tests/test-quickshell-lockscreen-background-composition.sh`

**Interfaces:**
- Persist: `lockscreen_wallpaper_fit` = `cover|contain`, `lockscreen_wallpaper_focal_x/y` = 0..1, `lockscreen_overlay_mode` = `none|dark|light`, `lockscreen_overlay_strength` = 0..100, `lockscreen_wallpaper_blur` = 0..100.
- Scene inputs: `wallpaperFit`, `wallpaperFocalX`, `wallpaperFocalY`, `overlayMode`, `overlayStrength`, `wallpaperBlur`.

- [ ] **Step 1: Write failing persistence/presentation contract**

Require strict validation/defaults, atomic editor save/reset, secure-shell normalization, scene parity, focal cover positioning, contain centering, overlay rendering, and `MultiEffect` blur only for wallpaper mode.

- [ ] **Step 2: Verify RED**

```bash
bash tests/test-quickshell-lockscreen-background-composition.sh
```

Expected: failure because these state fields and scene inputs do not exist.

- [ ] **Step 3: Implement state and scene behavior**

For cover mode, size the wallpaper to preserve aspect ratio while filling the screen and place overflow using focal coordinates: x/y 0 selects the leading crop edge, 0.5 centers, 1 selects the trailing edge. Contain mode centers the fitted image and ignores focal coordinates. Use an editor-only draggable focal marker when wallpaper mode is active.

Overlay mode `dark` paints black at `strength / 100`, `light` paints white at `strength / 100`, and `none` is transparent. Blur is 0..100 and maps to `MultiEffect.blur` 0..1. The background layer remains presentation-only and contains no network/authentication logic.

- [ ] **Step 4: Run focused tests**

```bash
bash -n config/hypr/scripts/quickshell_application_state.sh
shellcheck config/hypr/scripts/quickshell_application_state.sh
bash tests/test-quickshell-lockscreen-background-composition.sh
bash tests/test-quickshell-lockscreen-runtime-polish.sh
bash tests/test-quickshell-lockscreen-live-editor.sh
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add config/hypr/scripts/quickshell_application_state.sh config/quickshell/awtarchy/BarState.qml config/quickshell/awtarchy/LockscreenEditor.qml config/quickshell/awtarchy/LockPreviewScene.qml config/quickshell/awtarchy-lock/LockScene.qml config/quickshell/awtarchy-lock/shell.qml tests/test-quickshell-lockscreen-background-composition.sh
git commit -m "feat: add lockscreen background composition controls"
```

### Task 3: Weather units

**Files:**
- Modify: `config/hypr/scripts/quickshell_application_state.sh`
- Modify: `config/hypr/scripts/quickshell_lockscreen_weather.sh`
- Modify: `config/quickshell/awtarchy/BarState.qml`
- Modify: `config/quickshell/awtarchy/LockscreenWeather.qml`
- Modify: `config/quickshell/awtarchy/LockscreenEditor.qml`
- Test: `tests/test-quickshell-lockscreen-weather-units.sh`

**Interfaces:**
- Persist: `lockscreen_weather_units` = `auto|fahrenheit|celsius`.
- Weather helper: `refresh <location> <units>` where `auto` resolves Fahrenheit for a US locale and Celsius otherwise.

- [ ] **Step 1: Write failing weather-unit contract**

Require enum validation, state default `auto`, helper request-unit mapping, and refresh invalidation when units change.

- [ ] **Step 2: Verify RED**

```bash
bash tests/test-quickshell-lockscreen-weather-units.sh
```

Expected: failure because weather units are currently fixed to Fahrenheit.

- [ ] **Step 3: Implement minimal unit selection**

Pass `fahrenheit` or `celsius` to Open-Meteo. For `auto`, resolve the locale from `LC_ALL`, then `LC_MEASUREMENT`, then `LANG`; locales containing `_US` use Fahrenheit and other locales use Celsius. Include the resolved unit in the cache request identity so changing units refreshes immediately.

- [ ] **Step 4: Run weather tests**

```bash
bash -n config/hypr/scripts/quickshell_lockscreen_weather.sh
shellcheck config/hypr/scripts/quickshell_lockscreen_weather.sh
bash tests/test-quickshell-lockscreen-weather.sh
bash tests/test-quickshell-lockscreen-weather-units.sh
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add config/hypr/scripts/quickshell_application_state.sh config/hypr/scripts/quickshell_lockscreen_weather.sh config/quickshell/awtarchy/BarState.qml config/quickshell/awtarchy/LockscreenWeather.qml config/quickshell/awtarchy/LockscreenEditor.qml tests/test-quickshell-lockscreen-weather-units.sh
git commit -m "feat: add lockscreen weather units"
```

### Task 4: Editor grid and stock layout presets

**Files:**
- Modify: `config/quickshell/awtarchy/LockscreenEditor.qml`
- Test: `tests/test-quickshell-lockscreen-editor-presets.sh`

**Interfaces:**
- Transient: `showEditorGrid` boolean.
- Presets: `minimal`, `centered`, `information`, `lower-third`.

- [ ] **Step 1: Write failing preset/grid contract**

Require editor-only center/thirds/safe-area guides and four deterministic presets. Applying a preset records one undo snapshot, changes only layout/visibility, preserves element colors and background state, and keeps Password visible.

- [ ] **Step 2: Verify RED**

```bash
bash tests/test-quickshell-lockscreen-editor-presets.sh
```

Expected: failure because the grid/preset APIs do not exist.

- [ ] **Step 3: Implement grid and presets**

Minimal shows Logo + Password. Centered shows Logo + Time + Date + Password. Information shows all elements in a centered stack. Lower Third keeps Logo high and places Time/Date/Username/Weather as a lower information cluster above Password. Preserve each element's current `color` when applying preset geometry.

- [ ] **Step 4: Run editor tests**

```bash
bash tests/test-quickshell-lockscreen-editor-presets.sh
bash tests/test-quickshell-lockscreen-editor-tooling.sh
bash tests/test-quickshell-lockscreen-live-editor.sh
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add config/quickshell/awtarchy/LockscreenEditor.qml tests/test-quickshell-lockscreen-editor-presets.sh
git commit -m "feat: add lockscreen layout presets"
```

### Task 5: Managed history and final verification

**Files:**
- Modify: `local/share/awtarchy/quickshell-managed-history.sha256`
- Modify: PR #181 description / issue #187 only as metadata.

**Interfaces:**
- Append current stock hashes only; never delete prior managed hashes.

- [ ] **Step 1: Append exact current managed hashes for every changed managed Quickshell/helper file**

Use the same path scope enforced by the updater migration tests and append only absent `<sha256>\t.<repo-path>` records.

- [ ] **Step 2: Run focused and broad validation**

```bash
bash tests/test-quickshell-lockscreen-editor-flick.sh
bash tests/test-quickshell-lockscreen-editor-tooling.sh
bash tests/test-quickshell-lockscreen-editor-presets.sh
bash tests/test-quickshell-lockscreen-background-composition.sh
bash tests/test-quickshell-lockscreen-weather.sh
bash tests/test-quickshell-lockscreen-weather-units.sh
bash tests/test-quickshell-lockscreen-interactive-managed-history.sh
git diff --check
```

Then require the exact final PR head to pass `Validate Quickshell Lockscreen Interactive Effects`, `Validate Quickshell Lockscreen Foundation`, `Validate Runtime Stress Analysis`, `Validate Quick Settings Layout`, and full `Validate Awtarchy` command/updater integration.

- [ ] **Step 3: Verify security and target state**

Confirm `LockAuth.qml` is unchanged, `WlSessionLock` remains the only lock authority, PR #181 remains draft/open/unmerged, current `main` is fully incorporated, and no release/tag changed.

- [ ] **Step 4: Commit final history-only bookkeeping if required**

```bash
git add local/share/awtarchy/quickshell-managed-history.sha256
git commit -m "chore: record lockscreen editor managed history"
```
