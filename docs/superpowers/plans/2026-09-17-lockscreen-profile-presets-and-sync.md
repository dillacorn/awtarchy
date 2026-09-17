# Lockscreen Profile Presets And Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make multi-monitor lockscreen profile saving reliable, reduce Shared-preview drag lag, make Individual-to-Shared switching non-destructive, and add global reusable named lockscreen configurations.

**Architecture:** Keep the existing complete-profile model. Extend the application-state backend from an atomic Shared+overrides transaction to an atomic Shared+overrides+saved-presets transaction, while keeping the resolver and backend schemas in lockstep. In `LockscreenEditor.qml`, separate live active-display manipulation from settled Shared passive-preview state and add confirmation/preset draft state without changing authentication ownership.

**Tech Stack:** QML/QtQuick, JavaScript, Bash, jq, Node-based resolver tests, GitHub Actions validation.

**Spec:** `docs/superpowers/specs/2026-09-17-lockscreen-profile-presets-and-sync-design.md`

## Global Constraints

- Work only on `feature/lockscreen-media-editor-polish`; do not modify `main`.
- Preserve `WlSessionLock` as the sole secure lock authority.
- Preserve `LockAuth.qml` as PAM/authentication owner.
- Keep complete normalized profiles; do not introduce sparse monitor patches.
- Keep saves atomic: Shared, overrides, and saved presets either all persist or none persist.
- Named presets are global reusable visual snapshots and contain no authentication/session state or derived Auto Contrast colors.
- Runtime/visual behavior is not confirmed until maintainer testing in Hyprland.

---

### Task 1: Resolver/Backend Profile Schema Parity

**Files:**
- Modify: `config/quickshell/awtarchy/LockscreenPresentationState.js`
- Modify: `config/quickshell/awtarchy-lock/LockscreenPresentationState.js`
- Modify: `config/hypr/scripts/quickshell_application_state.sh`
- Test: `tests/test-quickshell-lockscreen-monitor-profile-resolver.mjs`
- Create: `tests/test-quickshell-lockscreen-profile-save-parity.sh`

**Interfaces:**
- Consumes: existing `normalizedProfile()`, `sharedProfile()`, `monitorOverrides()`, `save-lockscreen-editor-profiles`.
- Produces: resolver output guaranteed to satisfy backend profile validation; backend diagnostics identify the rejected profile section.

- [ ] **Step 1: Write failing parity tests**

Add resolver cases with malformed/legacy values that normalization must repair, including password position outside secure editor bounds, invalid enum values, non-integral bounded integers, malformed optional repeated-element fields, and missing optional profile fields. Feed normalized JSON to `quickshell_application_state.sh save-lockscreen-editor-profiles` in an isolated XDG cache/config fixture and require success.

- [ ] **Step 2: Run focused tests and verify RED**

Run:

```bash
node tests/test-quickshell-lockscreen-monitor-profile-resolver.mjs
bash tests/test-quickshell-lockscreen-profile-save-parity.sh
```

Expected: at least one normalized profile is rejected by the backend before the fix.

- [ ] **Step 3: Align resolver normalization with backend bounds**

Make password transforms use the backend's `x=0.15..0.85`, `y=0.20..0.86`, and opacity minimum 20. Ensure all repeated elements, integer fields, enum fields, mask character, path strings, and complete-profile keys normalize to backend-valid values in both unlocked and secure copies of the resolver.

- [ ] **Step 4: Improve backend diagnostic granularity without weakening validation**

Split `normalize_lockscreen_profile_json` validation into named checks or emit a deterministic label such as `invalid lockscreen profile: layout`, `...: custom media`, `...: timezone clocks`, `...: visualizer`, `...: background`, or `...: presentation`. Preserve exit status 2 and atomic rollback semantics.

- [ ] **Step 5: Re-run parity tests**

Expected: GREEN.

- [ ] **Step 6: Commit**

```bash
git add config/quickshell/awtarchy/LockscreenPresentationState.js \
        config/quickshell/awtarchy-lock/LockscreenPresentationState.js \
        config/hypr/scripts/quickshell_application_state.sh \
        tests/test-quickshell-lockscreen-monitor-profile-resolver.mjs \
        tests/test-quickshell-lockscreen-profile-save-parity.sh
git commit -m "Fix lockscreen profile save parity"
```

### Task 2: Settled Shared Preview Synchronization

**Files:**
- Modify: `config/quickshell/awtarchy/LockscreenEditor.qml`
- Modify: `tests/test-quickshell-lockscreen-multimonitor-editor.sh`
- Create: `tests/test-quickshell-lockscreen-shared-preview-settle.sh`

**Interfaces:**
- Consumes: `profileFromDraftScalars()`, `effectiveProfileForMonitor(name)`, direct manipulation lifecycle, `historyTransactionActive`, inertia lifecycle.
- Produces: `settledSharedProfile` snapshot and direct-manipulation hold state used only by passive Shared previews.

- [ ] **Step 1: Write RED contracts**

Require passive Shared previews to resolve `settledSharedProfile` while a direct-manipulation hold is active, while the active monitor continues to use `profileFromDraftScalars()`. Require final publication when drag/resize/rotate/visualizer-width manipulation or inertia completes.

- [ ] **Step 2: Verify RED**

```bash
bash tests/test-quickshell-lockscreen-shared-preview-settle.sh
```

- [ ] **Step 3: Implement settled snapshot lifecycle**

Add editor properties for the settled Shared snapshot and manipulation hold. Initialize the settled snapshot from the loaded Shared draft. Begin the hold only for continuous direct manipulation. End it after the final settled state, then clone the active Shared profile into `settledSharedProfile` once. Discrete edits keep immediate Shared preview behavior.

- [ ] **Step 4: Verify GREEN plus existing editor tests**

```bash
bash tests/test-quickshell-lockscreen-shared-preview-settle.sh
bash tests/test-quickshell-lockscreen-multimonitor-editor.sh
bash tests/test-quickshell-lockscreen-editor.sh
```

- [ ] **Step 5: Commit**

```bash
git add config/quickshell/awtarchy/LockscreenEditor.qml \
        tests/test-quickshell-lockscreen-shared-preview-settle.sh \
        tests/test-quickshell-lockscreen-multimonitor-editor.sh
git commit -m "Settle shared lockscreen previews after drag"
```

### Task 3: Safe Individual-To-Shared Conversion

**Files:**
- Modify: `config/quickshell/awtarchy/LockscreenEditor.qml`
- Create: `tests/test-quickshell-lockscreen-profile-mode-switch.sh`

**Interfaces:**
- Consumes: `useIndividualConfiguration()`, draft Shared profile, draft monitor overrides, active monitor identity.
- Produces: confirmation state plus `confirmUseExistingShared()`, `confirmPromoteIndividualToShared()`, and cancel path.

- [ ] **Step 1: Write RED mode-switch contract**

Assert that clicking Use Shared no longer deletes the override directly. Require a warning/confirmation flow and both approved outcomes: discard Individual and load existing Shared, or promote current Individual to Shared and then remove only that monitor override.

- [ ] **Step 2: Verify RED**

```bash
bash tests/test-quickshell-lockscreen-profile-mode-switch.sh
```

- [ ] **Step 3: Implement confirmation state and dialog**

Keep all state draft-only. `Use Existing Shared` removes the active override, loads Shared, and restores Shared history. `Use This Display as Shared` first captures the complete active profile, replaces `draftSharedProfile`, removes the active override, publishes the new settled Shared snapshot, and loads the promoted Shared profile. Cancel performs no mutations.

- [ ] **Step 4: Verify GREEN plus multi-monitor regression**

```bash
bash tests/test-quickshell-lockscreen-profile-mode-switch.sh
bash tests/test-quickshell-lockscreen-multimonitor-editor.sh
```

- [ ] **Step 5: Commit**

```bash
git add config/quickshell/awtarchy/LockscreenEditor.qml \
        tests/test-quickshell-lockscreen-profile-mode-switch.sh
git commit -m "Protect lockscreen profile mode switching"
```

### Task 4: Persisted Global Saved Profiles

**Files:**
- Modify: `config/hypr/scripts/quickshell_application_state.sh`
- Modify: `config/hypr/scripts/quickshell_lockscreen_editor_save.sh`
- Modify: `config/quickshell/awtarchy/BarState.qml`
- Modify: `config/quickshell/awtarchy/LockscreenEditor.qml`
- Create: `tests/test-quickshell-lockscreen-saved-profiles.sh`

**Interfaces:**
- Produces state field `lockscreen_saved_profiles` as ordered array of `{id,name,profile}`.
- Extends editor save mode to `--profiles <shared-json> <overrides-json> <saved-profiles-json>` while retaining compatibility with the existing three-argument invocation during migration tests.
- Produces `BarState.lockscreenSavedProfiles()` returning normalized ordered entries.

- [ ] **Step 1: Write backend RED tests**

Cover valid create/save/reload order, case-insensitive unique names, stable IDs, profile normalization, invalid entry atomic rollback, rename/reorder/delete persistence, and compatibility when `lockscreen_saved_profiles` is absent.

- [ ] **Step 2: Verify RED**

```bash
bash tests/test-quickshell-lockscreen-saved-profiles.sh
```

- [ ] **Step 3: Implement saved-profile normalization and atomic persistence**

Add bounded preset count and name length, validate stable IDs such as `profile-[A-Za-z0-9_-]{1,64}`, reject duplicate IDs and case-insensitive duplicate names, normalize every complete profile through the same profile validator, and commit Shared+overrides+saved profiles in one temp-file transaction.

- [ ] **Step 4: Expose saved profiles through BarState and editor session drafts**

Load them once when the editor opens and never reload during monitor switching. Ensure Escape discards unsaved preset operations.

- [ ] **Step 5: Verify backend and state tests GREEN**

```bash
bash tests/test-quickshell-lockscreen-saved-profiles.sh
bash tests/test-quickshell-lockscreen-monitor-profile-state.sh
```

- [ ] **Step 6: Commit**

```bash
git add config/hypr/scripts/quickshell_application_state.sh \
        config/hypr/scripts/quickshell_lockscreen_editor_save.sh \
        config/quickshell/awtarchy/BarState.qml \
        config/quickshell/awtarchy/LockscreenEditor.qml \
        tests/test-quickshell-lockscreen-saved-profiles.sh
git commit -m "Add reusable lockscreen configurations"
```

### Task 5: Saved Configurations Layout UI And Actions

**Files:**
- Modify: `config/quickshell/awtarchy/LockscreenEditor.qml`
- Modify: `tests/test-quickshell-lockscreen-saved-profiles.sh`

**Interfaces:**
- Consumes: editor `draftSavedProfiles` and complete profile snapshots.
- Produces actions to create, rename, delete, move up/down, overwrite from current display, apply to active display, apply to any connected display, and apply explicitly to Shared Configuration.

- [ ] **Step 1: Extend RED UI/action contracts**

Require Layout-tab labels/actions for Save Current Configuration, Rename, Delete, Move Up, Move Down, Overwrite, Apply To, connected-monitor targets, and Shared Configuration. Require applying to a monitor to create/replace an Individual override; applying to Shared must not create monitor overrides.

- [ ] **Step 2: Verify RED**

```bash
bash tests/test-quickshell-lockscreen-saved-profiles.sh
```

- [ ] **Step 3: Implement editor actions**

Use complete cloned profiles only. Applying to the active profile records undo history. Applying to another monitor replaces that target override and clears only that target's undo/redo stacks. Applying to Shared replaces `draftSharedProfile`, refreshes `settledSharedProfile`, and reloads the active scalars only when the active display resolves Shared.

- [ ] **Step 4: Implement Layout-tab controls and confirmations**

Keep the controls compact and use existing Awtarchy editor primitives. Delete requires confirmation. Rename rejects blank/duplicate names. Move controls disable at list boundaries. Overwrite requires confirmation because it destroys the preset's prior snapshot.

- [ ] **Step 5: Save presets atomically with normal Ctrl+S**

Pass `JSON.stringify(draftSavedProfiles)` through the existing editor save process. Do not add a separate persistence path.

- [ ] **Step 6: Verify GREEN**

```bash
bash tests/test-quickshell-lockscreen-saved-profiles.sh
bash tests/test-quickshell-lockscreen-profile-mode-switch.sh
bash tests/test-quickshell-lockscreen-shared-preview-settle.sh
bash tests/test-quickshell-lockscreen-multimonitor-editor.sh
bash tests/test-quickshell-lockscreen-editor-shortcuts.sh
```

- [ ] **Step 7: Commit**

```bash
git add config/quickshell/awtarchy/LockscreenEditor.qml \
        tests/test-quickshell-lockscreen-saved-profiles.sh
git commit -m "Finish lockscreen configuration presets"
```

### Task 6: Managed History And Final Verification

**Files:**
- Modify: `local/share/awtarchy/quickshell-managed-history.sha256`
- Modify if required: `tests/test-quickshell-lockscreen-interactive-managed-history.sh`
- Delete: temporary branch-validation scripts/workflow used only to execute this plan remotely.

**Interfaces:**
- Produces one clean runtime-test candidate SHA with no temporary validation machinery.

- [ ] **Step 1: Append current managed-file hashes**

Append, never rewrite historical entries, for every managed file changed in this pass.

- [ ] **Step 2: Run the complete focused suite**

```bash
for test in tests/test-quickshell-lockscreen-*.sh; do bash "$test"; done
node tests/test-quickshell-lockscreen-efficiency.mjs
node tests/test-quickshell-lockscreen-monitor-profile-resolver.mjs
bash tests/test-lua-validation.sh
bash tests/test-quickshell-production-readiness.sh
bash -n config/hypr/scripts/quickshell_application_state.sh
bash -n config/hypr/scripts/quickshell_lockscreen_editor_save.sh
git diff --check
```

Expected: all GREEN.

- [ ] **Step 3: Remove temporary validation tooling and rerun permanent contracts**

Ensure no `.github/workflows/feature-*` or `.github/scripts/feature-*` files introduced for this pass remain.

- [ ] **Step 4: Commit final cleanup**

```bash
git add -A
git commit -m "Finalize lockscreen profile editor polish"
```

- [ ] **Step 5: Re-read branch head and provide exact runtime command**

Do not describe direct-manipulation performance or interactive dialog behavior as runtime-confirmed until the maintainer tests the candidate under Hyprland.