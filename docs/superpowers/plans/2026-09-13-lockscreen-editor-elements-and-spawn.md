# Lockscreen Editor Elements and Spawn Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the approved lockscreen editor pass: themed fly-out spawn selectors, settled image preview with individual replay and during/after-logo timing, generic rotation, 12/24 toggle plus optional timezone clocks, arbitrary multiline/random text elements, and aligned explicit Cursor/Lockscreen Quick Settings actions.

**Architecture:** Extend the existing persisted presentation model instead of adding a second state system. Built-in layout points, visualizer, custom images, timezone clocks, and custom text all share normalized transform semantics; secure and editor renderers consume the same normalized state while authentication remains isolated in `LockAuth.qml`/`LockSurface.qml`.

**Tech Stack:** QML/QtQuick, Quickshell, Bash, jq, GitHub Actions, shell contract tests.

**Spec:** `docs/superpowers/specs/2026-09-13-lockscreen-editor-elements-and-spawn-design.md`

## Global Constraints

- `WlSessionLock` remains the sole lock authority.
- `LockAuth.qml` remains the PAM/authentication owner.
- Secure password input remains owned by the secure lock surface.
- Preserve the accepted Pixel / Resolution Collapse implementation.
- Existing persisted lockscreen state remains the source of truth; no parallel editor/runtime state.
- Legacy state without new fields must normalize to backward-compatible defaults.
- Use TDD for production changes.
- Runtime/visual/audio/compositor behavior remains unverified until maintainer Hyprland testing.
- Managed-history updates are append-only and must record current hashes for every changed managed stock file.
- PR #181 remains draft/unmerged; no release/tag mutation.

---

### Task 1: Lock the new UI/state contracts in RED tests

**Files:**
- Modify: `tests/test-quickshell-lockscreen-presentation-sequencing.sh`
- Modify: `tests/test-quickshell-lockscreen-rotation-reset.sh`
- Modify: `tests/test-quickshell-lockscreen-element-system.sh`
- Create: `tests/test-quickshell-lockscreen-timezones-text.sh`
- Create: `tests/test-quickshell-lockscreen-selector-flyout.sh`
- Create: `tests/test-quickshell-lockscreen-quicksettings-header.sh`
- Modify: `.github/workflows/validate-quickshell-lockscreen-interactive-effects.yml`

**Interfaces:**
- Consumes: current editor/scene/wrapper contracts at the approved green baseline.
- Produces: failing assertions for the exact properties/functions that Tasks 2–7 implement.

- [ ] **Step 1: Add selector RED assertions**

Require `LockscreenCompactSelector.qml` to own an explicit fly-out state and menu while rejecting the current left/right click-zone behavior:

```bash
contains "$SELECTOR" 'property bool menuOpen: false' 'selector has no fly-out open state'
contains "$SELECTOR" 'Repeater {' 'selector does not render an option fly-out'
contains "$SELECTOR" 'Keys.onEscapePressed' 'selector fly-out cannot cancel with Escape'
not_contains "$SELECTOR" 'mouse.x < width * 0.30' 'selector still cycles by click zone'
```

- [ ] **Step 2: Add image preview/sequencing RED assertions**

Require scene/editor contracts for settled edit mode, per-image replay, and timing:

```bash
require_text "$SCENE" 'readonly property bool customImageAnimationActive:' \
    'custom images have no explicit playback-only animation gate'
require_text "$SCENE" 'property string individualImageReplayId: ""' \
    'scene has no targeted image replay id'
require_text "$SCENE" 'property int individualImageReplayEpoch: 0' \
    'scene has no targeted image replay epoch'
require_text "$SCENE" 'spawn_timing' \
    'custom-image timing is not represented in the shared scene'
require_text "$EDITOR" 'function replaySelectedImageSpawn()' \
    'editor cannot replay only the selected image'
```

Assert that normal editor mode forces settled geometry unless a replay is active.

- [ ] **Step 3: Add generic rotation RED assertions**

Require `rotation` on default built-in layout points and visualizer, generic editor rotation dispatch, scene application, and password presentation rotation:

```bash
require_text "$SHELL_QML" 'rotation: 0' 'default built-in layout has no rotation field'
require_text "$EDITOR" 'function setElementRotation(name, value)' 'rotation is not generic'
require_text "$SURFACE" 'rotation: scene.elementRotation("password")' \
    'secure password presentation does not consume shared rotation'
```

Reject custom-image-only rotation guards in editor helpers.

- [ ] **Step 4: Add timezone/text RED test**

Create `tests/test-quickshell-lockscreen-timezones-text.sh` requiring:

```bash
contains "$EDITOR" 'property var draftTimezoneClocks: []' 'editor has no timezone clocks'
contains "$EDITOR" 'property var draftCustomTexts: []' 'editor has no custom text elements'
contains "$SCENE" 'required property var timezoneClocks' 'scene has no timezone clock input'
contains "$SCENE" 'required property var customTexts' 'scene has no custom text input'
contains "$EDITOR" 'function addTimezoneClock()' 'editor cannot add timezone clocks'
contains "$EDITOR" 'function addCustomText()' 'editor cannot add custom text'
contains "$EDITOR" 'alignment' 'custom text alignment is missing'
contains "$EDITOR" 'randomize' 'custom text randomization is missing'
```

Also execute the save wrapper against valid/invalid JSON to prove bounded atomic persistence and absence of password keys.

- [ ] **Step 5: Add Quick Settings header RED test**

Create `tests/test-quickshell-lockscreen-quicksettings-header.sh` and require explicit labels plus identical right-side action-column anchors:

```bash
contains "$QUICK" 'label: root.cursorSectionOpen ? "Collapse Cursor" : "Expand Cursor"' \
    'Cursor expansion label is ambiguous'
contains "$QUICK" 'label: root.lockscreenSectionOpen ? "Collapse Lockscreen" : "Expand Lockscreen"' \
    'Lockscreen expansion label is ambiguous'
contains "$QUICK" 'id: cursorSectionActions' 'Cursor header lacks aligned action column'
contains "$QUICK" 'id: lockscreenSectionActions' 'Lockscreen header lacks aligned action column'
```

Use a Python block to compare the two header action-column width/alignment declarations.

- [ ] **Step 6: Add new tests to the lockscreen workflow**

Add syntax, ShellCheck, and execution entries for the three new Bash tests.

- [ ] **Step 7: Run the focused RED suite**

Run in CI/branch workflow context:

```bash
bash tests/test-quickshell-lockscreen-selector-flyout.sh
bash tests/test-quickshell-lockscreen-presentation-sequencing.sh
bash tests/test-quickshell-lockscreen-rotation-reset.sh
bash tests/test-quickshell-lockscreen-element-system.sh
bash tests/test-quickshell-lockscreen-timezones-text.sh
bash tests/test-quickshell-lockscreen-quicksettings-header.sh
```

Expected: FAIL on missing fly-out, timing/replay, generic rotation, timezone/text, and explicit Quick Settings header contracts.

- [ ] **Step 8: Commit RED tests**

```bash
git add tests .github/workflows/validate-quickshell-lockscreen-interactive-effects.yml
git commit -m "test(lockscreen): cover editor elements and spawn pass"
```

---

### Task 2: Replace cycle controls with the themed fly-out and clock toggle

**Files:**
- Modify: `config/quickshell/awtarchy/LockscreenCompactSelector.qml`
- Modify: `config/quickshell/awtarchy/LockscreenEditor.qml`
- Test: `tests/test-quickshell-lockscreen-selector-flyout.sh`
- Test: `tests/test-quickshell-lockscreen-presentation-sequencing.sh`

**Interfaces:**
- Consumes: `model`, `currentIndex`, `activated(index)` selector API.
- Produces: same API with fly-out interaction; editor primary clock uses `draftClockFormat` toggle directly.

- [ ] **Step 1: Implement fly-out state and keyboard navigation**

Keep the public selector API and add:

```qml
property bool menuOpen: false
property int highlightedIndex: Math.max(0, currentIndex)
function openMenu() { highlightedIndex = Math.max(0, currentIndex); menuOpen = true; forceActiveFocus(); }
function closeMenu() { menuOpen = false; }
function activateHighlighted() { activated(highlightedIndex); menuOpen = false; }
```

Render an Awtarchy-themed option panel with `Repeater` and existing theme colors. Remove left/right click zones.

- [ ] **Step 2: Convert primary clock format to direct toggle**

Replace the selector in the Time settings row with one button whose label reflects the destination/current mode and whose click flips only:

```qml
root.draftClockFormat = root.draftClockFormat === "24h" ? "12h" : "24h"
```

Do not replay presentation or create new state.

- [ ] **Step 3: Run selector/presentation tests**

```bash
bash tests/test-quickshell-lockscreen-selector-flyout.sh
bash tests/test-quickshell-lockscreen-presentation-sequencing.sh
```

Expected: selector and clock-toggle assertions PASS; later sequencing assertions may still fail until Task 3.

- [ ] **Step 4: Commit**

```bash
git add config/quickshell/awtarchy/LockscreenCompactSelector.qml config/quickshell/awtarchy/LockscreenEditor.qml tests
git commit -m "feat(lockscreen): restore themed spawn flyouts"
```

---

### Task 3: Make custom-image spawn playback-only and add during/after-logo timing

**Files:**
- Modify: `config/quickshell/awtarchy-lock/LockScene.qml`
- Modify: `config/quickshell/awtarchy/LockPreviewScene.qml`
- Modify: `config/quickshell/awtarchy/LockscreenEditor.qml`
- Modify: `config/quickshell/awtarchy/BarState.qml`
- Modify: `config/quickshell/awtarchy-lock/shell.qml`
- Modify: `config/hypr/scripts/quickshell_application_state.sh`
- Modify: `tests/test-quickshell-lockscreen-presentation-sequencing.sh`

**Interfaces:**
- Produces custom-image field `spawn_timing: "during-logo" | "after-logo"`, default `during-logo`.
- Produces scene replay interface `individualImageReplayId` + `individualImageReplayEpoch`.

- [ ] **Step 1: Extend normalization/defaults**

For legacy/new images normalize:

```text
spawn_animation -> existing mode or none
spawn_timing -> during-logo unless exactly after-logo
```

Add `spawn_timing: "during-logo"` when creating/resetting images.

- [ ] **Step 2: Separate settled geometry from playback geometry**

Image delegates must remain at final x/y when `editorMode` and no explicit full/individual replay is active. Introduce explicit animation-active state instead of deriving visibility/offset from persisted spawn mode alone.

- [ ] **Step 3: Start during-logo images with logo entry**

`beginLogoEntry()` increments the logo epoch and starts eligible `during-logo` image delegates during the same presentation phase.

- [ ] **Step 4: Start after-logo images after logo completion**

At logo-entry completion, trigger only `after-logo` images. `none` remains settled throughout.

- [ ] **Step 5: Add targeted editor replay**

Add editor function:

```qml
function replaySelectedImageSpawn() {
    if (!selectedElement.startsWith("image:"))
        return;
    previewIndividualImageReplayId = selectedElement.slice(6);
    previewIndividualImageReplayEpoch += 1;
}
```

Pass these properties to preview scenes. Add `Play Spawn` beside selected image spawn controls.

- [ ] **Step 6: Preserve secure/preview scene parity**

Copy the final shared scene implementation exactly so:

```bash
cmp -s config/quickshell/awtarchy-lock/LockScene.qml config/quickshell/awtarchy/LockPreviewScene.qml
```

passes.

- [ ] **Step 7: Run sequencing and state tests**

```bash
bash tests/test-quickshell-lockscreen-presentation-sequencing.sh
bash tests/test-quickshell-lockscreen-element-system.sh
```

Expected: PASS for settled editor geometry, targeted replay, timing defaults, and secure/preview parity.

- [ ] **Step 8: Commit**

```bash
git add config/quickshell tests/test-quickshell-lockscreen-presentation-sequencing.sh tests/test-quickshell-lockscreen-element-system.sh
git commit -m "feat(lockscreen): separate image spawn playback from editing"
```

---

### Task 4: Generalize rotation across every presentation element

**Files:**
- Modify: `config/quickshell/awtarchy/BarState.qml`
- Modify: `config/quickshell/awtarchy/LockscreenEditor.qml`
- Modify: `config/quickshell/awtarchy-lock/LockScene.qml`
- Modify: `config/quickshell/awtarchy/LockPreviewScene.qml`
- Modify: `config/quickshell/awtarchy-lock/LockSurface.qml`
- Modify: `config/quickshell/awtarchy-lock/shell.qml`
- Modify: `config/hypr/scripts/quickshell_application_state.sh`
- Test: `tests/test-quickshell-lockscreen-rotation-reset.sh`

**Interfaces:**
- Common transform field: `rotation` integer/real degrees normalized to the existing editor rotation range.
- `elementRotation(name)` / `setElementRotation(name,value)` dispatch by built-in, visualizer, and dynamic prefixes.

- [ ] **Step 1: Add rotation defaults/normalization to built-ins and visualizer**

Default each built-in layout point and visualizer to `rotation: 0`; preserve 0 when reading legacy state.

- [ ] **Step 2: Generalize editor rotation getters/setters**

Dispatch:

```text
logo/time/date/username/weather/password -> draftLayout[name].rotation
visualizer -> draftVisualizer.rotation
image:<id> -> draftCustomImages[index].rotation
timezone:<id> -> draftTimezoneClocks[index].rotation
text:<id> -> draftCustomTexts[index].rotation
```

Keep one history/persistence path.

- [ ] **Step 3: Show rotation handle/settings for all single selections**

Remove image-only visibility predicates from rotation handle and rotation settings. Preserve preset 0/90/180/270 and exact numeric entry.

- [ ] **Step 4: Render rotation everywhere**

Apply `rotation: root.elementRotation("...")` to logo/time/date/username/weather/visualizer and dynamic elements. In `LockSurface.qml`, rotate only visible password presentation around its center; do not move/rotate the hidden secure TextInput or alter `auth.submit`.

- [ ] **Step 5: Preserve scene parity and run rotation tests**

```bash
cp config/quickshell/awtarchy-lock/LockScene.qml config/quickshell/awtarchy/LockPreviewScene.qml
bash tests/test-quickshell-lockscreen-rotation-reset.sh
bash tests/test-quickshell-lockscreen-element-system.sh
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add config/quickshell config/hypr/scripts/quickshell_application_state.sh tests
git commit -m "feat(lockscreen): make rotation a generic transform"
```

---

### Task 5: Add bounded timezone-clock elements

**Files:**
- Create: `config/hypr/scripts/quickshell_lockscreen_timezones.sh`
- Modify: `config/hypr/scripts/quickshell_lockscreen_editor_save.sh`
- Modify: `config/quickshell/awtarchy/LockscreenEditor.qml`
- Modify: `config/quickshell/awtarchy/BarState.qml`
- Modify: `config/quickshell/awtarchy-lock/shell.qml`
- Modify: `config/quickshell/awtarchy-lock/LockSurface.qml`
- Modify: `config/quickshell/awtarchy-lock/LockScene.qml`
- Modify: `config/quickshell/awtarchy/LockPreviewScene.qml`
- Modify: `.github/workflows/validate-quickshell-lockscreen-interactive-effects.yml`
- Test: `tests/test-quickshell-lockscreen-timezones-text.sh`

**Interfaces:**
- Persisted array `lockscreen_timezone_clocks`.
- Helper accepts normalized JSON and emits a bounded JSON id->display-string map; timezone names must resolve beneath `/usr/share/zoneinfo`.

- [ ] **Step 1: Implement secure local timezone helper**

The helper validates each zone against `/usr/share/zoneinfo`, refuses absolute/path-traversal/control-character values, then formats through a fixed `date` invocation using `TZ="$zone"`. No `eval`; no user-controlled command construction.

- [ ] **Step 2: Add wrapper persistence**

Extend `quickshell_lockscreen_editor_save.sh` after the established first 23 fields with timezone JSON and custom-text JSON arguments. Keep the first 19 backend arguments unchanged. Validate bounded arrays before the atomic jq replacement.

- [ ] **Step 3: Add editor timezone model/actions**

Add:

```qml
property var draftTimezoneClocks: []
function addTimezoneClock() { ... }
function removeSelectedTimezoneClock() { ... }
```

Create stable ids and defaults including rotation, visibility, x/y/scale/stretch/opacity/color and 24h format.

- [ ] **Step 4: Add editor controls**

For a selected timezone clock provide label, timezone id, 12/24 toggle, visibility, generic transform/color/rotation/reset controls, and Delete removal with undo/redo.

- [ ] **Step 5: Render timezone clocks securely and in preview**

Secure shell/editor owner refresh formatted values at minute-scale cadence, pass the bounded map to scenes, and render each clock using the common transform state.

- [ ] **Step 6: Run tests**

```bash
bash -n config/hypr/scripts/quickshell_lockscreen_timezones.sh
shellcheck config/hypr/scripts/quickshell_lockscreen_timezones.sh
bash tests/test-quickshell-lockscreen-timezones-text.sh
bash tests/test-quickshell-lockscreen-rotation-reset.sh
```

Expected: timezone normalization, persistence, safe path validation, transforms, and rendering contracts PASS.

- [ ] **Step 7: Commit**

```bash
git add config .github/workflows/validate-quickshell-lockscreen-interactive-effects.yml tests
git commit -m "feat(lockscreen): add optional timezone clocks"
```

---

### Task 6: Add arbitrary multiline/random text elements

**Files:**
- Modify: `config/hypr/scripts/quickshell_lockscreen_editor_save.sh`
- Modify: `config/quickshell/awtarchy/LockscreenEditor.qml`
- Modify: `config/quickshell/awtarchy/BarState.qml`
- Modify: `config/quickshell/awtarchy-lock/shell.qml`
- Modify: `config/quickshell/awtarchy-lock/LockSurface.qml`
- Modify: `config/quickshell/awtarchy-lock/LockScene.qml`
- Modify: `config/quickshell/awtarchy/LockPreviewScene.qml`
- Test: `tests/test-quickshell-lockscreen-timezones-text.sh`
- Test: `tests/test-quickshell-lockscreen-element-system.sh`

**Interfaces:**
- Persisted array `lockscreen_custom_texts`.
- Element ids use `text:<id>`; variants remain bounded strings with newline/tab allowed and unsafe controls rejected.

- [ ] **Step 1: Normalize/persist custom text arrays**

Require bounded object keys:

```text
id, variants, randomize, alignment, x, y, scale, stretch_x, stretch_y,
opacity, color, rotation, visible
```

Alignment is one of `left|center|right`. Empty variants normalize to one empty string or reject the element consistently.

- [ ] **Step 2: Add editor creation/deletion and history**

Add stable ids and default transform state. Delete and Reset use the existing history snapshot/atomic save path.

- [ ] **Step 3: Add multiline content editor**

Use a bounded multiline Qt input. Preserve `\n`/tabs. Shift+Enter inserts a newline/continuation and does not close or save the editor session. Provide variant management and `Randomize` toggle.

- [ ] **Step 4: Add alignment controls**

Expose direct Left/Center/Right actions that update the same persisted `alignment` property.

- [ ] **Step 5: Make random choice stable per presentation epoch**

Choose one variant when the scene presentation epoch/replay begins and retain it until the next explicit replay/session. Never call random selection from a per-frame binding.

- [ ] **Step 6: Render text with generic transforms**

Apply scale/stretch/opacity/color/rotation/visibility and alignment in both secure and preview scene paths.

- [ ] **Step 7: Run tests**

```bash
bash tests/test-quickshell-lockscreen-timezones-text.sh
bash tests/test-quickshell-lockscreen-element-system.sh
bash tests/test-quickshell-lockscreen-rotation-reset.sh
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add config tests
git commit -m "feat(lockscreen): add arbitrary text elements"
```

---

### Task 7: Align and relabel Quick Settings Cursor/Lockscreen actions

**Files:**
- Modify: `config/quickshell/awtarchy/QuickSettings.qml`
- Test: `tests/test-quickshell-lockscreen-quicksettings-header.sh`
- Test: `tests/test-quick-settings-bar-customize-flow.sh`

**Interfaces:**
- Produces matching action-column structure with ids `cursorSectionActions` and `lockscreenSectionActions`.

- [ ] **Step 1: Give both headers the same action column contract**

Use equal preferred/minimum width and right alignment for both action columns. Keep `Edit Layout` below the Lockscreen expand action.

- [ ] **Step 2: Use explicit labels**

Set:

```qml
label: root.cursorSectionOpen ? "Collapse Cursor" : "Expand Cursor"
label: root.lockscreenSectionOpen ? "Collapse Lockscreen" : "Expand Lockscreen"
```

Move the small current lockscreen animation text out of the header geometry if it prevents alignment.

- [ ] **Step 3: Run Quick Settings regressions**

```bash
bash tests/test-quickshell-lockscreen-quicksettings-header.sh
bash tests/test-quick-settings-bar-customize-flow.sh
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add config/quickshell/awtarchy/QuickSettings.qml tests
git commit -m "fix(quickshell): align cursor and lockscreen actions"
```

---

### Task 8: Managed history, full validation, and runtime-candidate bookkeeping

**Files:**
- Modify: `local/share/awtarchy/quickshell-managed-history.sha256`
- Modify if required by current stock hashes: `tests/test-quickshell-updater-migration.sh`
- Update comments only after exact-head validation: PR #181, issues #187–#190.

**Interfaces:**
- Consumes: final exact tree from Tasks 1–7.
- Produces: one exact automated-green SHA eligible for maintainer runtime testing.

- [ ] **Step 1: Enumerate managed files changed in this pass**

Compare the pre-pass green SHA against the new head and list every modified managed `.config/...` stock path.

- [ ] **Step 2: Calculate exact SHA-256 stock hashes**

Use exact repository bytes for each managed file. Append only missing `<sha256>  <managed-path>` entries; never delete historical entries.

- [ ] **Step 3: Run focused local/static contract set through CI**

At minimum require green:

```bash
bash tests/test-quickshell-lockscreen-selector-flyout.sh
bash tests/test-quickshell-lockscreen-presentation-sequencing.sh
bash tests/test-quickshell-lockscreen-rotation-reset.sh
bash tests/test-quickshell-lockscreen-element-system.sh
bash tests/test-quickshell-lockscreen-timezones-text.sh
bash tests/test-quickshell-lockscreen-quicksettings-header.sh
bash tests/test-quick-settings-bar-customize-flow.sh
```

plus workflow Bash syntax/ShellCheck and managed-history tests.

- [ ] **Step 4: Verify security invariants on final tree**

Confirm:

```text
LockAuth.qml imports Quickshell.Services.Pam and owns PamContext.
awtarchy-lock/shell.qml owns WlSessionLock with locked: true.
LockSurface.qml owns the hidden real TextInput and calls auth.submit.
Editor/preview files contain no PamContext and cannot submit passwords.
```

- [ ] **Step 5: Verify exact-head GitHub state**

Re-fetch branch, `main`, PR #181, release/tag state, secure/preview scene blob parity, and all applicable workflow runs for the exact head. No failed/cancelled/pending workflow may remain.

- [ ] **Step 6: Update PR/issues with automated evidence only**

Record the exact SHA and implemented scope in #187–#190 and PR #181. Explicitly state runtime visual/input/audio/compositor acceptance is pending maintainer testing.

- [ ] **Step 7: Hand off exact runtime candidate**

Only after every applicable workflow is green, provide:

```bash
awtarchy git update --branch feature/lockscreen-interactive-effects --commit <EXACT_GREEN_SHA>
```

and a focused runtime checklist covering fly-outs, settled image preview, individual replay, during/after-logo timing, clock toggle/timezones, all-element rotation, custom text, Quick Settings alignment, secondary-monitor preview, and immediate authentication usability.