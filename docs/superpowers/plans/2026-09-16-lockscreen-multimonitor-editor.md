# Lockscreen Multi-Monitor Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the lockscreen editor preview every connected display, keep Shared configuration as the backward-compatible default, support complete optional per-monitor visual profiles with copy controls, and make `Super+Alt+E` a normal/`noalt` toggle.

**Architecture:** Preserve the existing top-level `lockscreen_*` fields as the Shared profile and add `lockscreen_monitor_overrides` as complete per-output snapshots. Extend the existing duplicated `LockscreenPresentationState.js` helper as the common normalization/resolution contract used by the unlocked editor and secure lock shell. Keep the current scalar editor draft properties as the active-profile facade to avoid rewriting every manipulation path; flush/load those scalars when the active monitor changes, while secondary previews resolve their own effective profile. The secure `WlSessionLockSurface` resolves its profile from its own `screen.name`, and monitor-specific presentation helpers live per surface where state can legitimately differ.

**Tech Stack:** Bash + jq state persistence, Quickshell/QML, QtQuick, Qt Multimedia, Node.js contract tests, shell regression tests, Hyprland Lua config.

**Spec:** `docs/superpowers/specs/2026-09-16-lockscreen-multimonitor-editor-design.md`

## Global Constraints

- Work only on `feature/lockscreen-media-editor-polish`; do not touch `main`, releases, or tags.
- `WlSessionLock` remains the sole secure lock authority.
- `LockAuth.qml` remains the PAM/authentication owner; do not move or weaken authentication.
- Existing top-level `lockscreen_*` state remains the Shared/default profile and must stay backward compatible.
- `lockscreen_monitor_overrides` is keyed by the existing Quickshell/Hyprland output name and stores complete normalized visual profiles, not sparse patches.
- Missing override state means Shared mode. Disconnected monitor overrides are retained.
- Auto Contrast colors are derived per effective profile and are not persisted inside monitor profile objects.
- Weather location remains global; weather display units may differ per monitor.
- Unrelated global input/performance settings such as lock ownership/authentication are not monitor profile fields.
- Existing still/GIF/MP4 rendering, silent looping video, bounded video pre-roll, blur/pixelation, overlays, and transitions must remain intact.
- Runtime/visual/multi-monitor behavior is not considered verified until the maintainer tests the exact Git candidate in Hyprland.
- `tests/test-quickshell-updater-migration.sh` has a known unrelated AUR migration fixture failure on this branch; do not use it as a blocker for this feature unless the failure changes to a lockscreen-related assertion.
- The temporary branch-only workflow `.github/workflows/feature-lockscreen-editor-toggle.yml` must be removed after permanent tests cover the feature.

---

## File Structure

**Shared profile normalization/resolution**
- Modify: `config/quickshell/awtarchy/LockscreenPresentationState.js`
- Modify: `config/quickshell/awtarchy-lock/LockscreenPresentationState.js`
- Keep the two managed copies byte-identical.

**Persistence**
- Modify: `config/hypr/scripts/quickshell_application_state.sh`
- Modify: `config/hypr/scripts/quickshell_lockscreen_editor_save.sh`

**Unlocked editor**
- Modify: `config/quickshell/awtarchy/LockscreenEditor.qml`
- Modify: `config/quickshell/awtarchy/LockscreenContrast.qml` only if needed to refresh persisted contrast after profile save.
- Modify: `config/hypr/scripts/quickshell_lockscreen_contrast.sh`

**Secure lock presentation**
- Modify: `config/quickshell/awtarchy-lock/shell.qml`
- Modify: `config/quickshell/awtarchy-lock/LockSurface.qml`
- Modify: `config/quickshell/awtarchy-lock/LockContrastCache.qml`
- Modify: `config/quickshell/awtarchy-lock/LockWeatherCache.qml`
- Reuse per-surface `LockWallpaperState.qml` and `LockAudioAnalyzer.qml`; do not create a second renderer.

**Weather/timezone support**
- Modify: `config/hypr/scripts/quickshell_lockscreen_weather.sh`
- Modify: `config/quickshell/awtarchy/LockscreenWeather.qml`
- Reuse `config/hypr/scripts/quickshell_lockscreen_timezones.sh` unchanged by moving each monitor's batch call into its owning preview/surface; duplicate timezone IDs are then naturally isolated per monitor.

**Shortcut routing**
- Modify: `config/quickshell/awtarchy/shell.qml`
- Modify: `config/hypr/scripts/quickshell_lockscreen_editor.sh`
- Modify: `config/hypr/hyprland.lua`

**Tests / managed history**
- Modify: `tests/test-quickshell-lockscreen-editor-shortcuts.sh`
- Create: `tests/test-quickshell-lockscreen-monitor-profile-resolver.mjs`
- Create: `tests/test-quickshell-lockscreen-monitor-profile-state.sh`
- Create: `tests/test-quickshell-lockscreen-multimonitor-editor.sh`
- Create: `tests/test-quickshell-lockscreen-monitor-contrast.sh`
- Create: `tests/test-quickshell-lockscreen-monitor-weather.sh`
- Create: `tests/test-quickshell-lockscreen-secure-monitor-profiles.sh`
- Modify affected existing lockscreen weather/contrast/runtime contracts only when their old single-profile assertion is intentionally superseded.
- Modify: `tests/test-quickshell-lockscreen-interactive-managed-history.sh`
- Modify: `local/share/awtarchy/quickshell-managed-history.sha256`
- Delete after GREEN: `.github/workflows/feature-lockscreen-editor-toggle.yml`

---

### Task 1: Finish the already-RED editor toggle and `noalt` shortcut

**Files:**
- Modify: `config/quickshell/awtarchy/shell.qml`
- Modify: `config/hypr/scripts/quickshell_lockscreen_editor.sh`
- Modify: `config/hypr/hyprland.lua`
- Test: `tests/test-quickshell-lockscreen-editor-shortcuts.sh`

**Interfaces:**
- Consumes: `LockscreenEditor.open`, `LockscreenEditor.openFocused()`, `LockscreenEditor.close()`.
- Produces: IPC method `toggleLockscreenEditor()` and two Hyprland `SUPER + ALT + e` bindings, one normal and one inside `noalt`.

- [ ] **Step 1: Confirm the existing regression is RED**

Run:

```bash
bash tests/test-quickshell-lockscreen-editor-shortcuts.sh
```

Expected: FAIL because production still exposes the open-only IPC/helper and/or only one Hyprland binding.

- [ ] **Step 2: Implement the minimal toggle routing**

In `shell.qml`, replace the open-only control action with:

```qml
function toggleLockscreenEditor(): void {
    if (LockscreenEditor.open)
        LockscreenEditor.close();
    else
        LockscreenEditor.openFocused();
}
```

Make the control IPC endpoint call `toggleLockscreenEditor`. In `quickshell_lockscreen_editor.sh`, call:

```bash
qs -c awtarchy ipc call control toggleLockscreenEditor
```

Keep the existing default bind and add the identical bind inside the existing `noalt` submap:

```lua
hl.bind("SUPER + ALT + e", hl.dsp.exec_cmd(lockscreen_editor), {})
```

Do not remove `Escape`; the toggle close path intentionally reuses the same cancel/discard behavior.

- [ ] **Step 3: Verify GREEN**

Run:

```bash
bash tests/test-quickshell-lockscreen-editor-shortcuts.sh
bash tests/test-lua-validation.sh
bash -n config/hypr/scripts/quickshell_lockscreen_editor.sh
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add config/quickshell/awtarchy/shell.qml \
    config/hypr/scripts/quickshell_lockscreen_editor.sh \
    config/hypr/hyprland.lua \
    tests/test-quickshell-lockscreen-editor-shortcuts.sh
git commit -m "Toggle lockscreen editor shortcut"
```

---

### Task 2: Add the pure Shared/Individual profile resolver

**Files:**
- Modify: `config/quickshell/awtarchy/LockscreenPresentationState.js`
- Modify: `config/quickshell/awtarchy-lock/LockscreenPresentationState.js`
- Create: `tests/test-quickshell-lockscreen-monitor-profile-resolver.mjs`

**Interfaces:**
- Produces: `sharedProfile(state) -> object`, `monitorOverrides(state) -> object`, `profileForMonitor(shared, overrides, monitorName) -> object`, `cloneProfile(profile) -> object`.
- Profile keys use the existing persisted names such as `lockscreen_layout`, `lockscreen_background`, `lockscreen_show_logo`, `lockscreen_custom_images`, and `lockscreen_entry_transition`.

- [ ] **Step 1: Write a Node regression that loads both JS copies and requires identical behavior**

The test loader should strip the QML library pragma before evaluating:

```js
function loadPresentationState(path) {
  const source = fs.readFileSync(path, "utf8").replace(/^\.pragma library\s*/m, "");
  const context = {};
  vm.createContext(context);
  vm.runInContext(source, context, { filename: path });
  return context;
}
```

Assert all of the following for both copies:

```js
const shared = api.sharedProfile({ lockscreen_background: "color", lockscreen_background_color: "#112233" });
assert.equal(shared.lockscreen_background, "color");
assert.equal(shared.lockscreen_show_password, undefined);

const overrides = api.monitorOverrides({
  lockscreen_monitor_overrides: {
    "DP-1": { ...shared, lockscreen_background_color: "#abcdef" }
  }
});
assert.equal(api.profileForMonitor(shared, overrides, "DP-1").lockscreen_background_color, "#abcdef");
assert.equal(api.profileForMonitor(shared, overrides, "HDMI-A-1").lockscreen_background_color, "#112233");

const cloned = api.cloneProfile(shared);
cloned.lockscreen_layout.logo.x = 0.2;
assert.notEqual(cloned.lockscreen_layout.logo.x, shared.lockscreen_layout.logo.x);
```

Also assert an older/incomplete override receives defaults for fields introduced later rather than inheriting current Shared values.

- [ ] **Step 2: Run the test to verify RED**

```bash
node tests/test-quickshell-lockscreen-monitor-profile-resolver.mjs
```

Expected: FAIL because the profile resolver functions do not exist.

- [ ] **Step 3: Implement the resolver in one JS copy, then copy it byte-for-byte to the other**

The normalized profile must include exactly these editor-owned persisted fields:

```js
{
  lockscreen_layout,
  lockscreen_show_logo,
  lockscreen_show_time,
  lockscreen_show_date,
  lockscreen_show_username,
  lockscreen_show_weather,
  lockscreen_custom_images,
  lockscreen_timezone_clocks,
  lockscreen_custom_texts,
  lockscreen_visualizer,
  lockscreen_background,
  lockscreen_background_color,
  lockscreen_wallpaper_path,
  lockscreen_wallpaper_fit,
  lockscreen_wallpaper_focal_x,
  lockscreen_wallpaper_focal_y,
  lockscreen_background_opacity,
  lockscreen_background_opacity_previous,
  lockscreen_overlay_mode,
  lockscreen_overlay_strength,
  lockscreen_wallpaper_blur,
  lockscreen_blur_style,
  lockscreen_weather_units,
  lockscreen_animation,
  lockscreen_entry_transition,
  lockscreen_entry_transition_duration,
  lockscreen_password_mask_mode,
  lockscreen_password_mask_character,
  lockscreen_clock_format
}
```

Use the existing element/custom-media/timezone/custom-text normalization helpers. Add small enum/boolean/number normalizers in this file rather than duplicating profile fallback rules in the editor and secure shell.

`monitorOverrides(state)` must normalize each object independently. It must not merge a partial override with Shared; missing fields use profile defaults so old stored overrides remain complete and deterministic.

- [ ] **Step 4: Verify GREEN and byte identity**

```bash
node tests/test-quickshell-lockscreen-monitor-profile-resolver.mjs
cmp -s config/quickshell/awtarchy/LockscreenPresentationState.js \
    config/quickshell/awtarchy-lock/LockscreenPresentationState.js
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add config/quickshell/awtarchy/LockscreenPresentationState.js \
    config/quickshell/awtarchy-lock/LockscreenPresentationState.js \
    tests/test-quickshell-lockscreen-monitor-profile-resolver.mjs
git commit -m "Add lockscreen monitor profile resolver"
```

---

### Task 3: Persist Shared plus monitor profiles atomically

**Files:**
- Modify: `config/hypr/scripts/quickshell_application_state.sh`
- Modify: `config/hypr/scripts/quickshell_lockscreen_editor_save.sh`
- Create: `tests/test-quickshell-lockscreen-monitor-profile-state.sh`

**Interfaces:**
- Produces backend command: `save-lockscreen-editor-profiles <shared-profile-json> <monitor-overrides-json>`.
- Produces editor-save mode: `quickshell_lockscreen_editor_save.sh --profiles <shared-profile-json> <monitor-overrides-json>`.
- Legacy editor-save argument forms remain accepted while this branch transitions existing tests/callers.

- [ ] **Step 1: Write atomic persistence tests**

Create a temporary state file and a complete Shared profile plus two overrides. Require:

```bash
XDG_CACHE_HOME="$TMP/cache" HOME="$TMP/home" HYPR_QUICKSHELL_SCRIPT=/bin/false \
  bash "$EDITOR_SAVE" --profiles "$shared_json" "$overrides_json"
```

Then assert:

```bash
jq -e '
  .lockscreen_background == "color"
  and .lockscreen_monitor_overrides["DP-1"].lockscreen_background == "wallpaper"
  and .lockscreen_monitor_overrides["HDMI-A-1"].lockscreen_clock_format == "12h"
' "$TMP/cache/awtarchy/quickshell-state.json"
```

For atomic failure, hash the state, submit one invalid override such as `lockscreen_background:"invalid"`, require nonzero status, then require the hash to remain unchanged.

Also test that an override for a disconnected name is retained and that optional missing wallpaper/custom-media files are repaired/filtered with the same policy used for Shared state.

- [ ] **Step 2: Run the new test to verify RED**

```bash
bash tests/test-quickshell-lockscreen-monitor-profile-state.sh
```

Expected: FAIL because the profile save mode does not exist.

- [ ] **Step 3: Add complete profile validation and one-transaction save**

In `quickshell_application_state.sh`, reuse the existing lockscreen validators to validate every Shared field and every override field before `new_tmp`. Validate monitor keys as non-empty strings up to 128 code points with no control characters.

Only after all profiles validate, write one temporary file with one jq transaction:

```jq
. as $state
| $state
| .lockscreen_layout = $shared.lockscreen_layout
| .lockscreen_show_logo = $shared.lockscreen_show_logo
| .lockscreen_show_time = $shared.lockscreen_show_time
| .lockscreen_show_date = $shared.lockscreen_show_date
| .lockscreen_show_username = $shared.lockscreen_show_username
| .lockscreen_show_weather = $shared.lockscreen_show_weather
| .lockscreen_custom_images = $shared.lockscreen_custom_images
| .lockscreen_timezone_clocks = $shared.lockscreen_timezone_clocks
| .lockscreen_custom_texts = $shared.lockscreen_custom_texts
| .lockscreen_visualizer = $shared.lockscreen_visualizer
| .lockscreen_background = $shared.lockscreen_background
| .lockscreen_background_color = $shared.lockscreen_background_color
| .lockscreen_wallpaper_path = $shared.lockscreen_wallpaper_path
| .lockscreen_wallpaper_fit = $shared.lockscreen_wallpaper_fit
| .lockscreen_wallpaper_focal_x = $shared.lockscreen_wallpaper_focal_x
| .lockscreen_wallpaper_focal_y = $shared.lockscreen_wallpaper_focal_y
| .lockscreen_background_opacity = $shared.lockscreen_background_opacity
| .lockscreen_background_opacity_previous = $shared.lockscreen_background_opacity_previous
| .lockscreen_overlay_mode = $shared.lockscreen_overlay_mode
| .lockscreen_overlay_strength = $shared.lockscreen_overlay_strength
| .lockscreen_wallpaper_blur = $shared.lockscreen_wallpaper_blur
| .lockscreen_blur_style = $shared.lockscreen_blur_style
| .lockscreen_weather_units = $shared.lockscreen_weather_units
| .lockscreen_animation = $shared.lockscreen_animation
| .lockscreen_entry_transition = $shared.lockscreen_entry_transition
| .lockscreen_entry_transition_duration = $shared.lockscreen_entry_transition_duration
| .lockscreen_password_mask_mode = $shared.lockscreen_password_mask_mode
| .lockscreen_password_mask_character = $shared.lockscreen_password_mask_character
| .lockscreen_clock_format = $shared.lockscreen_clock_format
| .lockscreen_monitor_overrides = $overrides
```

Do not persist derived Auto Contrast colors inside these objects.

- [ ] **Step 4: Make the editor-save wrapper sanitize then delegate once**

The wrapper's `--profiles` mode must validate JSON shape, apply the existing stale optional-media filtering to Shared and each override, then call exactly one backend mutation:

```bash
bash "$STATE_BACKEND" save-lockscreen-editor-profiles "$shared_profile" "$monitor_overrides"
```

Do not perform a second state-file rewrite after this call.

- [ ] **Step 5: Verify GREEN plus existing persistence contracts**

```bash
bash tests/test-quickshell-lockscreen-monitor-profile-state.sh
bash tests/test-quickshell-lockscreen-element-system.sh
bash tests/test-quickshell-lockscreen-background-save-dispatch.sh
bash tests/test-quickshell-lockscreen-weather-units.sh
bash -n config/hypr/scripts/quickshell_application_state.sh
bash -n config/hypr/scripts/quickshell_lockscreen_editor_save.sh
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add config/hypr/scripts/quickshell_application_state.sh \
    config/hypr/scripts/quickshell_lockscreen_editor_save.sh \
    tests/test-quickshell-lockscreen-monitor-profile-state.sh
git commit -m "Persist lockscreen monitor profiles"
```

---

### Task 4: Build the editor's Shared/Individual draft session and all-display controls

**Files:**
- Modify: `config/quickshell/awtarchy/LockscreenEditor.qml`
- Create: `tests/test-quickshell-lockscreen-multimonitor-editor.sh`

**Interfaces:**
- Consumes: `LockscreenPresentationState.sharedProfile`, `monitorOverrides`, `profileForMonitor`, `cloneProfile`.
- Produces editor functions: `activeProfileKey()`, `snapshotActiveProfile()`, `flushActiveProfile()`, `loadActiveProfile(profile)`, `effectiveDraftProfile(monitorName)`, `selectMonitor(name)`, `useIndividualConfiguration()`, `useSharedConfiguration()`, `copyActiveConfigurationTo(name)`, `copyActiveConfigurationToAll()`.

- [ ] **Step 1: Write structural/editor-session regressions**

Require properties/functions for:

```qml
property var sharedDraftProfile
property var draftMonitorOverrides
property string activeMonitorName
```

Require the existing `Variants { model: Quickshell.screens }` preview path to bind each secondary scene through `effectiveDraftProfile(modelData.name)` rather than directly to one global `draftLayout`/`draftWallpaperPath` mirror.

Require monitor selector text that exposes Shared/Individual mode and actions containing `Use Individual Configuration`, `Use Shared Configuration`, and `Copy Configuration To`.

Require `Ctrl+S` to serialize Shared + override drafts through the new `--profiles` save path.

- [ ] **Step 2: Run the test to verify RED**

```bash
bash tests/test-quickshell-lockscreen-multimonitor-editor.sh
```

Expected: FAIL.

- [ ] **Step 3: Keep existing scalar drafts as the active-profile facade**

Do not rewrite every existing transform/editor binding. Add session containers and conversion helpers:

```qml
property var sharedDraftProfile: ({})
property var draftMonitorOverrides: ({})
property string activeMonitorName: ""

function activeProfileKey() {
    return draftMonitorOverrides[activeMonitorName] !== undefined
        ? "monitor:" + activeMonitorName : "shared";
}

function effectiveDraftProfile(name) {
    const monitor = String(name || "");
    const key = activeProfileKey();
    if (monitor === activeMonitorName)
        return snapshotActiveProfile();
    if (draftMonitorOverrides[monitor] !== undefined)
        return LockscreenPresentationState.cloneProfile(draftMonitorOverrides[monitor]);
    if (key === "shared")
        return snapshotActiveProfile();
    return LockscreenPresentationState.cloneProfile(sharedDraftProfile);
}
```

`snapshotActiveProfile()` must build a complete profile from the existing `draftLayout`, `draftVisibility`, `draftCustomImages`, `draftTimezoneClocks`, `draftCustomTexts`, `draftVisualizer`, background/media fields, transition fields, mask fields, and clock format.

`flushActiveProfile()` writes that snapshot into `sharedDraftProfile` or `draftMonitorOverrides[activeMonitorName]` according to the current mode. `selectMonitor()` flushes first, retargets `editorWindow.screen`, then loads the selected monitor's effective profile into the scalar drafts without re-reading persisted state.

- [ ] **Step 4: Add mode switching and copy semantics**

Implement:

```qml
function useIndividualConfiguration() {
    flushActiveProfile();
    if (draftMonitorOverrides[activeMonitorName] === undefined) {
        const next = Object.assign({}, draftMonitorOverrides);
        next[activeMonitorName] = LockscreenPresentationState.cloneProfile(sharedDraftProfile);
        draftMonitorOverrides = next;
    }
    loadActiveProfile(draftMonitorOverrides[activeMonitorName]);
}

function useSharedConfiguration() {
    const next = Object.assign({}, draftMonitorOverrides);
    delete next[activeMonitorName];
    draftMonitorOverrides = next;
    loadActiveProfile(sharedDraftProfile);
}
```

`copyActiveConfigurationTo(target)` must flush first, deep-clone the source effective profile into `draftMonitorOverrides[target]`, and never mutate the source. `copyActiveConfigurationToAll()` iterates only currently connected `Quickshell.screens`, excluding the source.

- [ ] **Step 5: Add monitor UI and topology reconciliation**

Add a compact selector in the existing editor settings/header area showing the active output name and `Shared`/`Individual`. The target list comes from `Quickshell.screens` and switching calls `selectMonitor()`.

Use the fact that `Quickshell.screens` is reactive as monitors are connected/removed. Add a `Connections` handler for its property change and a `reconcileActiveMonitor()` function. If the active screen disappears, flush the current profile and choose the focused screen if available, otherwise the first connected screen. Do not delete disconnected override entries.

- [ ] **Step 6: Make undo/redo target-aware**

Add the current profile key to every history snapshot:

```qml
snapshot.profileKey = activeProfileKey();
```

Before applying a history snapshot, flush the current profile and restore the snapshot into its recorded Shared or monitor target. Never apply an old `DP-1` edit to the currently active `HDMI-A-1` profile.

- [ ] **Step 7: Route save/cancel correctly**

Before save, call `flushActiveProfile()` and serialize:

```qml
JSON.stringify(sharedDraftProfile)
JSON.stringify(draftMonitorOverrides)
```

through:

```text
quickshell_lockscreen_editor_save.sh --profiles <shared> <overrides>
```

On successful save, keep the editor open and make the saved Shared/override objects the new session baseline. `close()`/Escape/toggle must continue to discard the entire unsaved session without persistence.

- [ ] **Step 8: Verify GREEN plus existing editor contracts**

```bash
bash tests/test-quickshell-lockscreen-multimonitor-editor.sh
bash tests/test-quickshell-lockscreen-editor-shortcuts.sh
bash tests/test-quickshell-lockscreen-media-editor-polish.sh
bash tests/test-quickshell-lockscreen-runtime-polish.sh
```

Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add config/quickshell/awtarchy/LockscreenEditor.qml \
    tests/test-quickshell-lockscreen-multimonitor-editor.sh
git commit -m "Add multi-monitor lockscreen editing"
```

---

### Task 5: Make Auto Contrast resolve per effective monitor profile

**Files:**
- Modify: `config/hypr/scripts/quickshell_lockscreen_contrast.sh`
- Modify: `config/quickshell/awtarchy/LockscreenEditor.qml`
- Modify: `config/quickshell/awtarchy/LockscreenContrast.qml` if this singleton owns persisted refresh triggering on the current branch.
- Modify: `config/quickshell/awtarchy-lock/LockContrastCache.qml`
- Create: `tests/test-quickshell-lockscreen-monitor-contrast.sh`

**Interfaces:**
- Produce contrast helper option `--profile-json <json>` for one complete profile with `--stdout`.
- Persist contrast cache version 3 with `shared` colors plus `monitors` colors keyed by output name.
- Produce `LockContrastCache.monitorName` and `LockContrastCache.colors` resolving that monitor's cached colors with Shared fallback.

- [ ] **Step 1: Write RED tests for independent background/layout contrast**

Use two profiles with opposite background luminance and assert:

```bash
bash "$CONTRAST" --stdout --profile-json "$dark_profile"
bash "$CONTRAST" --stdout --profile-json "$light_profile"
```

return white vs black element colors as appropriate. Include GIF/MP4 fixtures or command stubs that prove only one deterministic representative frame is sampled per profile.

Also require persisted cache shape:

```json
{
  "version": 3,
  "provider": "awtarchy-local-contrast",
  "shared": { "colors": {} },
  "monitors": { "DP-1": { "colors": {} } }
}
```

- [ ] **Step 2: Run RED**

```bash
bash tests/test-quickshell-lockscreen-monitor-contrast.sh
```

Expected: FAIL.

- [ ] **Step 3: Add profile input and monitor-aware cache generation**

`--profile-json` must use only:

```text
lockscreen_background
lockscreen_background_color
lockscreen_wallpaper_path
lockscreen_layout
```

and reuse the existing deterministic first-frame GIF/MP4 sampler.

When refreshing persisted cache from saved state, calculate Shared once and each stored monitor override once. Do not run per-frame sampling and do not store colors inside `lockscreen_monitor_overrides`.

- [ ] **Step 4: Make editor previews maintain contrast by profile key**

Replace the single draft result with a map keyed by `shared` or `monitor:<name>`. Queue/debounce refresh only for a profile whose background/media/layout changed. Secondary previews read their effective profile's cached draft colors; unrelated monitor edits must not thrash every animated frame.

- [ ] **Step 5: Make secure cache choose monitor colors**

`LockContrastCache.qml` gets:

```qml
required property string monitorName
```

and selects `parsed.monitors[monitorName].colors` when present, otherwise `parsed.shared.colors`, retaining safe white fallbacks for malformed/old caches.

- [ ] **Step 6: Verify GREEN**

```bash
bash tests/test-quickshell-lockscreen-monitor-contrast.sh
bash tests/test-quickshell-lockscreen-animated-contrast.sh
bash tests/test-quickshell-lockscreen-runtime-polish.sh
bash -n config/hypr/scripts/quickshell_lockscreen_contrast.sh
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add config/hypr/scripts/quickshell_lockscreen_contrast.sh \
    config/quickshell/awtarchy/LockscreenEditor.qml \
    config/quickshell/awtarchy/LockscreenContrast.qml \
    config/quickshell/awtarchy-lock/LockContrastCache.qml \
    tests/test-quickshell-lockscreen-monitor-contrast.sh
git commit -m "Resolve lockscreen contrast per monitor"
```

If `LockscreenContrast.qml` requires no source change after inspection, omit it from `git add`; do not create a cosmetic diff.

---

### Task 6: Make timezone clocks monitor-local without changing the helper protocol

**Files:**
- Modify: `config/quickshell/awtarchy/LockscreenEditor.qml`
- Modify: `config/quickshell/awtarchy-lock/LockSurface.qml`
- Modify: `config/quickshell/awtarchy-lock/shell.qml`
- Test: `tests/test-quickshell-lockscreen-multimonitor-editor.sh`
- Test: `tests/test-quickshell-lockscreen-secure-monitor-profiles.sh`

**Interfaces:**
- Reuse existing `quickshell_lockscreen_timezones.sh --batch <id> <zone> <format>...` unchanged.
- Each preview/surface owns its own returned `{clockId: text}` map, so the same `timezone-1` ID may mean different zones on different monitors without collision.

- [ ] **Step 1: Extend regressions to reject one global timezone-value map for all monitors**

Require secondary previews and secure `LockSurface` to create/own timezone values from their own effective profile clocks rather than root-global `draftTimezoneClocks` / `lockTimezoneClocks`.

- [ ] **Step 2: Verify RED**

```bash
bash tests/test-quickshell-lockscreen-multimonitor-editor.sh
bash tests/test-quickshell-lockscreen-secure-monitor-profiles.sh
```

Expected: FAIL on monitor-local timezone ownership.

- [ ] **Step 3: Give each editor preview its own batch values**

The active editor can retain its existing process for the active scalar profile. Each secondary preview window gets a small process/timer scoped to `effectiveDraftProfile(modelData.name).lockscreen_timezone_clocks` and passes only its own result map to `LockPreviewScene.timezoneValues`.

Do not namespace or mutate persisted clock IDs.

- [ ] **Step 4: Move secure timezone refresh into each `LockSurface`**

Import `Quickshell`/`Quickshell.Io` in `LockSurface.qml`, derive the helper path from `XDG_CONFIG_HOME`, and build batch arguments from `profile.lockscreen_timezone_clocks`. Store results in a local `timezoneValues` property and pass that to `LockScene`.

Delete the obsolete root-global timezone process/value map from `awtarchy-lock/shell.qml` after the surface-local path is GREEN.

- [ ] **Step 5: Verify GREEN**

```bash
bash tests/test-quickshell-lockscreen-multimonitor-editor.sh
bash tests/test-quickshell-lockscreen-secure-monitor-profiles.sh
bash tests/test-quickshell-lockscreen-runtime-services.sh
bash -n config/hypr/scripts/quickshell_lockscreen_timezones.sh
```

Expected: PASS with the helper unchanged.

- [ ] **Step 6: Commit**

```bash
git add config/quickshell/awtarchy/LockscreenEditor.qml \
    config/quickshell/awtarchy-lock/LockSurface.qml \
    config/quickshell/awtarchy-lock/shell.qml \
    tests/test-quickshell-lockscreen-multimonitor-editor.sh \
    tests/test-quickshell-lockscreen-secure-monitor-profiles.sh
git commit -m "Scope lockscreen clocks per monitor"
```

---

### Task 7: Make weather cache unit-neutral so monitors can choose units independently

**Files:**
- Modify: `config/hypr/scripts/quickshell_lockscreen_weather.sh`
- Modify: `config/quickshell/awtarchy/LockscreenWeather.qml`
- Modify: `config/quickshell/awtarchy-lock/LockWeatherCache.qml`
- Modify: `config/quickshell/awtarchy-lock/LockSurface.qml`
- Create: `tests/test-quickshell-lockscreen-monitor-weather.sh`
- Modify: `tests/test-quickshell-lockscreen-weather.sh`
- Modify: `tests/test-quickshell-lockscreen-weather-units.sh`

**Interfaces:**
- Weather location remains one global saved location.
- Cache stores canonical current weather plus both formatted Celsius/Fahrenheit summaries.
- `LockWeatherCache` consumes `units: "auto"|"fahrenheit"|"celsius"` and returns the appropriate summary locally.

- [ ] **Step 1: Write RED weather tests**

Stub Open-Meteo with one Celsius response and require cache output containing both summaries, e.g.:

```json
{
  "provider": "open-meteo",
  "temperature_c": 20,
  "weather_code": 0,
  "summaries": {
    "celsius": "20°C · Clear",
    "fahrenheit": "68°F · Clear"
  }
}
```

Require `LockWeatherCache` to resolve `auto` using `LC_ALL`, `LC_MEASUREMENT`, or `LANG` with the same US/non-US rule currently used by the helper.

Require unlocked refresh to run when Shared shows weather **or any stored monitor override shows weather**, even if Shared hides it.

- [ ] **Step 2: Run RED**

```bash
bash tests/test-quickshell-lockscreen-monitor-weather.sh
bash tests/test-quickshell-lockscreen-weather.sh
bash tests/test-quickshell-lockscreen-weather-units.sh
```

Expected: FAIL on dual-summary/per-monitor behavior.

- [ ] **Step 3: Change refresh cache to canonical Celsius plus both summaries**

Request Open-Meteo current temperature in Celsius once. Compute Fahrenheit locally:

```bash
fahrenheit="$(awk -v c="$temperature_c" 'BEGIN { printf "%.0f", (c * 9 / 5) + 32 }')"
```

Preserve expiration/provider validation. Keep legacy top-level `summary`/`units` fields if needed for one transition release, but secure code must prefer the new `summaries` map.

- [ ] **Step 4: Make unlocked refresh independent of one monitor's units**

`LockscreenWeather.qml` should refresh based on location plus whether any effective saved profile needs weather. A unit change alone no longer needs another network request because both summaries are already cached.

- [ ] **Step 5: Resolve units inside each secure surface**

Add `property string units` to `LockWeatherCache.qml`, choose the correct cached summary, and instantiate/use it from `LockSurface` according to `profile.lockscreen_weather_units` and `profile.lockscreen_show_weather`.

- [ ] **Step 6: Verify GREEN**

```bash
bash tests/test-quickshell-lockscreen-monitor-weather.sh
bash tests/test-quickshell-lockscreen-weather.sh
bash tests/test-quickshell-lockscreen-weather-units.sh
bash tests/test-quickshell-lockscreen-runtime-services.sh
bash -n config/hypr/scripts/quickshell_lockscreen_weather.sh
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add config/hypr/scripts/quickshell_lockscreen_weather.sh \
    config/quickshell/awtarchy/LockscreenWeather.qml \
    config/quickshell/awtarchy-lock/LockWeatherCache.qml \
    config/quickshell/awtarchy-lock/LockSurface.qml \
    tests/test-quickshell-lockscreen-monitor-weather.sh \
    tests/test-quickshell-lockscreen-weather.sh \
    tests/test-quickshell-lockscreen-weather-units.sh
git commit -m "Support per-monitor lockscreen weather units"
```

---

### Task 8: Resolve complete profiles per secure lock surface

**Files:**
- Modify: `config/quickshell/awtarchy-lock/shell.qml`
- Modify: `config/quickshell/awtarchy-lock/LockSurface.qml`
- Modify: `config/quickshell/awtarchy-lock/LockContrastCache.qml`
- Modify: `config/quickshell/awtarchy-lock/LockWeatherCache.qml`
- Create/complete: `tests/test-quickshell-lockscreen-secure-monitor-profiles.sh`

**Interfaces:**
- `shell.qml` owns `lockSharedProfile` and `lockMonitorOverrides` loaded once from saved state.
- Each `LockSurface` receives one required `profile` selected by its inherited `screen.name`.
- Per-surface services: wallpaper source, animated media pre-roll, contrast cache selection, timezone clock values, weather unit selection, and visualizer analyzer.

- [ ] **Step 1: Write the secure-surface RED contract**

Require `shell.qml` to load:

```qml
lockSharedProfile = LockscreenPresentationState.sharedProfile(parsed)
lockMonitorOverrides = LockscreenPresentationState.monitorOverrides(parsed)
```

and require each lock surface to select by its own inherited `screen.name`, not by focused monitor or one root-global presentation object.

The test must reject changes to `LockAuth.qml` and require `WlSessionLock { locked: true }` to remain the lock authority.

- [ ] **Step 2: Run RED**

```bash
bash tests/test-quickshell-lockscreen-secure-monitor-profiles.sh
```

Expected: FAIL.

- [ ] **Step 3: Replace root-global visual fields with Shared/override state**

In secure `shell.qml`, retain only truly global state such as `unlockRequested`, capture directory, shared auth/theme objects, and non-profile global settings. Load the saved JSON into:

```qml
property var lockSharedProfile: LockscreenPresentationState.sharedProfile(({}))
property var lockMonitorOverrides: ({})

function profileForMonitor(name) {
    return LockscreenPresentationState.profileForMonitor(
        lockSharedProfile, lockMonitorOverrides, String(name || ""));
}
```

On parse failure, reset to the normalized default Shared profile and empty overrides.

- [ ] **Step 4: Pass a complete profile into each `LockSurface`**

Inside the `WlSessionLock.surface` component, bind:

```qml
LockSurface {
    auth: lockAuth
    theme: lockTheme
    profile: root.profileForMonitor(screen && screen.name ? screen.name : "")
    unlocking: root.unlockRequested
    captureDirectory: root.captureDirectory
}
```

Keep global settings such as random formation seed or mouse-interaction policy global if they are not part of the approved profile schema.

- [ ] **Step 5: Make the surface own all monitor-varying presentation helpers**

Inside `LockSurface.qml`:

- instantiate `LockWallpaperState` with `profile.lockscreen_wallpaper_path`;
- instantiate `LockContrastCache` with `monitorName: captureOutputName`;
- instantiate `LockWeatherCache` with `enabled: profile.lockscreen_show_weather` and `units: profile.lockscreen_weather_units`;
- instantiate `LockAudioAnalyzer` using `profile.lockscreen_visualizer.enabled/performance`;
- own timezone process/value state from Task 6;
- bind `LockScene` and `LockPreviewTransitionLayer` fields from `profile`.

Do not move media out of the secure surface. The existing `LockMedia` renderer and 750 ms bounded video pre-roll remain unchanged in principle and now operate per surface automatically.

- [ ] **Step 6: Verify full secure behavior contracts**

```bash
bash tests/test-quickshell-lockscreen-secure-monitor-profiles.sh
bash tests/test-quickshell-lockscreen-media-preroll.sh
bash tests/test-quickshell-lockscreen-media-editor-polish.sh
bash tests/test-quickshell-lockscreen-runtime-acceptance-187.sh
bash tests/test-quickshell-lockscreen-runtime-services.sh
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add config/quickshell/awtarchy-lock/shell.qml \
    config/quickshell/awtarchy-lock/LockSurface.qml \
    config/quickshell/awtarchy-lock/LockContrastCache.qml \
    config/quickshell/awtarchy-lock/LockWeatherCache.qml \
    tests/test-quickshell-lockscreen-secure-monitor-profiles.sh
git commit -m "Resolve secure lockscreen profiles per monitor"
```

---

### Task 9: Managed-history integration, cleanup, and complete static validation

**Files:**
- Modify: `tests/test-quickshell-lockscreen-interactive-managed-history.sh`
- Modify: `local/share/awtarchy/quickshell-managed-history.sha256`
- Delete: `.github/workflows/feature-lockscreen-editor-toggle.yml`
- Modify existing tests only for intentional new monitor-aware behavior.

**Interfaces:**
- Produces final branch candidate with no temporary branch-only validation workflow.
- Preserves updater recognition for every changed managed file.

- [ ] **Step 1: Add changed managed files to the permanent managed-history contract**

At minimum inspect/update hashes for:

```text
.config/hypr/hyprland.lua
.config/hypr/scripts/quickshell_application_state.sh
.config/hypr/scripts/quickshell_lockscreen_editor.sh
.config/hypr/scripts/quickshell_lockscreen_editor_save.sh
.config/hypr/scripts/quickshell_lockscreen_contrast.sh
.config/hypr/scripts/quickshell_lockscreen_weather.sh
.config/quickshell/awtarchy/shell.qml
.config/quickshell/awtarchy/LockscreenEditor.qml
.config/quickshell/awtarchy/LockscreenPresentationState.js
.config/quickshell/awtarchy/LockscreenWeather.qml
.config/quickshell/awtarchy-lock/shell.qml
.config/quickshell/awtarchy-lock/LockSurface.qml
.config/quickshell/awtarchy-lock/LockscreenPresentationState.js
.config/quickshell/awtarchy-lock/LockContrastCache.qml
.config/quickshell/awtarchy-lock/LockWeatherCache.qml
```

Append known managed hashes; do not rewrite historical entries.

- [ ] **Step 2: Run every focused new contract**

```bash
bash tests/test-quickshell-lockscreen-editor-shortcuts.sh
node tests/test-quickshell-lockscreen-monitor-profile-resolver.mjs
bash tests/test-quickshell-lockscreen-monitor-profile-state.sh
bash tests/test-quickshell-lockscreen-multimonitor-editor.sh
bash tests/test-quickshell-lockscreen-monitor-contrast.sh
bash tests/test-quickshell-lockscreen-monitor-weather.sh
bash tests/test-quickshell-lockscreen-secure-monitor-profiles.sh
bash tests/test-quickshell-lockscreen-interactive-managed-history.sh
```

Expected: PASS.

- [ ] **Step 3: Run the complete lockscreen regression set**

```bash
for test in tests/test-quickshell-lockscreen-*.sh; do
    bash "$test"
done
node tests/test-quickshell-lockscreen-efficiency.mjs
bash tests/test-lua-validation.sh
bash tests/test-quickshell-production-readiness.sh
bash -n config/hypr/scripts/quickshell_application_state.sh
bash -n config/hypr/scripts/quickshell_lockscreen_editor.sh
bash -n config/hypr/scripts/quickshell_lockscreen_editor_save.sh
bash -n config/hypr/scripts/quickshell_lockscreen_contrast.sh
bash -n config/hypr/scripts/quickshell_lockscreen_weather.sh
git diff --check
```

Expected: PASS. If an unrelated generic workflow or the already-known updater migration fixture fails, inspect the failure and do not misclassify it as a lockscreen regression.

- [ ] **Step 4: Delete temporary toggle-only CI tooling**

```bash
git rm .github/workflows/feature-lockscreen-editor-toggle.yml
```

Permanent tests above are the feature contract; do not leave a branch-only helper workflow behind.

- [ ] **Step 5: Re-run focused tests after cleanup**

```bash
bash tests/test-quickshell-lockscreen-editor-shortcuts.sh
node tests/test-quickshell-lockscreen-monitor-profile-resolver.mjs
bash tests/test-quickshell-lockscreen-monitor-profile-state.sh
bash tests/test-quickshell-lockscreen-multimonitor-editor.sh
bash tests/test-quickshell-lockscreen-monitor-contrast.sh
bash tests/test-quickshell-lockscreen-monitor-weather.sh
bash tests/test-quickshell-lockscreen-secure-monitor-profiles.sh
git diff --check
```

Expected: PASS.

- [ ] **Step 6: Commit final integration**

```bash
git add tests local/share/awtarchy/quickshell-managed-history.sha256
git add -u .github/workflows/feature-lockscreen-editor-toggle.yml
git commit -m "Finalize lockscreen monitor profiles"
```

---

## Runtime Acceptance Handoff

After all static validation is GREEN, record the exact 40-character branch head and give the maintainer one exact Git-testing command:

```bash
awtarchy git update --branch feature/lockscreen-media-editor-polish --commit <EXACT_FINAL_SHA>
```

The maintainer runtime test must verify:

1. `Super+Alt+E` opens the editor in normal mode and `noalt`; pressing it again cancels/closes the editor.
2. Every physical monitor shows its real effective lockscreen preview while editing.
3. The focused display is initially active; switching the editor target preserves unsaved work.
4. Shared edits immediately update every Shared monitor preview.
5. `Use Individual Configuration` produces no immediate visual change, then isolates later edits to that monitor.
6. `Use Shared Configuration` removes only that monitor override and immediately returns it to Shared.
7. `Copy Configuration To…` and `All Other Displays` create exact independent target snapshots.
8. A portrait/ultrawide/other differently sized monitor can keep an independent layout.
9. Different monitors can use different still/GIF/MP4 backgrounds; MP4 remains silent, looping, and pre-rolled before reveal.
10. Auto Contrast is sensible and stable on each monitor, including animated media.
11. Different timezone clocks and weather unit choices display independently per monitor.
12. `Ctrl+S` saves the entire Shared + override session and keeps the editor open; `Escape` discards unsaved changes.
13. Locking after save matches the editor preview on every monitor.
14. PAM authentication/unlock behavior and multi-monitor session-lock security remain unchanged.
