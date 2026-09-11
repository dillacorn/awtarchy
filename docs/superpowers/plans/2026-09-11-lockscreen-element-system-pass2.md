# Lockscreen Element System Pass 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a backward-compatible generic lockscreen transform model with per-element opacity and user-inserted local image elements while preserving the existing secure authentication architecture.

**Architecture:** Keep built-in element state in the existing `lockscreen_layout` object and extend each point with normalized opacity/stretch defaults. Store user images in a separate bounded `lockscreen_custom_images` array, then make the secure scene and unlocked editor consume both through shared transform helpers. Persist layout, images, visibility, and background composition atomically through the existing application-state helper.

**Tech Stack:** Bash + jq persistence/validation, Quickshell QML, GitHub Actions shell regressions.

**Spec:** `docs/superpowers/specs/2026-09-11-lockscreen-element-system-pass2-design.md`

## Global Constraints

- `WlSessionLock` remains the sole lock authority.
- `LockAuth.qml` remains the PAM/authentication owner and must remain unchanged.
- Custom image paths are local-only, validated, canonicalized, bounded, and never enter authentication state.
- Password visibility remains required; password presentation opacity has a 20% minimum.
- Existing persisted layouts must load with safe defaults for every new field.
- Production changes follow RED -> GREEN TDD.
- No release/tag changes.
- Runtime/visual behavior is not called verified until maintainer testing on real Hyprland.

---

### Task 1: Add the failing Pass 2 contract

**Files:**
- Create: `tests/test-quickshell-lockscreen-element-system.sh`
- Modify: `.github/workflows/validate-quickshell-lockscreen-interactive-effects.yml`

**Interfaces:**
- Consumes: existing `quickshell_application_state.sh`, `BarState.qml`, `LockscreenEditor.qml`, secure/preview scenes.
- Produces: executable regression contract for the complete Pass 2 state/render/editor boundary.

- [ ] **Step 1: Write the failing test**

Create a shell regression that requires:

```bash
require_text "$APP_STATE" 'lockscreen_custom_images' 'custom image persistence is missing'
require_text "$SCENE" 'required property var customImages' 'secure scene has no custom images'
require_text "$EDITOR" 'function addCustomImage(' 'editor cannot add custom images'
require_text "$EDITOR" 'Opacity' 'editor has no element opacity control'
require_text "$EDITOR" 'Stretch X' 'editor has no horizontal stretch control'
require_text "$EDITOR" 'Stretch Y' 'editor has no vertical stretch control'
```

The same test must invoke the state helper with legacy and expanded layouts, create temporary readable image files, prove invalid image paths/duplicate IDs/password opacity below 20 are rejected, prove malformed saves do not mutate the state file, and prove Reset clears `lockscreen_custom_images`.

- [ ] **Step 2: Run it through PR CI and verify RED**

Add the test to syntax, ShellCheck, and Customization editor steps in `validate-quickshell-lockscreen-interactive-effects.yml`.

Expected: `Validate Quickshell Lockscreen Interactive Effects` fails specifically because Pass 2 production symbols/state are absent.

- [ ] **Step 3: Record the failing run before production changes**

Use the exact commit SHA and GitHub Actions logs as RED evidence.

### Task 2: Extend atomic persistence and normalized readers

**Files:**
- Modify: `config/hypr/scripts/quickshell_application_state.sh`
- Modify: `config/quickshell/awtarchy/BarState.qml`

**Interfaces:**
- Produces built-in normalized entries `{x,y,scale,stretch_x,stretch_y,opacity,color}`.
- Produces `lockscreen_custom_images` normalized array with entries `{id,path,x,y,scale,stretch_x,stretch_y,opacity,visible}`.
- `save-lockscreen-editor` gains the custom-images JSON argument while retaining legacy call compatibility where existing tests require it.

- [ ] **Step 1: Extend layout normalization minimally**

Accept the current legacy key combinations plus optional `stretch_x`, `stretch_y`, and `opacity`; normalize absent fields to `1`, `1`, and `100` respectively. Keep scale 0.50–2.00 and current safe x/y bounds. Enforce Password opacity 20–100 and other built-ins 0–100.

- [ ] **Step 2: Add custom-image normalization**

Implement one validator/normalizer that checks array type, max 12 entries, exact allowed keys, unique bounded `image-*` IDs, readable canonical absolute local path, general element x/y bounds, scale 0.50–2.00, stretch 0.25–4.00, opacity 0–100, and boolean visibility.

- [ ] **Step 3: Extend atomic editor save/reset**

Persist `.lockscreen_custom_images` in the same jq replacement as layout/background/weather state. Reset must set it to `[]`. No validation failure may partially write state.

- [ ] **Step 4: Extend `BarState.qml` readers/defaults**

Normalize legacy built-in layout entries with new defaults, expose `lockscreenCustomImages()`, and return `[]` for missing/invalid legacy state.

- [ ] **Step 5: Run the focused contract**

Expected: persistence/BarState portions become GREEN while scene/editor assertions still fail.

### Task 3: Extend secure and preview presentation

**Files:**
- Modify: `config/quickshell/awtarchy-lock/shell.qml`
- Modify: `config/quickshell/awtarchy-lock/LockSurface.qml`
- Modify: `config/quickshell/awtarchy-lock/LockScene.qml`
- Modify: `config/quickshell/awtarchy/LockPreviewScene.qml`

**Interfaces:**
- `LockScene` receives `required property var customImages`.
- Generic helpers expose stretch and configured opacity for any element.
- Secure shell re-normalizes persisted custom image objects before scene consumption.

- [ ] **Step 1: Normalize secure-shell state**

Add defaults/readers for built-in opacity/stretch and for the bounded custom image array. Reject protocol/control-character/non-absolute custom-image paths in the secure process. Do not add networking or auth access.

- [ ] **Step 2: Pass custom images through `LockSurface.qml`**

Add the presentation-only property and pass it into `LockScene`; leave the password `TextInput` submission/focus path unchanged.

- [ ] **Step 3: Add generic transform helpers to `LockScene.qml`**

Add `elementStretchX`, `elementStretchY`, `elementOpacity`, custom-image lookup, and local-file-source helpers. Existing styled alpha values multiply by configured opacity. Password decorative presentation uses its configured opacity while auth input behavior is unchanged.

- [ ] **Step 4: Render custom images below built-ins**

Render the ordered custom-image list above the background but under logo/text/password presentation. Missing/unloadable files display nothing. Expose their real visual dimensions to the editor-selection API.

- [ ] **Step 5: Preserve byte-identical scene parity**

Copy the finalized secure `LockScene.qml` content exactly to `LockPreviewScene.qml` and verify identical hashes.

- [ ] **Step 6: Run focused security/parity tests**

Expected: scene/shell portions GREEN; `LockAuth.qml` blob remains unchanged.

### Task 4: Make the unlocked editor generic enough for images and opacity

**Files:**
- Modify: `config/quickshell/awtarchy/LockscreenEditor.qml`

**Interfaces:**
- Editor snapshots include `customImages` and new transform fields.
- Selectable IDs are six built-ins plus current custom-image IDs.
- Existing drag/snap/nudge/group/resize routines operate through generic lookup/update helpers.

- [ ] **Step 1: Add draft custom-image state and generic lookup/update helpers**

Initialize from `BarState.lockscreenCustomImages()`. Add helpers to find custom image by ID, read/write its transform, read/write visibility, and distinguish built-ins from images.

- [ ] **Step 2: Include images in history and selection**

Undo/redo snapshots and restore must include custom images. Dynamic selection frames include images. Deleting a selected image repairs selection safely.

- [ ] **Step 3: Add draft Add/Remove Image behavior**

Reuse the existing Awtwall selection-only picker process. Wallpaper selection keeps its existing behavior; Add Image takes the returned local path and creates a unique draft `image-*` entry centered on the editor. Remove operates on draft only.

- [ ] **Step 4: Add generic precision controls**

Expose overall scale, Stretch X, Stretch Y, and Opacity for every selected element. Keep direct resize as the primary uniform scaling gesture. Images omit text color controls. Password opacity clamps to 20–100 and remains non-hideable.

- [ ] **Step 5: Extend atomic Save and Defaults**

Pass serialized custom images to the persistence helper. Restore Defaults empties draft images and resets built-in transforms.

- [ ] **Step 6: Run editor regressions**

Expected: the new Pass 2 test plus existing editor/flick/tooling/preset tests all pass.

### Task 5: Managed history and full verification

**Files:**
- Modify only if required: `local/share/awtarchy/quickshell-managed-history.sha256`

**Interfaces:**
- Managed updater recognizes final changed Quickshell managed-file hashes.

- [ ] **Step 1: Register final managed hashes only after content stabilizes**

Add only the hashes required by the existing managed-history regression.

- [ ] **Step 2: Run focused lockscreen validation**

Run/observe:

```bash
bash tests/test-quickshell-lockscreen-element-system.sh
bash tests/test-quickshell-lockscreen-live-editor.sh
bash tests/test-quickshell-lockscreen-editor-flick.sh
bash tests/test-quickshell-lockscreen-editor-tooling.sh
bash tests/test-quickshell-lockscreen-editor-presets.sh
bash tests/test-quickshell-lockscreen-interaction-polish.sh
bash tests/test-quickshell-lockscreen-interactive-effects.sh
bash tests/test-quickshell-lockscreen-interactive-managed-history.sh
```

Also run `bash -n` and ShellCheck on changed shell/tests.

- [ ] **Step 3: Run security/parity verification**

Verify `LockAuth.qml` is byte-identical to the base/current approved version and secure/preview scene files are byte-identical.

- [ ] **Step 4: Observe all PR CI on one exact final SHA**

Require every PR-triggered workflow, including full `Validate Awtarchy`, lockscreen foundation, interactive effects, and runtime stress analysis, to complete successfully.

- [ ] **Step 5: Stop before merge**

Provide the exact 40-character runtime-test SHA. PR #181 remains draft/unmerged and no release/tag is changed.