# Lockscreen Runtime Acceptance #187 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the runtime-rejected lockscreen transition/editor behavior with the approved desktop-to-lockscreen architecture and produce a new exact PR #181 runtime-test candidate without claiming Hyprland runtime success.

**Architecture:** Capture each active Hyprland output immediately before requesting `WlSessionLock`, then let the secure lock surface own the entire visible transition from that frozen desktop frame into the real lockscreen. A reusable `LockTransitionLayer.qml` supplies bounded two-source Fade/Wipe/Edges/Reverse-Iris/Resolution-Collapse effects to both secure runtime and a synthetic editor replay source. Keep one persisted state path for editor/runtime transforms, use one high defensive scale limit, and keep all authentication data inside the existing secure `LockAuth.qml`/password path.

**Tech Stack:** Bash, jq, grim, Qt 6 QML/Quickshell, `ShaderEffectSource`, `MultiEffect`, CAVA raw output, Hyprland JSON/dispatch, shell regression tests, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-12-lockscreen-runtime-corrections-design.md`

## Global Constraints

- `WlSessionLock` remains the sole lock authority.
- `LockAuth.qml` remains the PAM/authentication owner and must not be modified.
- Production changes use RED/GREEN TDD.
- Secure/editor presentation parity remains exact where the design requires it.
- Transition captures stay below a validated owner-only `XDG_RUNTIME_DIR` root and fail closed to black.
- No release, tag, merge, force-push, or unrelated branch operations.
- Runtime, visual, audio, and compositor behavior remains unverified until maintainer testing on Hyprland.
- Managed Quickshell/config history must be refreshed for every changed managed file before the candidate is handed off.

---

### Task 1: Secure pre-lock capture helper

**Files:**
- Create: `config/hypr/scripts/quickshell_lockscreen_capture.sh`
- Modify: `config/hypr/scripts/awtarchy_lock.sh`
- Test: `tests/test-quickshell-lockscreen-capture.sh`

**Interfaces:**
- `quickshell_lockscreen_capture.sh prepare` prints exactly one validated capture directory on success and returns nonzero without a directory on failure.
- `quickshell_lockscreen_capture.sh cleanup <capture-dir>` removes only a validated owned `capture.*` directory directly below `$XDG_RUNTIME_DIR/awtarchy-lock-transition`.
- `awtarchy_lock.sh lock` passes a successful directory only to the spawned Quickshell process as `AWTARCHY_LOCK_CAPTURE_DIR`; capture failure does not prevent lock startup.

- [ ] **Step 1: Write the failing capture contract test**

Create a fake `hyprctl` returning two output names and a fake `grim` writing deterministic bytes. Assert owner-only root/file modes, one file per output, partial-capture cleanup, unsafe output rejection, stale cleanup confinement, and `awtarchy_lock.sh` fail-closed fallback.

```bash
bash tests/test-quickshell-lockscreen-capture.sh
```

Expected before implementation: FAIL because `quickshell_lockscreen_capture.sh` does not exist and `awtarchy_lock.sh` never exports `AWTARCHY_LOCK_CAPTURE_DIR`.

- [ ] **Step 2: Implement the capture helper**

Use this production shape, with the final script retaining the same validation boundaries:

```bash
#!/usr/bin/env bash
set -euo pipefail
umask 077

runtime_dir="${XDG_RUNTIME_DIR:-}"
root="${runtime_dir}/awtarchy-lock-transition"

validate_runtime_root() {
    [[ -n "$runtime_dir" && -d "$runtime_dir" && ! -L "$runtime_dir" && -O "$runtime_dir" ]]
}

safe_output_name() {
    [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]]
}

prepare_capture() {
    validate_runtime_root || return 1
    mkdir -p -m 700 -- "$root"
    [[ -d "$root" && ! -L "$root" && -O "$root" ]] || return 1
    find "$root" -mindepth 1 -maxdepth 1 -type d -user "$(id -un)" -name 'capture.*' -exec rm -rf -- {} +
    local dir
    dir="$(mktemp -d "${root}/capture.XXXXXX")"
    chmod 700 -- "$dir"
    mapfile -t outputs < <(hyprctl monitors -j | jq -er '.[].name')
    ((${#outputs[@]} > 0)) || { rm -rf -- "$dir"; return 1; }
    for output in "${outputs[@]}"; do
        safe_output_name "$output" || { rm -rf -- "$dir"; return 1; }
        grim -l 1 -o "$output" "${dir}/${output}.png" || { rm -rf -- "$dir"; return 1; }
        chmod 600 -- "${dir}/${output}.png"
        [[ -f "${dir}/${output}.png" && ! -L "${dir}/${output}.png" \
            && -O "${dir}/${output}.png" && -r "${dir}/${output}.png" \
            && -s "${dir}/${output}.png" ]] || { rm -rf -- "$dir"; return 1; }
    done
    printf '%s\n' "$dir"
}
```

Implement cleanup with canonical parent/name/ownership checks rather than accepting arbitrary paths.

- [ ] **Step 3: Wire capture into lock startup**

Immediately before `nohup "$QS_BIN" -c awtarchy-lock`, call the helper. Spawn with:

```bash
AWTARCHY_LOCK_CAPTURE_DIR="$capture_dir" nohup "$QS_BIN" -c "$CONFIG_NAME" >>"$LOG_FILE" 2>&1 &
```

when capture succeeds; otherwise unset the variable for the child and continue acquiring the lock.

- [ ] **Step 4: Verify RED->GREEN and shell syntax**

```bash
bash tests/test-quickshell-lockscreen-capture.sh
bash -n config/hypr/scripts/quickshell_lockscreen_capture.sh
bash -n config/hypr/scripts/awtarchy_lock.sh
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add config/hypr/scripts/quickshell_lockscreen_capture.sh \
  config/hypr/scripts/awtarchy_lock.sh tests/test-quickshell-lockscreen-capture.sh
git commit -m "Add secure lockscreen transition capture"
```

### Task 2: Reusable two-source transition renderer

**Files:**
- Create: `config/quickshell/awtarchy-lock/LockTransitionLayer.qml`
- Modify: `config/quickshell/awtarchy-lock/LockSurface.qml`
- Modify: `config/quickshell/awtarchy-lock/shell.qml`
- Test: `tests/test-quickshell-lockscreen-transition-layer.sh`

**Interfaces:**
- `LockTransitionLayer` consumes `startSource: Item`, `endSource: Item`, `mode: string`, `duration: int`, and `replayToken: int`.
- It exposes `running: bool`, `progress: real`, and `finished()`.
- Valid duration is 800-6000 ms, default 1800 ms.
- `pixel` uses `ShaderEffectSource.textureSize` and nearest-neighbor sampling with a bounded coarse size; no random black tiles.

- [ ] **Step 1: Write the failing transition contract**

Assert that Pixel contains two `ShaderEffectSource` inputs, dynamic `textureSize`, `smooth: false`, midpoint source blend, no black tile repeater, and that Fade/Wipe/Edges/Iris reference the real start/end sources. Assert 1800 default/800-6000 normalization and a post-transition signal.

```bash
bash tests/test-quickshell-lockscreen-transition-layer.sh
```

Expected before implementation: FAIL because the component is absent and the current transition remains a black cover in `LockScene.qml`.

- [ ] **Step 2: Implement `LockTransitionLayer.qml`**

The Pixel phase must follow this normalized model:

```qml
readonly property real collapseAmount: progress < 0.5
    ? progress / 0.5 : (1.0 - progress) / 0.5
readonly property real sourceBlend: Math.max(0, Math.min(1, (progress - 0.45) / 0.10))
readonly property real coarseFactor: 1 + 47 * Math.pow(collapseAmount, 1.35)
readonly property size reducedTextureSize: Qt.size(
    Math.max(1, Math.round(width * devicePixelRatio / coarseFactor)),
    Math.max(1, Math.round(height * devicePixelRatio / coarseFactor)))
```

Use `ShaderEffectSource` for both source items with `textureSize: reducedTextureSize` and `smooth: false`; crossfade only around the maximally coarse midpoint. Other modes reveal `endSource` while masking/clipping the frozen `startSource`, never a black decorative cover.

- [ ] **Step 3: Make `LockSurface.qml` the secure transition coordinator**

Set the surface color to opaque black. Derive a validated `file://` capture URL from `AWTARCHY_LOCK_CAPTURE_DIR` plus `screen.name`; load it synchronously/boundedly and fall back to black when status is not `Image.Ready`.

Build one hidden transition start source and one real secure end-source container. Gate password opacity, configured logo formation, and other entrance motion until `LockTransitionLayer.running` becomes false. Do not modify `LockAuth.qml`.

- [ ] **Step 4: Pass capture/timing state from `shell.qml`**

Keep `WlSessionLock` creation unchanged except for presentation-only properties needed by `LockSurface`. Cleanup the capture directory through the validated capture helper after the handoff and again before unlock/termination paths.

- [ ] **Step 5: Verify focused transition/security tests**

```bash
bash tests/test-quickshell-lockscreen-transition-layer.sh
bash tests/test-quickshell-lockscreen-foundation.sh
bash tests/test-quickshell-lockscreen-security.sh
```

Expected: PASS; no auth ownership changes.

- [ ] **Step 6: Commit**

```bash
git add config/quickshell/awtarchy-lock/LockTransitionLayer.qml \
  config/quickshell/awtarchy-lock/LockSurface.qml \
  config/quickshell/awtarchy-lock/shell.qml \
  tests/test-quickshell-lockscreen-transition-layer.sh
git commit -m "Fix desktop to lockscreen transitions"
```

### Task 3: Captured-desktop blur and transparency

**Files:**
- Modify: `config/quickshell/awtarchy-lock/LockSurface.qml`
- Modify: `config/quickshell/awtarchy/LockscreenEditor.qml`
- Modify: `config/quickshell/awtarchy/QuickSettings.qml`
- Test: `tests/test-quickshell-lockscreen-background-controls.sh`

**Interfaces:**
- `backgroundOpacity` remains background-only.
- `wallpaperBlur` becomes secure captured-backing blur as well as wallpaper blur when a wallpaper is selected.
- First opacity reduction below 100 seeds blur only while blur is still untouched/zero.

- [ ] **Step 1: Extend the background test to RED**

Require a capture-backed `MultiEffect` below `LockScene`, opaque-black fallback, ungated editor opacity/blur/brightness tracks, first-transparency blur seeding, and absence of duplicated precision controls in Quick Settings.

```bash
bash tests/test-quickshell-lockscreen-background-controls.sh
```

Expected: FAIL on captured-backing blur and remaining precision-control ownership gaps.

- [ ] **Step 2: Implement secure backing blur**

Render the already-loaded captured frame through `MultiEffect` below `LockScene`:

```qml
MultiEffect {
    anchors.fill: parent
    source: desktopBackingImage
    autoPaddingEnabled: false
    blurEnabled: root.wallpaperBlur > 0
    blurMax: 32
    blur: Math.max(0, Math.min(1, root.wallpaperBlur / 100))
}
```

Black remains the base when the image is unavailable.

- [ ] **Step 3: Finish editor ownership**

Use the same custom track/thumb/value-entry component pattern already used for display brightness/output limit. Slider movement directly changes signed brightness, blur, or opacity without prerequisite mode buttons. When opacity first crosses below 100 and blur is untouched/zero, set the approved seeded blur value once.

- [ ] **Step 4: Remove duplicate Quick Settings precision controls**

Keep editor launch and useful on/off actions only; do not create a second state variable.

- [ ] **Step 5: Verify and commit**

```bash
bash tests/test-quickshell-lockscreen-background-controls.sh
bash tests/test-quickshell-lockscreen-quick-settings.sh
git add config/quickshell/awtarchy-lock/LockSurface.qml \
  config/quickshell/awtarchy/LockscreenEditor.qml \
  config/quickshell/awtarchy/QuickSettings.qml tests/test-quickshell-lockscreen-background-controls.sh
git commit -m "Fix lockscreen background blur controls"
```

### Task 4: Editor replay and duration control

**Files:**
- Modify: `config/quickshell/awtarchy/LockscreenEditor.qml`
- Modify: persistent state helper/`BarState.qml` only where normalization/defaults need changing
- Test: `tests/test-quickshell-lockscreen-editor-transitions.sh`

**Interfaces:**
- Persisted duration default 1800, valid 800-6000.
- Replay uses `LockTransitionLayer.qml` with an editor-generated synthetic start source; it never invokes grim/screencopy.

- [ ] **Step 1: Write RED contracts for replay safety/style**

Require the shared component, the synthetic start source, no capture helper call from editor, and the established custom slider/value-entry interaction.

```bash
bash tests/test-quickshell-lockscreen-editor-transitions.sh
```

Expected: FAIL.

- [ ] **Step 2: Replace the stock replay path**

Create a neutral editor-only desktop mock from QML rectangles/window silhouettes and pass it as `startSource`. The actual editor lock preview is `endSource`. Both real lock and Replay consume the same normalized duration.

- [ ] **Step 3: Replace the stock speed slider**

Use the existing brightness/max-volume track interaction pattern, normalize 800-6000 ms, and display/edit the exact millisecond value.

- [ ] **Step 4: Verify and commit**

```bash
bash tests/test-quickshell-lockscreen-editor-transitions.sh
bash tests/test-quickshell-lockscreen-state.sh
git add config/quickshell/awtarchy/LockscreenEditor.qml \
  config/quickshell/awtarchy/BarState.qml tests/test-quickshell-lockscreen-editor-transitions.sh
git commit -m "Finish lockscreen transition editor controls"
```

### Task 5: Remove the 200% ceiling and add custom-image rotation/reset

**Files:**
- Modify: persistent state helper and `BarState.qml`
- Modify: `config/quickshell/awtarchy/LockscreenEditor.qml`
- Modify: `config/quickshell/awtarchy-lock/LockScene.qml`
- Modify: preview scene copy if still separate
- Test: `tests/test-quickshell-lockscreen-element-transforms.sh`

**Interfaces:**
- One defensive scale limit: `100.0` for built-ins, visualizer, and custom images.
- Custom image state gains normalized `rotation` degrees.
- Selected-element `Reset to Default` exists for every element; custom-image reset preserves its asset/path/id while resetting transform/presentation fields.

- [ ] **Step 1: Write RED contracts**

Assert no `2.00`/200% transform ceiling remains in validation/editor/renderer, all scalable paths share 100x, custom images persist/render rotation, Delete removes selected custom images, and every selected element exposes Reset to Default.

```bash
bash tests/test-quickshell-lockscreen-element-transforms.sh
```

Expected: FAIL on built-in/visualizer ceilings and missing rotation/reset behavior.

- [ ] **Step 2: Normalize transforms in the single persistence path**

Use shared validation equivalent to:

```js
const scale = Math.max(0.10, Math.min(100.0, Number(value.scale)));
const rotation = ((Number(value.rotation || 0) % 360) + 540) % 360 - 180;
```

Reject non-finite values rather than silently storing them.

- [ ] **Step 3: Update editor direct manipulation**

Resize handles and numeric scale use the same 100x state. Add a visible rotation handle for selected custom images plus numeric rotation entry. Route Delete through `removeCustomImage()` while editor focus is inside the canvas/toolbar, and include rotation/reset/delete in the existing history snapshot.

- [ ] **Step 4: Update secure rendering/reset parity**

Apply `rotation` on custom-image render items and ensure secure/editor scenes use the same normalized state. Add selected-element Reset to Default while retaining Reset Position and Reset All.

- [ ] **Step 5: Verify and commit**

```bash
bash tests/test-quickshell-lockscreen-element-transforms.sh
bash tests/test-quickshell-lockscreen-editor.sh
bash tests/test-quickshell-lockscreen-state.sh
git add config/quickshell/awtarchy/LockscreenEditor.qml \
  config/quickshell/awtarchy-lock/LockScene.qml \
  config/quickshell/awtarchy/BarState.qml tests/test-quickshell-lockscreen-element-transforms.sh
git commit -m "Expand lockscreen element transforms"
```

### Task 6: Visualizer width, bend, and response modes

**Files:**
- Modify: persistent state helper/`BarState.qml`
- Modify: `config/quickshell/awtarchy/LockscreenEditor.qml`
- Modify: visualizer analyzer/helper/CAVA config path
- Modify: secure/preview scene visualizer rendering
- Test: `tests/test-quickshell-lockscreen-visualizer-response.sh`

**Interfaces:**
- Modes: balanced 60 FPS, responsive 90 FPS, high-response 120 FPS.
- Default sensitivity increases from the rejected candidate.
- Arc bend defensive range `-2000..2000`, numeric editing only.
- Visualizer width becomes persisted independent width state with direct resize/numeric edit and secure/editor parity.

- [ ] **Step 1: Write RED contracts**

Require 60/90/120 source cadence, direct frame assignment with no visible smoothing/interpolation timer, higher default sensitivity, width state, wide signed bend, and identical data path for straight/arc/circle.

```bash
bash tests/test-quickshell-lockscreen-visualizer-response.sh
```

Expected: FAIL on high-response mode, width, bend range, and default sensitivity.

- [ ] **Step 2: Update source cadence and parsing**

Map the persisted mode to actual CAVA framerate, keep direct parsed frame assignment, and preserve malformed-input zero/fail-safe behavior.

- [ ] **Step 3: Update state and editor**

Add width to the existing visualizer object. Replace Arc Bend slider with signed numeric input. Add direct horizontal resize handle plus exact width input. Include width/bend in history and reset.

- [ ] **Step 4: Update rendering and verify**

Use the persisted width instead of fixed 520/380 base width where applicable while keeping bounded bar geometry.

```bash
bash tests/test-quickshell-lockscreen-visualizer-response.sh
bash tests/test-quickshell-lockscreen-visualizer.sh
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add config/quickshell tests/test-quickshell-lockscreen-visualizer-response.sh
git commit -m "Improve lockscreen visualizer controls"
```

### Task 7: Awtwall mapped-window fullscreen and Quick Settings placement

**Files:**
- Modify: `config/hypr/scripts/quickshell_lockscreen_wallpaper_picker.sh`
- Modify: `config/quickshell/awtarchy/QuickSettings.qml`
- Test: `tests/test-quickshell-lockscreen-wallpaper-picker.sh`
- Test: relevant Quick Settings layout test

**Interfaces:**
- Exact picker class/title remain `awtarchy-lock-wallpaper` / `Awtarchy-Lockscreen-Wallpaper`.
- Fullscreen targets the exact mapped client address and verifies/retries that address for a bounded period.
- `Edit Layout` appears in the lockscreen section right column directly below Collapse.

- [ ] **Step 1: Write RED mapped-window test**

Fake `hyprctl clients -j` so the client appears only after more than the rejected one-second polling window. Require address-targeted focus/fullscreen and verified fullscreen state while preserving Awtwall `--select-only` argv.

```bash
bash tests/test-quickshell-lockscreen-wallpaper-picker.sh
```

Expected: FAIL against the short class-only polling implementation.

- [ ] **Step 2: Implement bounded address-targeted wait**

Capture the exact mapped address with jq, then use:

```bash
hyprctl dispatch focuswindow "address:^${window_address}$"
hyprctl dispatch fullscreen 1
```

Re-read that exact client and retry until `.fullscreen` is nonzero or the bounded wait ends. Keep Alacritty `window.startup_mode=Fullscreen` as an initial hint, not proof.

- [ ] **Step 3: Move Edit Layout below Collapse**

Restructure only the lockscreen Quick Settings header/actions so the right-side control column contains Collapse/Expand then Edit Layout. Do not duplicate editor precision controls.

- [ ] **Step 4: Verify and commit**

```bash
bash tests/test-quickshell-lockscreen-wallpaper-picker.sh
bash tests/test-quickshell-lockscreen-quick-settings.sh
bash -n config/hypr/scripts/quickshell_lockscreen_wallpaper_picker.sh
git add config/hypr/scripts/quickshell_lockscreen_wallpaper_picker.sh \
  config/quickshell/awtarchy/QuickSettings.qml \
  tests/test-quickshell-lockscreen-wallpaper-picker.sh
git commit -m "Fix lockscreen wallpaper picker lifecycle"
```

### Task 8: Logo physics visual-quality retune

**Files:**
- Modify: `config/quickshell/awtarchy-lock/LockScene.qml`
- Modify: preview scene copy if still separate
- Test: `tests/test-quickshell-lockscreen-logo-physics.sh`

**Interfaces:**
- Solver remains active only during hover deformation, explosion, or spring return.
- Repeated click adds bounded impulse to current velocity.
- No connector-line effect.

- [ ] **Step 1: Extend physics contracts before tuning**

Assert idle timer shutdown, coherent neighbor hover field, repeated impulse without state reset, clamped velocity, collision/bounds behavior, and spring return.

```bash
bash tests/test-quickshell-lockscreen-logo-physics.sh
```

Expected: existing structural checks may pass; add at least one new rejected-candidate quality contract (for example, no hard scatter cutoff/reset during active return) that fails before the retune.

- [ ] **Step 2: Retune the bounded solver minimally**

Adjust spring/damping/restitution/scatter constants only after the failing contract identifies the rejected behavior. Preserve the same fixed particle count and bucket collision bound.

- [ ] **Step 3: Verify and commit**

```bash
bash tests/test-quickshell-lockscreen-logo-physics.sh
bash tests/test-quickshell-lockscreen-interactions.sh
git add config/quickshell/awtarchy-lock/LockScene.qml tests/test-quickshell-lockscreen-logo-physics.sh
git commit -m "Retune lockscreen logo physics"
```

Runtime appearance remains pending maintainer Hyprland testing even when these tests pass.

### Task 9: Managed history and focused regression sweep

**Files:**
- Modify: `local/share/awtarchy/quickshell-managed-history.sha256`
- Modify tests only if a genuine current contract requires it

- [ ] **Step 1: Refresh every changed managed-file hash using the repository's existing history format**

For each changed managed source, compute its current SHA-256 and add the exact installed-path entry without deleting historical accepted hashes.

- [ ] **Step 2: Run focused lockscreen/security syntax suite**

```bash
bash -n config/hypr/scripts/awtarchy_lock.sh
bash -n config/hypr/scripts/quickshell_lockscreen_capture.sh
bash -n config/hypr/scripts/quickshell_lockscreen_wallpaper_picker.sh
bash tests/test-quickshell-lockscreen-foundation.sh
bash tests/test-quickshell-lockscreen-security.sh
bash tests/test-quickshell-lockscreen-state.sh
bash tests/test-quickshell-lockscreen-runtime-acceptance-187.sh
bash tests/test-quickshell-lockscreen-capture.sh
bash tests/test-quickshell-lockscreen-transition-layer.sh
bash tests/test-quickshell-lockscreen-background-controls.sh
bash tests/test-quickshell-lockscreen-editor-transitions.sh
bash tests/test-quickshell-lockscreen-element-transforms.sh
bash tests/test-quickshell-lockscreen-visualizer-response.sh
bash tests/test-quickshell-lockscreen-wallpaper-picker.sh
bash tests/test-quickshell-lockscreen-logo-physics.sh
git diff --check
```

Expected: PASS.

- [ ] **Step 3: Commit managed history**

```bash
git add local/share/awtarchy/quickshell-managed-history.sha256
git commit -m "Refresh lockscreen managed history"
```

### Task 10: Full PR validation and runtime candidate handoff

**Files:** PR #181 metadata and #187/#188/#189/#190 comments only after the code target is proven by CI.

- [ ] **Step 1: Run the broadest available local/in-CI validation**

Use `.github/workflows/validate-awtarchy.yml` as the command reference and require all lockscreen-specific workflows plus the full Awtarchy integration suite to pass on the exact same SHA.

- [ ] **Step 2: Verify repository state after writes**

Confirm PR #181 is still draft/unmerged, feature branch is not behind current `main`, no temporary write/helper workflow remains, and release/tag state is unchanged.

- [ ] **Step 3: Update PR/issues with evidence only**

Record the exact 40-character branch head and automated results. Explicitly state that desktop transition appearance, fullscreen behavior, logo physics feel, and visualizer responsiveness are still awaiting real Hyprland runtime confirmation.

- [ ] **Step 4: Handoff exact candidate command**

```bash
awtarchy git update --branch feature/lockscreen-interactive-effects --commit <EXACT_GREEN_SHA>
```

Do not mark #187 accepted or merge PR #181 until the maintainer reports the runtime result.
