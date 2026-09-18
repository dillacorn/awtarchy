# Lockscreen Multi-Monitor Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the lockscreen editor preview every connected display, keep Shared configuration as the backward-compatible default, support complete optional per-monitor visual profiles with copy controls, and make `Super+Alt+E` a normal/`noalt` toggle.

**Architecture:** Preserve the existing top-level `lockscreen_*` fields as the Shared profile and add `lockscreen_monitor_overrides` as complete per-output snapshots. Extend the existing byte-identical `LockscreenPresentationState.js` copies as the common profile normalizer/resolver. Keep the editor's current scalar draft properties as the live facade for the active profile, flushing them only when switching targets/saving/copying; secondary previews resolve Shared or monitor snapshots independently. The secure `WlSessionLockSurface` resolves its own profile from `screen.name`, with wallpaper, contrast, weather, timezone, visualizer, media pre-roll, and transitions owned by that surface.

**Tech Stack:** Bash + jq persistence, Quickshell/QML, QtQuick, Qt Multimedia, JavaScript helper tests under Node.js, shell regression tests, Hyprland Lua.

**Spec:** `docs/superpowers/specs/2026-09-16-lockscreen-multimonitor-editor-design.md`

## Global Constraints

- Work only on `feature/lockscreen-media-editor-polish`; do not modify `main`, releases, or tags.
- `WlSessionLock` remains the sole secure lock authority.
- `LockAuth.qml` remains the PAM/authentication owner.
- Existing top-level `lockscreen_*` state remains the Shared/default profile.
- `lockscreen_monitor_overrides` stores complete normalized snapshots keyed by output name. Missing keys mean Shared mode. Disconnected overrides are retained.
- Auto Contrast output is derived per effective profile and is not stored in monitor profile objects.
- Weather location remains global; weather units may differ by monitor.
- `lockscreen_mouse_interactive`, lock ownership/authentication, and global performance/session settings are not monitor profile fields.
- Existing still/GIF/MP4 rendering, silent looping video, bounded MP4 pre-roll, blur/pixelation, overlays, and entry transitions remain intact.
- The transition lifecycle regression reported during planning was fixed at `dbea0b9219e07341701cc2f2d1c553919ec08a6a`: `LockTransitionLayer.Component.onCompleted` no longer resets a parent-started deferred transition. Keep `tests/test-quickshell-lockscreen-media-preroll.sh` green.
- Runtime/visual/multi-monitor behavior is not verified until the maintainer tests the exact Git candidate in Hyprland.
- The temporary `.github/workflows/feature-lockscreen-editor-toggle.yml` exists only for branch development and must be deleted after permanent tests cover the completed feature.
- Do not treat the known unrelated updater/AUR migration fixture failure as a blocker unless its failure changes to a lockscreen-related assertion.

---

## File Structure

**Profile contract**
- Modify `config/quickshell/awtarchy/LockscreenPresentationState.js`
- Modify `config/quickshell/awtarchy-lock/LockscreenPresentationState.js`
- Keep these copies byte-identical.

**Persistence/state facade**
- Modify `config/hypr/scripts/quickshell_application_state.sh`
- Modify `config/hypr/scripts/quickshell_lockscreen_editor_save.sh`
- Modify `config/quickshell/awtarchy/BarState.qml`

**Editor/preview**
- Modify `config/quickshell/awtarchy/LockscreenEditor.qml`
- Modify `config/quickshell/awtarchy/LockscreenContrast.qml`
- Modify `config/hypr/scripts/quickshell_lockscreen_contrast.sh`

**Secure presentation**
- Modify `config/quickshell/awtarchy-lock/shell.qml`
- Modify `config/quickshell/awtarchy-lock/LockSurface.qml`
- Modify `config/quickshell/awtarchy-lock/LockContrastCache.qml`
- Modify `config/quickshell/awtarchy-lock/LockWeatherCache.qml`
- Reuse `LockWallpaperState.qml`, `LockAudioAnalyzer.qml`, `LockMedia.qml`, `LockScene.qml`, and `LockTransitionLayer.qml` rather than introducing an external renderer.

**Weather/timezone**
- Modify `config/hypr/scripts/quickshell_lockscreen_weather.sh`
- Modify `config/quickshell/awtarchy/LockscreenWeather.qml`
- Reuse `config/hypr/scripts/quickshell_lockscreen_timezones.sh` unchanged; run its existing `--batch` mode per preview/surface so duplicate element IDs on different monitors do not collide.

**Shortcut routing**
- Modify `config/quickshell/awtarchy/shell.qml`
- Modify `config/hypr/scripts/quickshell_lockscreen_editor.sh`
- Modify `config/hypr/hyprland.lua`

**Tests/history**
- Modify `tests/test-quickshell-lockscreen-editor-shortcuts.sh`
- Modify `tests/test-quickshell-lockscreen-media-preroll.sh` only if implementation intentionally changes its now-green lifecycle contract.
- Create `tests/test-quickshell-lockscreen-monitor-profile-resolver.mjs`
- Create `tests/test-quickshell-lockscreen-monitor-profile-state.sh`
- Create `tests/test-quickshell-lockscreen-multimonitor-editor.sh`
- Create `tests/test-quickshell-lockscreen-monitor-contrast.sh`
- Create `tests/test-quickshell-lockscreen-monitor-weather.sh`
- Create `tests/test-quickshell-lockscreen-secure-monitor-profiles.sh`
- Modify affected existing lockscreen contracts only where the old single-profile behavior is intentionally superseded.
- Modify `tests/test-quickshell-lockscreen-interactive-managed-history.sh`
- Append new managed hashes to `local/share/awtarchy/quickshell-managed-history.sha256`
- Delete `.github/workflows/feature-lockscreen-editor-toggle.yml` after final GREEN validation.

---

### Task 1: Finish the already-RED editor toggle and `noalt` shortcut

**Files:**
- Modify: `config/quickshell/awtarchy/shell.qml`
- Modify: `config/hypr/scripts/quickshell_lockscreen_editor.sh`
- Modify: `config/hypr/hyprland.lua`
- Test: `tests/test-quickshell-lockscreen-editor-shortcuts.sh`

**Interfaces:**
- Consumes `LockscreenEditor.open`, `LockscreenEditor.openFocused()`, `LockscreenEditor.close()`.
- Produces control IPC `toggleLockscreenEditor()`.
- Produces two identical `SUPER + ALT + e` binds: normal bindings and the existing `noalt` submap.

- [ ] **Step 1: Confirm RED.**

```bash
bash tests/test-quickshell-lockscreen-editor-shortcuts.sh
```

Expected: `FAIL: lockscreen editor IPC action is not a toggle` on the current branch baseline.

- [ ] **Step 2: Implement the minimal toggle.**

Use this control action in `shell.qml`:

```qml
function toggleLockscreenEditor(): void {
    if (LockscreenEditor.open)
        LockscreenEditor.close();
    else
        LockscreenEditor.openFocused();
}
```

The IPC endpoint must expose `toggleLockscreenEditor`, and `quickshell_lockscreen_editor.sh` must call:

```bash
qs -c awtarchy ipc call control toggleLockscreenEditor
```

Keep the existing global bind and add the same bind inside `noalt`:

```lua
hl.bind("SUPER + ALT + e", hl.dsp.exec_cmd(lockscreen_editor), {})
```

The open-editor toggle close path intentionally uses `LockscreenEditor.close()`, the same unsaved-draft discard path as Escape.

- [ ] **Step 3: Verify GREEN.**

```bash
bash tests/test-quickshell-lockscreen-editor-shortcuts.sh
bash tests/test-lua-validation.sh
bash -n config/hypr/scripts/quickshell_lockscreen_editor.sh
```

- [ ] **Step 4: Commit.**

```bash
git add config/quickshell/awtarchy/shell.qml config/hypr/scripts/quickshell_lockscreen_editor.sh config/hypr/hyprland.lua tests/test-quickshell-lockscreen-editor-shortcuts.sh
git commit -m "Toggle lockscreen editor shortcut"
```

---

### Task 2: Add one normalized Shared/Individual profile contract

**Files:**
- Modify: both `LockscreenPresentationState.js` copies
- Create: `tests/test-quickshell-lockscreen-monitor-profile-resolver.mjs`

**Interfaces:**
- Produces `sharedProfile(state) -> object`.
- Produces `monitorOverrides(state) -> object`.
- Produces `profileForMonitor(shared, overrides, monitorName) -> object`.
- Produces `cloneProfile(profile) -> object`.

A normalized visual profile contains exactly these persisted editor-owned keys:

```text
lockscreen_layout
lockscreen_show_logo
lockscreen_show_time
lockscreen_show_date
lockscreen_show_username
lockscreen_show_weather
lockscreen_custom_images
lockscreen_timezone_clocks
lockscreen_custom_texts
lockscreen_visualizer
lockscreen_background
lockscreen_background_color
lockscreen_wallpaper_path
lockscreen_wallpaper_fit
lockscreen_wallpaper_focal_x
lockscreen_wallpaper_focal_y
lockscreen_background_opacity
lockscreen_background_opacity_previous
lockscreen_overlay_mode
lockscreen_overlay_strength
lockscreen_wallpaper_blur
lockscreen_blur_style
lockscreen_weather_units
lockscreen_animation
lockscreen_entry_transition
lockscreen_entry_transition_duration
lockscreen_password_mask_mode
lockscreen_password_mask_character
lockscreen_clock_format
```

- [ ] **Step 1: Write the failing Node test.** Load both JS files with `vm`, stripping `.pragma library`, then assert:

```js
const shared = api.sharedProfile({
  lockscreen_background: "color",
  lockscreen_background_color: "#112233"
});
assert.equal(shared.lockscreen_background, "color");
assert.equal(shared.lockscreen_background_color, "#112233");

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

Also assert that an incomplete stored override fills missing fields from static profile defaults, not from the current Shared profile. This enforces complete-snapshot semantics.

- [ ] **Step 2: Verify RED.**

```bash
node tests/test-quickshell-lockscreen-monitor-profile-resolver.mjs
```

- [ ] **Step 3: Implement resolver functions.** Reuse existing element/custom-media/timezone/custom-text/visualizer helpers. Add only the small enum/boolean/range normalizers needed for the profile fields above. `monitorOverrides()` must normalize each stored object independently. `profileForMonitor()` returns the complete override when present, otherwise Shared. `cloneProfile()` must deep-clone nested arrays/objects.

- [ ] **Step 4: Verify GREEN and copy identity.**

```bash
node tests/test-quickshell-lockscreen-monitor-profile-resolver.mjs
cmp -s config/quickshell/awtarchy/LockscreenPresentationState.js config/quickshell/awtarchy-lock/LockscreenPresentationState.js
```

- [ ] **Step 5: Commit.**

```bash
git add config/quickshell/awtarchy/LockscreenPresentationState.js config/quickshell/awtarchy-lock/LockscreenPresentationState.js tests/test-quickshell-lockscreen-monitor-profile-resolver.mjs
git commit -m "Add lockscreen monitor profile resolver"
```

---

### Task 3: Persist Shared plus all monitor overrides atomically

**Files:**
- Modify: `config/hypr/scripts/quickshell_application_state.sh`
- Modify: `config/hypr/scripts/quickshell_lockscreen_editor_save.sh`
- Modify: `config/quickshell/awtarchy/BarState.qml`
- Create: `tests/test-quickshell-lockscreen-monitor-profile-state.sh`

**Interfaces:**
- Produces backend command `save-lockscreen-editor-profiles <shared-json> <overrides-json>`.
- Produces editor helper form `quickshell_lockscreen_editor_save.sh --profiles <shared-json> <overrides-json>`.
- Produces `BarState.lockscreenSharedProfile()`, `BarState.lockscreenMonitorOverrides()`, and `BarState.lockscreenProfileForMonitor(name)` using the shared JS resolver.
- Existing legacy save forms remain accepted for existing callers/tests.

- [ ] **Step 1: Write RED persistence tests.** Build a temp state with a complete Shared profile and `DP-1`/`HDMI-A-1` overrides. Save through:

```bash
XDG_CACHE_HOME="$TMP/cache" HOME="$TMP/home" HYPR_QUICKSHELL_SCRIPT=/bin/false \
  bash "$EDITOR_SAVE" --profiles "$shared_json" "$overrides_json"
```

Assert top-level Shared fields and both override snapshots. Then hash the state, submit one invalid override (`lockscreen_background:"invalid"`), require nonzero exit, and require the hash to remain unchanged. Also assert disconnected output names remain stored.

- [ ] **Step 2: Verify RED.**

```bash
bash tests/test-quickshell-lockscreen-monitor-profile-state.sh
```

- [ ] **Step 3: Centralize complete profile normalization in the backend.** Add `normalize_lockscreen_profile_json()` that reuses current validators. Extend the existing normalization to accept the already-supported editor extension fields directly: layout/visualizer `rotation`, custom-media `spawn_timing`. This removes the need for the new profile path to perform a second post-save rewrite.

Add `normalize_lockscreen_monitor_overrides_json()`. Monitor keys must be 1-128 Unicode code points with no control characters. Validate/normalize every override before creating the temp output file.

- [ ] **Step 4: Implement one replacement transaction.** Only after Shared and every override validate, write all Shared top-level fields plus:

```jq
.lockscreen_monitor_overrides = $overrides
```

through the existing temp-file/lock commit path. If `$overrides` is empty, store `{}` rather than deleting unrelated state.

- [ ] **Step 5: Preserve stale-local-media repair in `quickshell_lockscreen_editor_save.sh`.** Apply the current readable-local-file filtering to Shared and every override before dispatching to the strict backend. Do not partially save when a non-repairable profile field is malformed.

- [ ] **Step 6: Expose profile reads from BarState.** Import `LockscreenPresentationState.js` and implement:

```qml
function lockscreenSharedProfile() {
    const dependency = revision;
    return LockscreenPresentationState.sharedProfile(data());
}
function lockscreenMonitorOverrides() {
    const dependency = revision;
    return LockscreenPresentationState.monitorOverrides(data());
}
function lockscreenProfileForMonitor(name) {
    return LockscreenPresentationState.profileForMonitor(
        lockscreenSharedProfile(), lockscreenMonitorOverrides(), String(name || ""));
}
```

- [ ] **Step 7: Verify GREEN plus legacy state tests.**

```bash
bash tests/test-quickshell-lockscreen-monitor-profile-state.sh
bash tests/test-quickshell-lockscreen-element-system.sh
bash tests/test-quickshell-lockscreen-background-save-dispatch.sh
bash tests/test-quickshell-lockscreen-weather-units.sh
bash -n config/hypr/scripts/quickshell_application_state.sh
bash -n config/hypr/scripts/quickshell_lockscreen_editor_save.sh
```

- [ ] **Step 8: Commit.**

```bash
git add config/hypr/scripts/quickshell_application_state.sh config/hypr/scripts/quickshell_lockscreen_editor_save.sh config/quickshell/awtarchy/BarState.qml tests/test-quickshell-lockscreen-monitor-profile-state.sh
git commit -m "Persist lockscreen monitor profiles"
```

---

### Task 4: Convert the editor into a Shared/Individual draft session

**Files:**
- Modify: `config/quickshell/awtarchy/LockscreenEditor.qml`
- Create: `tests/test-quickshell-lockscreen-multimonitor-editor.sh`

**Interfaces:**
- Produces `draftSharedProfile`, `draftMonitorOverrides`, `activeMonitorName`.
- Produces `profileFromDraftScalars()`, `flushActiveProfile()`, `loadProfileIntoDraft(profile)`, `effectiveProfileForMonitor(name)`.
- Produces `useIndividualConfiguration()`, `useSharedConfiguration()`, `copyConfigurationTo(name)`, `copyConfigurationToAllOthers()`, `switchActiveMonitor(name)`.

The current scalar `draft*` properties remain the UI/manipulation facade for the active profile. Do not rewrite all element manipulation code to nested profile paths.

- [ ] **Step 1: Write RED structural/behavior contracts.** Require the new draft/profile functions, one initial persisted load per editor session, no persisted reload during monitor switching, and secondary preview resolution through `effectiveProfileForMonitor(modelData.name)`.

- [ ] **Step 2: Verify RED.**

```bash
bash tests/test-quickshell-lockscreen-multimonitor-editor.sh
```

- [ ] **Step 3: Implement scalar/profile conversion.** `profileFromDraftScalars()` must return the complete persisted profile from current scalar properties. `loadProfileIntoDraft(profile)` must set every corresponding scalar under a `profileLoadActive` guard so loading does not create undo history or trigger unintended save state.

- [ ] **Step 4: Implement active-target flushing.** Before switching monitor, saving, or copying, call `flushActiveProfile()`. If the active monitor has an override, write a deep clone into `draftMonitorOverrides[activeMonitorName]`; otherwise write to `draftSharedProfile`. Always replace the top-level map object after changing an override so QML bindings are invalidated.

- [ ] **Step 5: Implement effective preview resolution.** Use this rule:

```text
if name == activeMonitorName:
    current scalar profile
else if draftMonitorOverrides[name] exists:
    stored override snapshot
else if active monitor is Shared:
    current scalar Shared profile
else:
    stored draftSharedProfile
```

This makes Shared edits live-update every Shared preview without adding change handlers to every scalar property.

- [ ] **Step 6: Implement mode changes.** `Use Individual Configuration` clones the current effective Shared profile into an override without changing the visible scalar values. `Use Shared Configuration` deletes only the active monitor override and loads current Shared into the scalar facade.

- [ ] **Step 7: Implement copying.** Copy source = active effective scalar profile. Copying to another connected output creates/replaces that target's Individual snapshot. `All Other Displays` applies the same deep snapshot independently to every current target. Source state is never mutated.

- [ ] **Step 8: Make history target-safe.** Store undo/redo stacks by profile identity (`shared` or `monitor:<name>`). Before switching targets, stash the current stacks; after loading the target, restore that profile's stacks or empty arrays. No undo operation may apply a snapshot to a different profile.

- [ ] **Step 9: Add monitor controls.** In the editor settings bar add a monitor selector showing connected output names, a visible `Shared`/`Individual` mode indicator, the corresponding `Use Individual Configuration`/`Use Shared Configuration` action, and `Copy Configuration To…` targets. Only the active editor window remains focusable; passive preview windows get no toolbar.

- [ ] **Step 10: Handle topology changes.** Watch `Quickshell.screens`. New outputs appear using retained override or Shared. If active output disappears, flush its draft, prefer the currently focused remaining output, otherwise use first available screen. Never delete disconnected overrides.

- [ ] **Step 11: Save profiles atomically.** `Ctrl+S` flushes the active profile and calls:

```text
quickshell_lockscreen_editor_save.sh --profiles <JSON shared> <JSON overrides>
```

Success keeps the editor open; failure keeps all draft state intact and uses the existing save error/status UI. Escape/toggle close writes nothing.

- [ ] **Step 12: Verify GREEN.**

```bash
bash tests/test-quickshell-lockscreen-multimonitor-editor.sh
bash tests/test-quickshell-lockscreen-editor-shortcuts.sh
bash tests/test-quickshell-lockscreen-editor.sh
bash tests/test-quickshell-lockscreen-media-editor-polish.sh
```

- [ ] **Step 13: Commit.**

```bash
git add config/quickshell/awtarchy/LockscreenEditor.qml tests/test-quickshell-lockscreen-multimonitor-editor.sh
git commit -m "Add lockscreen monitor editing"
```

---

### Task 5: Make draft and persisted Auto Contrast monitor-aware

**Files:**
- Modify: `config/hypr/scripts/quickshell_lockscreen_contrast.sh`
- Modify: `config/quickshell/awtarchy/LockscreenContrast.qml`
- Modify: `config/quickshell/awtarchy/LockscreenEditor.qml`
- Modify: `config/quickshell/awtarchy-lock/LockContrastCache.qml`
- Create: `tests/test-quickshell-lockscreen-monitor-contrast.sh`

**Interfaces:**
- Persisted cache schema keeps top-level Shared `colors` for compatibility and adds `monitor_colors: { outputName: colors }`.
- `LockContrastCache.monitorName` selects monitor colors when present, otherwise Shared colors.
- Editor stores `draftSharedAutoAccents` plus `draftMonitorAutoAccents` and keeps current `draftAutoAccents` as the active-profile facade.

- [ ] **Step 1: Write RED tests.** Use black Shared + white `DP-1` override and assert default helper mode emits white Shared foreground colors and black `monitor_colors["DP-1"]`. Also assert GIF first-frame and MP4 single-frame sampling remain one-shot, not per-frame loops.

- [ ] **Step 2: Verify RED.**

```bash
bash tests/test-quickshell-lockscreen-monitor-contrast.sh
```

- [ ] **Step 3: Extend persisted contrast generation.** When no explicit `--stdout` draft overrides are supplied, read Shared plus `lockscreen_monitor_overrides`, call the existing deterministic sampler once per profile, and write:

```json
{
  "version": 3,
  "provider": "awtarchy-local-contrast",
  "colors": {"logo":"#ffffff"},
  "monitor_colors": {"DP-1":{"logo":"#000000"}}
}
```

Retain current background metadata fields if existing tests depend on them.

- [ ] **Step 4: Select persisted colors by secure monitor.** Add `property string monitorName` to `LockContrastCache.qml`. Parse both old v2 caches and new v3 caches. For v3 use `monitor_colors[monitorName]` when valid, otherwise Shared `colors`.

- [ ] **Step 5: Keep unsaved editor contrast per draft profile.** Before switching monitor, stash current `draftAutoAccents` into Shared or that monitor's accent map. Load the target's stored accents when switching. Debounced active-profile recomputation continues to use current `--stdout` mode. Shared active accents are used by every Shared preview; Individual accents only by that monitor. Copying a profile deep-copies its current derived accents as an immediate visual value, then allows the normal debounced refresh to verify/recompute it.

- [ ] **Step 6: Verify GREEN.**

```bash
bash tests/test-quickshell-lockscreen-monitor-contrast.sh
bash tests/test-quickshell-lockscreen-animated-contrast.sh
bash tests/test-quickshell-lockscreen-runtime-polish.sh
bash -n config/hypr/scripts/quickshell_lockscreen_contrast.sh
```

- [ ] **Step 7: Commit.**

```bash
git add config/hypr/scripts/quickshell_lockscreen_contrast.sh config/quickshell/awtarchy/LockscreenContrast.qml config/quickshell/awtarchy/LockscreenEditor.qml config/quickshell/awtarchy-lock/LockContrastCache.qml tests/test-quickshell-lockscreen-monitor-contrast.sh
git commit -m "Resolve lockscreen contrast per monitor"
```

---

### Task 6: Make weather units and timezone values profile-local

**Files:**
- Modify: `config/hypr/scripts/quickshell_lockscreen_weather.sh`
- Modify: `config/quickshell/awtarchy/LockscreenWeather.qml`
- Modify: `config/quickshell/awtarchy/LockscreenEditor.qml`
- Modify: `config/quickshell/awtarchy-lock/LockWeatherCache.qml`
- Modify: `config/quickshell/awtarchy-lock/LockSurface.qml`
- Create: `tests/test-quickshell-lockscreen-monitor-weather.sh`

**Interfaces:**
- Weather cache contains `entries` keyed by requested unit mode (`auto`, `fahrenheit`, `celsius`).
- `LockWeatherCache` consumes `enabled` and `units` and exposes `summary` for that profile.
- Timezone helper remains unchanged; each preview/surface invokes `--batch` for its own `lockscreen_timezone_clocks`.

- [ ] **Step 1: Write RED weather tests.** Stub curl/date as existing tests do. Request both Fahrenheit and Celsius modes in one refresh set and assert both cache entries survive. Assert a profile requesting `fahrenheit` does not consume the Celsius entry.

- [ ] **Step 2: Verify RED.**

```bash
bash tests/test-quickshell-lockscreen-monitor-weather.sh
```

- [ ] **Step 3: Add helper `refresh-set`.** Accept:

```text
quickshell_lockscreen_weather.sh refresh-set <global-location> <units-json-array>
```

Validate the array contains only `auto|fahrenheit|celsius`, deduplicate it, resolve location once, fetch required forecast units, and atomically write an `entries` object keyed by the requested mode. Preserve the existing `refresh` command as a compatibility wrapper around a one-element set.

- [ ] **Step 4: Make unlocked refresh request every required unit mode.** `LockscreenWeather.qml` obtains Shared + overrides through BarState. Include units from each profile with `lockscreen_show_weather == true`, deduplicate, and call `refresh-set`. Keep location global from `BarState.lockscreenWeatherLocation()`.

- [ ] **Step 5: Make secure weather cache profile-aware.** `LockWeatherCache.qml` gets `required property string units`; use exactly that requested key in `entries`. Continue validating provider, expiry, and summary length. Read the legacy one-summary cache only as fallback for an old Shared installation.

- [ ] **Step 6: Scope timezone values per editor preview and secure surface.** Each secondary editor preview owns a local `timezoneValues` object + Process invoking the unchanged helper with only its effective profile clocks. The active editor keeps its current active-profile timezone facade. `LockSurface` similarly owns a local timezone Process keyed to its resolved profile, preventing duplicate timezone element IDs on separate displays from colliding.

- [ ] **Step 7: Verify GREEN.**

```bash
bash tests/test-quickshell-lockscreen-monitor-weather.sh
bash tests/test-quickshell-lockscreen-weather.sh
bash tests/test-quickshell-lockscreen-weather-units.sh
bash tests/test-quickshell-lockscreen-timezones.sh
bash -n config/hypr/scripts/quickshell_lockscreen_weather.sh
bash -n config/hypr/scripts/quickshell_lockscreen_timezones.sh
```

- [ ] **Step 8: Commit.**

```bash
git add config/hypr/scripts/quickshell_lockscreen_weather.sh config/quickshell/awtarchy/LockscreenWeather.qml config/quickshell/awtarchy/LockscreenEditor.qml config/quickshell/awtarchy-lock/LockWeatherCache.qml config/quickshell/awtarchy-lock/LockSurface.qml tests/test-quickshell-lockscreen-monitor-weather.sh
git commit -m "Scope lockscreen weather and clocks per monitor"
```

---

### Task 7: Resolve the secure lock scene independently on every display

**Files:**
- Modify: `config/quickshell/awtarchy-lock/shell.qml`
- Modify: `config/quickshell/awtarchy-lock/LockSurface.qml`
- Create: `tests/test-quickshell-lockscreen-secure-monitor-profiles.sh`

**Interfaces:**
- Secure shell owns `lockSharedProfile` and `lockMonitorOverrides` loaded once from the state snapshot.
- `LockSurface` consumes `sharedProfile`, `monitorOverrides`, plus global auth/session settings.
- `LockSurface.profile` is `LockscreenPresentationState.profileForMonitor(sharedProfile, monitorOverrides, screen.name)`.

- [ ] **Step 1: Write RED secure contracts.** Require the secure shell to parse Shared + override maps through the JS helper, require each `LockSurface` to resolve its own `screen.name`, and reject any profile-selection logic inside `LockAuth.qml`.

- [ ] **Step 2: Verify RED.**

```bash
bash tests/test-quickshell-lockscreen-secure-monitor-profiles.sh
```

- [ ] **Step 3: Replace global visual scalar loading with profile loading.** In secure `shell.qml`, parse state into:

```qml
lockSharedProfile = LockscreenPresentationState.sharedProfile(parsed);
lockMonitorOverrides = LockscreenPresentationState.monitorOverrides(parsed);
```

Keep only genuinely global settings separately, including authentication/session state, `lockscreen_mouse_interactive`, logo physics Hz, and global weather location.

- [ ] **Step 4: Resolve in `LockSurface`.** Import the JS helper and define:

```qml
readonly property string monitorName: root.screen && root.screen.name ? String(root.screen.name) : ""
readonly property var profile: LockscreenPresentationState.profileForMonitor(
    root.sharedProfile, root.monitorOverrides, root.monitorName)
```

Bind `LockScene` visual inputs from `profile` rather than Shared root scalars.

- [ ] **Step 5: Move presentation services to surface ownership.** Each secure surface owns:
- `LockWallpaperState` using `profile.lockscreen_wallpaper_path`;
- `LockContrastCache` using `monitorName`;
- `LockWeatherCache` using profile show-weather + units;
- `LockAudioAnalyzer` using profile visualizer enabled/performance;
- local timezone values from Task 6.

This ensures different background media, GIF/MP4 playback, visualizers, weather units, and clocks can coexist. `LockAuth` remains one shared auth owner passed into every surface.

- [ ] **Step 6: Preserve transition capture and pre-roll.** Keep capture lookup by the existing output name. Keep `autoStart:false`, `videoPreRollTimeout:750`, pre-roll cover, and the race-safe `LockTransitionLayer.Component.onCompleted` from commit `dbea0b9`. Media readiness may delay only visual reveal, never lock ownership/authentication.

- [ ] **Step 7: Verify GREEN.**

```bash
bash tests/test-quickshell-lockscreen-secure-monitor-profiles.sh
bash tests/test-quickshell-lockscreen-media-preroll.sh
bash tests/test-quickshell-lockscreen-runtime-acceptance-187.sh
bash tests/test-quickshell-lockscreen-runtime-polish.sh
bash tests/test-quickshell-lockscreen-editor.sh
```

- [ ] **Step 8: Commit.**

```bash
git add config/quickshell/awtarchy-lock/shell.qml config/quickshell/awtarchy-lock/LockSurface.qml tests/test-quickshell-lockscreen-secure-monitor-profiles.sh
git commit -m "Resolve secure lockscreen per monitor"
```

---

### Task 8: Final managed-history and regression pass

**Files:**
- Modify: `tests/test-quickshell-lockscreen-interactive-managed-history.sh`
- Modify: `local/share/awtarchy/quickshell-managed-history.sha256`
- Delete: `.github/workflows/feature-lockscreen-editor-toggle.yml`
- Modify existing focused tests only for intentional new behavior.

**Interfaces:**
- Produces one exact Git-testing candidate SHA for maintainer runtime acceptance.

- [ ] **Step 1: Extend managed-history coverage.** Ensure every new/changed managed config/helper file in this feature is listed by `test-quickshell-lockscreen-interactive-managed-history.sh`.

- [ ] **Step 2: Append current SHA-256 values.** Add a dated comment and append hashes for every changed managed file. Never rewrite historical hashes. Include the corrected `LockTransitionLayer.qml` hash along with the multi-monitor files.

- [ ] **Step 3: Run the complete focused lockscreen suite.**

```bash
for test in tests/test-quickshell-lockscreen-*.sh; do
    bash "$test"
done
node tests/test-quickshell-lockscreen-efficiency.mjs
node tests/test-quickshell-lockscreen-monitor-profile-resolver.mjs
bash tests/test-lua-validation.sh
bash tests/test-quickshell-production-readiness.sh
bash -n config/hypr/scripts/quickshell_application_state.sh
bash -n config/hypr/scripts/quickshell_lockscreen_editor_save.sh
bash -n config/hypr/scripts/quickshell_lockscreen_contrast.sh
bash -n config/hypr/scripts/quickshell_lockscreen_weather.sh
bash -n config/hypr/scripts/quickshell_lockscreen_editor.sh
git diff --check
```

Expected: all lockscreen-focused tests pass. Do not broaden the gate to the known unrelated updater/AUR fixture.

- [ ] **Step 4: Delete temporary branch validation workflow and re-run permanent contracts in the normal repository validation path.**

```bash
git rm .github/workflows/feature-lockscreen-editor-toggle.yml
git add tests local/share/awtarchy/quickshell-managed-history.sha256
git commit -m "Finalize lockscreen multi-monitor editor"
```

- [ ] **Step 5: Verify the exact branch head and temporary workflow removal.** Confirm the branch SHA, confirm `.github/workflows/feature-lockscreen-editor-toggle.yml` returns 404 at that SHA, and inspect relevant Actions results.

- [ ] **Step 6: Runtime acceptance handoff.** Provide:

```bash
awtarchy git update --branch feature/lockscreen-media-editor-polish --commit <FULL_40_CHARACTER_SHA>
```

Maintainer runtime checklist:
- `Super+P`, then `L`: Pixel/Fade/Edges/Wipe entry transitions visibly animate.
- `Super+Alt+E` opens and closes the editor in normal mode and `noalt`.
- Editor appears on every connected physical display.
- Initial interactive target is focused monitor; switching target does not discard draft.
- Shared edits update every Shared preview.
- Individual mode starts visually identical, then changes only that output.
- Copy to one/all outputs creates independent snapshots.
- Return to Shared restores current Shared profile.
- `Ctrl+S` persists; Escape/toggle close discards unsaved changes.
- Different monitor layouts/backgrounds including still/GIF/MP4 survive real lock.
- Auto Contrast, weather units, timezone clocks, and visualizer follow each monitor profile.
- Video remains silent and pre-rolls before reveal.
- Unlock/PAM behavior and multi-monitor session-lock security remain unchanged.

No runtime/visual item is marked confirmed until this exact candidate passes maintainer testing.
