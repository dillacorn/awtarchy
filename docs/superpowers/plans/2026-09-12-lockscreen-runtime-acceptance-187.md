# Lockscreen Runtime Acceptance #187 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement every automated/code-addressable acceptance requirement in issue #187 and produce a new exact PR #181 runtime-test candidate without claiming Hyprland runtime success.

**Architecture:** Extend the existing single persisted lockscreen state and shared secure/editor scene copies. Keep `WlSessionLock` and `LockAuth.qml` unchanged, keep audio/pointer/editor data presentation-only, and use bounded QML timers and fixed-size data structures.

**Tech Stack:** Bash, jq, Qt 6 QML/Quickshell, CAVA raw ASCII output, Hyprland dispatch, shell regression tests, GitHub Actions.

**Spec:** GitHub issue #187, with issues #188, #189, and #190 subordinate where they do not conflict.

## Global Constraints

- `WlSessionLock` remains the sole lock authority.
- `LockAuth.qml` remains the PAM/authentication owner and must not be modified.
- Production changes use RED/GREEN TDD.
- Secure/editor presentation parity remains exact.
- No release, tag, merge, force-push, or branch deletion operations.
- Runtime, visual, audio, and compositor behavior remains unverified until maintainer testing on Hyprland.

---

### Task 1: Persisted entry-transition duration and scene-first sequencing

**Files:** state helper, `BarState.qml`, lock shell/surface, shared scene copies, editor, focused transition tests.

- [ ] Add failing tests for a validated persisted duration, editor slider/replay propagation, deliberate default, fixed tile bound, actual-scene reveal, and logo formation starting only after reveal completion.
- [ ] Run the focused test and confirm the expected missing-duration/sequencing failures.
- [ ] Add `lockscreen_entry_transition_duration` with a safe 400–4000 ms range and 1200 ms default through the one atomic editor-save path.
- [ ] Pass duration only through presentation components; drive one eased reveal and gate logo formation on `!entryTransitionRunning`.
- [ ] Copy the secure scene to the preview scene, run focused tests, and commit.

### Task 2: Coherent hover field and improved bounded logo physics

**Files:** shared scene copies and pointer/physics tests.

- [ ] Replace the old click-only assertions with failing contracts for one shared active-only physics timer, coherent neighbor-weighted hover targets, no connector lines, bounded velocities/collisions, and spring reformation.
- [ ] Confirm RED against the tested head.
- [ ] Feed hover targets into the same per-cell displacement state and integrate damped velocity toward the target; preserve the bounded bucket collision solver and repeated-click impulses.
- [ ] Run focused pointer/physics tests, copy scene parity, and commit.

### Task 3: Direct visualizer frames and meaningful performance modes

**Files:** state helper, `BarState.qml`, analyzer copies, CAVA helper/config, editor, shell, focused visualizer tests.

- [ ] Add failing tests for `balanced`/`responsive` persistence, 60/90 Hz CAVA selection, direct frame assignment with no QML interpolation timer, increased default sensitivity, and shared straight/arc/circle data.
- [ ] Confirm RED.
- [ ] Add a persisted performance mode, pass it as a helper argument, generate a temporary derived CAVA config with the selected framerate, lower CAVA noise reduction, and assign parsed frames directly.
- [ ] Preserve zero-spectrum behavior on disable/exit/malformed input, run focused tests, and commit.

### Task 4: Editor-owned background adjustment sliders

**Files:** editor, Quick Settings, shared scene copies, focused background/UI tests.

- [ ] Add failing tests for editor-only detailed opacity/blur/brightness controls, Awtarchy-style pointer-driven tracks, ungated controls, direct signed brightness behavior, and first-transparency default blur.
- [ ] Confirm RED.
- [ ] Treat overlay strength as signed brightness: zero means none, negative darkens, positive lightens; slider interaction selects direction without a prerequisite button.
- [ ] Make blur affect the complete background composition and seed a nonzero blur only on the first opaque-to-transparent reduction when blur is still zero.
- [ ] Remove detailed opacity presets and precision background choices from Quick Settings while retaining the editor action and useful toggles.
- [ ] Run focused tests and commit.

### Task 5: Custom-image deletion and high defensive scale ceiling

**Files:** state helper, `BarState.qml`, editor, shared scene copies, focused element/editor tests.

- [ ] Add failing tests for Delete-key removal through `removeCustomImage`, undo/redo integration, and a custom-image-only scale ceiling of 10× across validation, editor, and renderer.
- [ ] Confirm RED.
- [ ] Route Delete only when the selected item is a custom image; retain the existing atomic draft/save path and history snapshot.
- [ ] Apply the 10× ceiling only to custom images, preserving existing built-in/password/visualizer limits.
- [ ] Run focused tests and commit.

### Task 6: Production Awtwall fullscreen path

**Files:** wallpaper-picker helper and focused runtime-polish test.

- [ ] Add a failing executable fake-terminal/fake-Awtwall test that captures the exact argv used by production and requires stable class/title plus both Alacritty fullscreen startup and Hyprland fullscreen dispatch fallback.
- [ ] Confirm RED.
- [ ] Launch with an exact class/title and issue targeted `hyprctl dispatch fullscreen 1` retries only for that picker window, without changing desktop wallpaper or selection-only arguments.
- [ ] Run helper and focused tests, then commit.

### Task 7: Managed history, full validation, and PR candidate

**Files:** managed-history manifest, permanent workflow, PR #181/issue #187 metadata if needed.

- [ ] Add/update all changed managed-file hashes using the repository’s existing generation path; verify no temporary helper workflow remains.
- [ ] Run syntax checks, every lockscreen-focused test, security/foundation tests, `git diff --check`, and the full integration command used by permanent CI.
- [ ] Self-review the complete diff against every #187 requirement and correct any static gap with another RED/GREEN cycle.
- [ ] Push the exact branch head, wait for all PR-triggered workflows, and report the full 40-character SHA as a runtime-test candidate only after CI is green.
