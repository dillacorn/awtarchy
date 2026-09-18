# Lockscreen Per-Display Profiles and Password Feedback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Shared/Individual lockscreen profiles with complete per-display profiles, enforce visible-element opacity >=5%, add explicit element selection, and add secure password spark/mini-flash/hidden feedback plus red authentication-failure edge lighting.

**Architecture:** The existing complete visual profile schema remains the unit of persistence, but active runtime/editor resolution moves to `lockscreen_monitor_profiles[output]` plus `lockscreen_last_edited_profile`. The editor edits one monitor profile at a time and copies profiles explicitly; saved presets remain global complete-profile snapshots. Secure surfaces resolve their own monitor profile and render password effects locally while the existing shared `LockAuth.qml` continues to own PAM.

**Tech Stack:** Quickshell 0.3.x QML, JavaScript resolver libraries, Bash, jq, Node.js contract tests, GitHub Actions validation.

**Spec:** `docs/superpowers/specs/2026-09-17-lockscreen-per-display-profiles-password-feedback-design.md`

## Global Constraints

- `WlSessionLock` remains the sole secure lock authority.
- `LockAuth.qml` remains the sole PAM/authentication owner.
- Runtime/editor profile resolution uses complete per-display profiles keyed by exact output name.
- Reconnecting the same output name restores its last profile; a never-seen output starts from `lockscreen_last_edited_profile`.
- Shared/Individual mode does not exist after migration.
- Copying between displays is explicit; continuous manipulation never propagates to another display.
- Global named saved configurations remain reusable on any connected display.
- Visible editable element opacity is 5–100%; visibility/enable state is the only zero-visibility mechanism.
- Background opacity remains 0–100%.
- Password effects never receive or persist password contents.
- Runtime/visual/performance behavior is not considered confirmed until Hyprland testing.
- Do not merge, release, modify `main`, or delete the feature branch during this plan.

---

### Task 1: Per-display resolver and atomic persistence

**Files:**
- Modify: `config/quickshell/awtarchy/LockscreenPresentationState.js`
- Modify: `config/quickshell/awtarchy-lock/LockscreenPresentationState.js`
- Modify: `config/quickshell/awtarchy/BarState.qml`
- Modify: `config/quickshell/awtarchy-lock/shell.qml`
- Modify: `config/hypr/scripts/quickshell_application_state.sh`
- Modify: `config/hypr/scripts/quickshell_lockscreen_editor_save.sh`
- Replace/migrate tests: `tests/test-quickshell-lockscreen-monitor-profile-resolver.mjs`, `tests/test-quickshell-lockscreen-monitor-profile-state.sh`, `tests/test-quickshell-lockscreen-secure-monitor-profiles.sh`
- Keep: `tests/test-quickshell-lockscreen-profile-save-parity.sh`

**Interfaces:**
- Produces JS:
  - `monitorProfiles(state) -> object<string, CompleteProfile>`
  - `lastEditedProfile(state) -> CompleteProfile`
  - `profileForMonitor(monitorProfiles, lastEditedProfile, name) -> CompleteProfile`
  - `migratedMonitorProfiles(state) -> object<string, CompleteProfile>`
- Produces BarState:
  - `lockscreenMonitorProfiles()`
  - `lockscreenLastEditedProfile()`
  - `lockscreenProfileForMonitor(name)`
- Produces backend command:
  - `save-lockscreen-editor-profiles <monitor-profiles-json> <last-edited-profile-json> [saved-profiles-json]`
- Secure shell passes `monitorProfiles` and `lastEditedProfile` into every `LockSurface`.

- [ ] **Step 1: Write resolver migration RED**

Update `tests/test-quickshell-lockscreen-monitor-profile-resolver.mjs` so legacy state:

```js
const legacy = {
  ...sharedFields,
  lockscreen_monitor_overrides: {
    "DP-1": individualProfile
  }
};
```

must satisfy:

```js
const profiles = context.migratedMonitorProfiles(legacy);
assert.deepEqual(profiles["DP-1"], context.cloneProfile(individualProfile));
assert.deepEqual(
  context.profileForMonitor(profiles, context.lastEditedProfile(legacy), "HDMI-A-1"),
  context.lastEditedProfile(legacy)
);
```

and new state with `lockscreen_monitor_profiles` must ignore legacy overrides as an active resolver source.

- [ ] **Step 2: Run resolver test and verify RED**

Run:

```bash
node tests/test-quickshell-lockscreen-monitor-profile-resolver.mjs
```

Expected: FAIL because `migratedMonitorProfiles` / new `profileForMonitor` contract does not exist.

- [ ] **Step 3: Implement resolver migration identically in both JS copies**

Keep current normalization helpers. Add complete-profile map normalization:

```js
function monitorProfiles(state) {
    const raw = state && typeof state.lockscreen_monitor_profiles === "object"
        && !Array.isArray(state.lockscreen_monitor_profiles)
        ? state.lockscreen_monitor_profiles : {};
    const result = {};
    for (const name of Object.keys(raw)) {
        if (/^[A-Za-z0-9._-]+$/.test(name))
            result[name] = cloneProfile(raw[name]);
    }
    return result;
}

function lastEditedProfile(state) {
    if (state && state.lockscreen_last_edited_profile
            && typeof state.lockscreen_last_edited_profile === "object"
            && !Array.isArray(state.lockscreen_last_edited_profile))
        return cloneProfile(state.lockscreen_last_edited_profile);
    return sharedProfile(state || {});
}

function migratedMonitorProfiles(state) {
    const current = monitorProfiles(state);
    if (Object.keys(current).length > 0
            || (state && Object.prototype.hasOwnProperty.call(state, "lockscreen_monitor_profiles")))
        return current;
    const result = {};
    const legacy = monitorOverrides(state || {});
    for (const name of Object.keys(legacy))
        result[name] = cloneProfile(legacy[name]);
    return result;
}

function profileForMonitor(profiles, fallback, name) {
    const key = String(name || "");
    if (profiles && profiles[key])
        return cloneProfile(profiles[key]);
    return cloneProfile(fallback);
}
```

- [ ] **Step 4: Run resolver and parity tests GREEN**

Run:

```bash
node tests/test-quickshell-lockscreen-monitor-profile-resolver.mjs
bash tests/test-quickshell-lockscreen-profile-save-parity.sh
```

Expected: PASS.

- [ ] **Step 5: Write persistence RED**

Rewrite `tests/test-quickshell-lockscreen-monitor-profile-state.sh` to invoke:

```bash
quickshell_lockscreen_editor_save.sh --profiles   "$monitor_profiles" "$last_edited_profile" "$saved_profiles"
```

Assert atomically:

```jq
.lockscreen_monitor_profiles["DP-1"].lockscreen_background == "black"
and .lockscreen_last_edited_profile.lockscreen_background_color == "#112233"
and (.lockscreen_monitor_overrides | not)
and .lockscreen_background_color == "#112233"
and .lockscreen_saved_profiles[0].name == "Work"
```

Also hash the state file before an invalid profile save and assert the hash is unchanged afterward.

- [ ] **Step 6: Run persistence RED**

Run:

```bash
bash tests/test-quickshell-lockscreen-monitor-profile-state.sh
```

Expected: FAIL because the save wrapper/backend still accepts Shared+overrides.

- [ ] **Step 7: Implement one atomic per-display save transaction**

In `quickshell_application_state.sh` add validation for:
- monitor-profile object keys matching `^[A-Za-z0-9._-]+$`;
- every map value through the existing strict complete-profile normalizer;
- one complete `lockscreen_last_edited_profile`;
- existing saved-profile library.

On success, one locked temp-file transaction must:
- write `.lockscreen_monitor_profiles`;
- write `.lockscreen_last_edited_profile`;
- write `.lockscreen_saved_profiles` when supplied;
- mirror last-edited complete-profile fields to top-level `lockscreen_*`;
- `del(.lockscreen_monitor_overrides)`.

Update `quickshell_lockscreen_editor_save.sh` `--profiles` usage to:

```text
--profiles <monitor-profiles-json> <last-edited-profile-json> [saved-profiles-json]
```

and repair optional resources in every monitor profile, last-edited profile, and saved preset before calling the strict backend.

- [ ] **Step 8: Update BarState and secure shell contracts**

BarState:

```qml
function lockscreenMonitorProfiles() {
    const dependency = revision;
    return LockscreenPresentationState.migratedMonitorProfiles(data());
}

function lockscreenLastEditedProfile() {
    const dependency = revision;
    return LockscreenPresentationState.lastEditedProfile(data());
}

function lockscreenProfileForMonitor(name) {
    return LockscreenPresentationState.profileForMonitor(
        lockscreenMonitorProfiles(),
        lockscreenLastEditedProfile(),
        String(name || ""));
}
```

Secure shell loads the same two values from its state snapshot, computes max transition duration across monitor profiles plus last-edited fallback, and passes them to `LockSurface`.

- [ ] **Step 9: Update secure profile test and run Task 1 GREEN**

Run:

```bash
bash tests/test-quickshell-lockscreen-monitor-profile-state.sh
bash tests/test-quickshell-lockscreen-secure-monitor-profiles.sh
bash tests/test-quickshell-lockscreen-profile-save-parity.sh
node tests/test-quickshell-lockscreen-monitor-profile-resolver.mjs
bash -n config/hypr/scripts/quickshell_application_state.sh
bash -n config/hypr/scripts/quickshell_lockscreen_editor_save.sh
```

Expected: PASS.

- [ ] **Step 10: Commit Task 1**

Commit message:

```text
Replace shared lockscreen profiles with per-display state
```

---

### Task 2: Per-display editor session and explicit copying

**Files:**
- Modify: `config/quickshell/awtarchy/LockscreenEditor.qml`
- Rewrite: `tests/test-quickshell-lockscreen-multimonitor-editor.sh`
- Delete/retire: `tests/test-quickshell-lockscreen-profile-mode-switch.sh`
- Delete/retire: `tests/test-quickshell-lockscreen-shared-preview-settle.sh`
- Modify: `tests/test-quickshell-lockscreen-saved-profiles.sh`

**Interfaces:**
- Consumes Task 1 `BarState.lockscreenMonitorProfiles()`, `lockscreenLastEditedProfile()`.
- Produces:
  - `draftMonitorProfiles`
  - `draftLastEditedProfile`
  - `effectiveProfileForMonitor(name)`
  - `copyConfigurationTo(name)`
  - `copyConfigurationToAllOthers()`

- [ ] **Step 1: Write editor architecture RED**

Require:
- no `draftSharedProfile`;
- no `draftMonitorOverrides`;
- no `Use Shared Configuration`;
- no `Use Individual Configuration`;
- no Shared-switch modal state/functions;
- `draftMonitorProfiles` and `draftLastEditedProfile` exist;
- editor open seeds connected unseen outputs from last-edited profile;
- switch flushes/loads in-memory target profile and never reloads persisted state;
- passive previews bind directly to `effectiveProfileForMonitor(modelData.name)`;
- save sends monitor map + last-edited profile + saved library.

- [ ] **Step 2: Run RED**

Run:

```bash
bash tests/test-quickshell-lockscreen-multimonitor-editor.sh
```

Expected: FAIL on retained Shared/Individual contracts.

- [ ] **Step 3: Replace editor session ownership**

On load:

```qml
draftMonitorProfiles = cloneSnapshot(BarState.lockscreenMonitorProfiles()) || ({});
draftLastEditedProfile = cloneSnapshot(BarState.lockscreenLastEditedProfile()) || ({});

for (const screen of Quickshell.screens || []) {
    const name = screen && screen.name ? String(screen.name) : "";
    if (name.length > 0 && !draftMonitorProfiles[name])
        draftMonitorProfiles[name] = cloneSnapshot(draftLastEditedProfile);
}
```

`flushActiveProfile()` must always write the complete active draft into `draftMonitorProfiles[activeMonitorName]` and clone it into `draftLastEditedProfile`.

`activeProfileKey()` becomes `"monitor:" + activeMonitorName`.

Remove all Shared preview hold/settle logic because nothing propagates implicitly anymore.

- [ ] **Step 4: Keep copying explicit**

`copyConfigurationTo(name)` clones the active complete profile to the target monitor draft and resets target Auto Contrast/history cache as needed. `copyConfigurationToAllOthers()` iterates only connected non-source outputs.

Do not mutate another display from any drag/resize/rotate setter.

- [ ] **Step 5: Update saved-preset targets**

Remove `applySavedConfigurationToShared()` and Shared target UI.

`applySavedConfigurationToMonitor(id, name)` replaces `draftMonitorProfiles[name]`.

Keep:
- Save Current Configuration
- Rename
- Delete
- Move Up/Down
- Overwrite
- Apply To connected monitor
- Apply To All Other Displays

- [ ] **Step 6: Run editor tests GREEN**

Run:

```bash
bash tests/test-quickshell-lockscreen-multimonitor-editor.sh
bash tests/test-quickshell-lockscreen-saved-profiles.sh
bash tests/test-quickshell-lockscreen-editor-shortcuts.sh
bash tests/test-quickshell-lockscreen-editor.sh
```

Expected: PASS and no Shared/Individual UI strings.

- [ ] **Step 7: Commit Task 2**

Commit message:

```text
Simplify lockscreen editor to per-display profiles
```

---

### Task 3: 5% opacity invariant and explicit Element selector

**Files:**
- Modify: both `LockscreenPresentationState.js` copies
- Modify: `config/quickshell/awtarchy/LockscreenEditor.qml`
- Modify: `config/hypr/scripts/quickshell_application_state.sh`
- Modify: `tests/test-quickshell-lockscreen-selector-flyout.sh`
- Create: `tests/test-quickshell-lockscreen-element-opacity.sh`

**Interfaces:**
- Visible element opacity normalizes to integer/number range 5–100.
- Existing zero-opacity persisted state migrates to hidden/disabled equivalent.
- Element selector calls one editor function: `selectElementByName(name)`.

- [ ] **Step 1: Write opacity RED**

Test complete-profile normalization for:
- built-in logo opacity 2 -> opacity 5;
- custom media opacity 0 -> `visible:false`, opacity >=5;
- timezone/custom text opacity 0 -> `visible:false`, opacity >=5;
- visualizer opacity 0 -> `enabled:false`, opacity >=5;
- password opacity 0 -> new password feedback mode `hidden` when Task 4 schema is present; until Task 4, preserve password layout opacity at >=5 and add migration helper used by Task 4.

Also assert backend rejects visible opacity <5 after normalization boundary.

- [ ] **Step 2: Run RED**

Run:

```bash
bash tests/test-quickshell-lockscreen-element-opacity.sh
```

Expected: FAIL because current generic normalizers allow zero.

- [ ] **Step 3: Implement opacity migration/clamping**

Use explicit per-type normalization rather than blindly changing background opacity.

For visible built-in layout transforms, clamp:
```js
opacity: Math.max(5, Math.min(100, normalizedOpacity))
```

Dynamic types:
```js
if (opacity <= 0) visible = false;
opacity = Math.max(5, Math.min(100, opacity <= 0 ? 100 : opacity));
```

Visualizer:
```js
if (opacity <= 0) enabled = false;
opacity = Math.max(5, Math.min(100, opacity <= 0 ? 100 : opacity));
```

Backend profile schema accepts only 5–100 for visible element opacity fields after migration/normalization.

Editor opacity setters/sliders use minimum 5. Background opacity remains unchanged at 0–100.

- [ ] **Step 4: Write explicit selection RED**

Extend selector test to require:
```qml
function selectElementByName(name)
```

and a visible Element drawer selector whose model comes from `editableElementNames()`, displays `elementLabel(modelData)`, and calls `root.selectElementByName(modelData)`.

- [ ] **Step 5: Implement selector**

```qml
function selectElementByName(name) {
    const key = String(name || "");
    if (!elementExists(key))
        return;
    selectedElement = key;
    selectedElements = [key];
    activeDrawer = "element";
    elementPaletteOpen = false;
    statusMessage = "Selected " + elementLabel(key);
}
```

Add a compact selector row/list to Element tab; dynamic model refreshes from current draft arrays.

- [ ] **Step 6: Run Task 3 GREEN**

Run:

```bash
bash tests/test-quickshell-lockscreen-element-opacity.sh
bash tests/test-quickshell-lockscreen-selector-flyout.sh
bash tests/test-quickshell-lockscreen-element-system.sh
bash tests/test-quickshell-lockscreen-visualizer-transparency.sh
```

Expected: PASS.

- [ ] **Step 7: Commit Task 3**

Commit message:

```text
Harden lockscreen element visibility controls
```

---

### Task 4: Password feedback schema and editor controls

**Files:**
- Modify: both `LockscreenPresentationState.js` copies
- Modify: `config/hypr/scripts/quickshell_application_state.sh`
- Modify: `config/quickshell/awtarchy/LockscreenEditor.qml`
- Modify: `config/quickshell/awtarchy-lock/LockScene.qml` if it currently owns mask presentation properties
- Create: `tests/test-quickshell-lockscreen-password-feedback.sh`
- Modify affected legacy mask tests.

**Interfaces:**
- Complete profile field: `lockscreen_password_feedback_mode`.
- Allowed: `squares|dots|custom|sparks|mini-flash|hidden`.
- `lockscreen_password_mask_character` retained for custom mode.
- Legacy `lockscreen_password_mask_mode` is migration input only.

- [ ] **Step 1: Write schema migration RED**

Assert:
```js
normalizedProfile({lockscreen_password_mask_mode:"dots"}).lockscreen_password_feedback_mode === "dots"
normalizedProfile({lockscreen_password_feedback_mode:"sparks"}).lockscreen_password_feedback_mode === "sparks"
normalizedProfile({lockscreen_password_feedback_mode:"bad"}).lockscreen_password_feedback_mode === "squares"
```

Backend must accept all six new values and write top-level mirror without the old mask-mode field as active state.

- [ ] **Step 2: Run RED**

Run:

```bash
bash tests/test-quickshell-lockscreen-password-feedback.sh
```

Expected: FAIL because the new field/modes do not exist.

- [ ] **Step 3: Implement schema and migration**

Resolver:
```js
function normalizedPasswordFeedbackMode(value, legacyValue) {
    const mode = String(value || "");
    if (["squares","dots","custom","sparks","mini-flash","hidden"].indexOf(mode) >= 0)
        return mode;
    const legacy = String(legacyValue || "");
    return ["squares","dots","custom"].indexOf(legacy) >= 0 ? legacy : "squares";
}
```

Profile output always contains `lockscreen_password_feedback_mode`.

Backend profile key list/validation uses the new field. Legacy state normalization migrates old mask mode before validation.

- [ ] **Step 4: Update editor state/UI**

Replace `draftPasswordMaskMode` with `draftPasswordFeedbackMode`.

Password controls expose:
- Squares
- Dots
- Custom
- Sparks
- Mini Flash
- Hidden

Custom-character control is available only for Custom.

Editor preview masks remain for squares/dots/custom. Sparks/Mini Flash get a local Demo action/preview epoch, and Hidden shows no password glyph preview.

- [ ] **Step 5: Run Task 4 GREEN**

Run:

```bash
bash tests/test-quickshell-lockscreen-password-feedback.sh
bash tests/test-quickshell-lockscreen-editor.sh
bash tests/test-quickshell-lockscreen-profile-save-parity.sh
```

Expected: PASS.

- [ ] **Step 6: Commit Task 4**

Commit message:

```text
Add lockscreen password feedback modes
```

---

### Task 5: Secure sparks, mini-flash, hidden mode, and failure edge light

**Files:**
- Modify: `config/quickshell/awtarchy-lock/LockSurface.qml`
- Modify: `config/quickshell/awtarchy-lock/LockScene.qml` only for presentation properties/components shared with preview
- Keep authentication implementation unchanged: `config/quickshell/awtarchy-lock/LockAuth.qml`
- Create: `tests/test-quickshell-lockscreen-password-effects.sh`
- Modify: `tests/test-quickshell-lockscreen-secure-monitor-profiles.sh`
- Modify: `tests/test-quickshell-lockscreen-editor-preview-runtime.sh` if preview demos are exercised there.

**Interfaces:**
- Local secure properties:
  - `passwordTypingEpoch`
  - `passwordFailureEpoch`
  - previous password length
- Presentation receives only effect epochs/count deltas, never password text.
- Existing `LockAuth.authenticationFailed()` signal remains unchanged.

- [ ] **Step 1: Write secure-effect RED**

Contract assertions:
- `LockAuth.qml` unchanged in ownership and still emits `authenticationFailed()`;
- `LockSurface.qml` increments a local failure epoch inside `onAuthenticationFailed`;
- red edge component exists on each `LockSurface`;
- typing effects are enabled only for `sparks`/`mini-flash`;
- `hidden` creates no persistent mask or per-key effect;
- typing-effect geometry is clipped to the password zone;
- no visual component receives `password.text` or submitted password contents as a property.

- [ ] **Step 2: Run RED**

Run:

```bash
bash tests/test-quickshell-lockscreen-password-effects.sh
```

Expected: FAIL on missing effects.

- [ ] **Step 3: Implement length-delta trigger safely**

Inside `TextInput.onTextChanged`, compare current length with a local previous length.

Only when length increases:
- clear stale auth error as today;
- increment typing effect epoch for sparks/mini-flash.

On deletion/backspace, do not emit an effect.

Do not pass the text value to scene/effect objects.

- [ ] **Step 4: Implement password-zone effects**

Create a clipped password feedback container centered on the existing password element transform.

For `sparks`:
- instantiate a small deterministic/randomized burst from the epoch;
- positions remain inside the password zone rectangle;
- particles fade/scale out in a short animation.

For `mini-flash`:
- create one small radial/rectangular soft flash at a pseudo-random location inside the password zone;
- fade rapidly.

For `squares|dots|custom`, keep current mask behavior.

For `hidden`, render none of the above.

- [ ] **Step 5: Implement red authentication-failure edge light**

On existing connection:
```qml
function onAuthenticationFailed() {
    root.passwordFailureEpoch += 1;
    root.passwordFailureMaskCount = Math.max(1, root.submittedMaskCount);
    password.text = "";
    root.focusPasswordWhenReady();
}
```

The edge overlay:
- is inside each secure surface;
- is red;
- briefly raises edge opacity then fades;
- does not capture input;
- triggers regardless of password feedback mode.

Because every surface connects to the shared auth object, all displays react to the same failure signal.

- [ ] **Step 6: Run security/effect GREEN**

Run:

```bash
bash tests/test-quickshell-lockscreen-password-effects.sh
bash tests/test-quickshell-lockscreen-secure-monitor-profiles.sh
bash tests/test-quickshell-lockscreen-foundation.sh
bash tests/test-security-boundaries.sh
```

Expected: PASS with `LockAuth.qml` still PAM owner and `WlSessionLock` still sole lock authority.

- [ ] **Step 7: Commit Task 5**

Commit message:

```text
Add secure lockscreen password effects
```

---

### Task 6: Migration cleanup, managed history, and final verification

**Files:**
- Update permanent tests that still assert Shared/Individual behavior.
- Update: `local/share/awtarchy/quickshell-managed-history.sha256`
- Remove: `.github/workflows/feature-lockscreen-profile-roundtrip.yml`
- Update `AGENTS.md` only if the persistent-state ownership description materially requires it after comparing current wording.
- No temporary production patchers/workflows may remain.

**Interfaces:**
- Final state owns only active per-display profile semantics.
- Legacy Shared/override fields exist only as migration compatibility handled in resolver/backend.

- [ ] **Step 1: Search for stale active Shared/Individual contracts**

Run repository searches for:
```text
draftSharedProfile
draftMonitorOverrides
Use Shared Configuration
Use Individual Configuration
lockscreenMonitorOverrides(
lockMonitorOverrides
sharedProfile:
monitorOverrides:
applySavedConfigurationToShared
```

Retain references only in migration tests/docs where explicitly historical.

- [ ] **Step 2: Migrate/remove stale permanent tests**

Replace old behavioral expectations with:
- per-display isolation;
- exact output reconnect;
- last-edited seed;
- explicit copy;
- no Shared UI.

Delete tests whose sole purpose was Shared mode conversion/settled Shared mirroring after their replacement tests are GREEN.

- [ ] **Step 3: Refresh managed-history hashes**

Append SHA-256 entries for every changed managed Quickshell/script file using the repository's existing managed-history format. Do not remove historical hashes.

- [ ] **Step 4: Remove temporary feature workflow**

Delete:
```text
.github/workflows/feature-lockscreen-profile-roundtrip.yml
```

Confirm no temporary feature patch scripts/workflows remain.

- [ ] **Step 5: Run complete focused lockscreen verification**

Run:

```bash
for test in tests/test-quickshell-lockscreen-*.sh; do
  echo "=== $test ==="
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

Expected: every command exits 0.

- [ ] **Step 6: Re-run critical permanent contracts after cleanup**

At minimum:

```bash
bash tests/test-quickshell-lockscreen-profile-save-parity.sh
bash tests/test-quickshell-lockscreen-monitor-profile-state.sh
bash tests/test-quickshell-lockscreen-multimonitor-editor.sh
bash tests/test-quickshell-lockscreen-element-opacity.sh
bash tests/test-quickshell-lockscreen-password-feedback.sh
bash tests/test-quickshell-lockscreen-password-effects.sh
bash tests/test-quickshell-lockscreen-secure-monitor-profiles.sh
bash tests/test-quickshell-lockscreen-interactive-managed-history.sh
```

Expected: PASS.

- [ ] **Step 7: Commit final clean candidate**

Commit message:

```text
Finalize per-display lockscreen editor
```

- [ ] **Step 8: Runtime acceptance remains required**

Do not claim visual/runtime completion from CI alone. Runtime test must verify:
- Ctrl+S with no changes succeeds;
- each display retains its own configuration;
- new display seeds from last edited configuration;
- copy-to-display is deliberate;
- preset operations persist;
- opacity cannot drop below 5%;
- Element selector works without canvas clicking;
- Sparks/Mini Flash stay inside password zone;
- Hidden shows no per-key feedback;
- failed auth flashes red edges on all locked displays;
- correct password unlocks the coherent session;
- transitions/media/weather/visualizer still render correctly.
