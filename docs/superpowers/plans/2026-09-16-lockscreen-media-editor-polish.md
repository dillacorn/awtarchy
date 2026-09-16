# Lockscreen Media and Editor Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make lockscreen editing click-safe and keyboard-friendly, add a direct editor shortcut, and support still/GIF/MP4 lockscreen media with silent pre-rolled video inside the existing secure Quickshell effects/transition pipeline.

**Architecture:** Keep Awtwall as the selector and Quickshell as the renderer. Introduce a focused media renderer component shared by secure/background preview scenes and custom media elements; still/GIF/video are selected by normalized local extension. Qt Multimedia video begins decoding before the transition reveals the secure destination, reports readiness after advancing frames, and has a bounded fallback so presentation cannot stall.

**Tech Stack:** QML/Qt Quick, Qt Multimedia, Quickshell, Hyprland Lua config, Bash helpers/tests, Arch package catalog.

**Spec:** `docs/superpowers/specs/2026-09-16-lockscreen-media-editor-polish-design.md`

## Global Constraints

- Work only on `feature/lockscreen-media-editor-polish` until the maintainer explicitly requests merge/release work.
- Preserve `WlSessionLock` as lock authority and preserve current authentication ownership.
- Do not use external `mpvpaper`/`mpv` windows for secure lockscreen rendering.
- Video must loop silently and must not stall secure presentation when decoding fails.
- Static checks do not prove real GIF/video/compositor behavior; maintainer runtime testing remains required.

---

### Task 1: Editor pointer and keyboard polish

**Files:**
- Modify: `config/quickshell/awtarchy/LockscreenEditor.qml`
- Test: `tests/test-quickshell-lockscreen-media-editor-polish.sh`

**Interfaces:**
- Consumes: existing `save()`, `close()`, selection, history transaction, snapping, flick/inertia helpers.
- Produces: drag activation threshold state inside the existing element `MouseArea`; `Ctrl+S` application shortcut; visible save/cancel shortcut hint.

- [ ] **Step 1: Write failing contracts**

Add assertions that the editor contains a small drag threshold, does not call movement/hold/history-start directly on press, starts movement only after the threshold, exposes `Ctrl+S` to `root.save()`, preserves Escape cancel behavior, and renders `Ctrl+S Save` / `Esc Cancel` helper text.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
bash tests/test-quickshell-lockscreen-media-editor-polish.sh
```

Expected: FAIL because the new threshold/save/hint contracts do not exist yet.

- [ ] **Step 3: Implement minimal editor behavior**

Add press-origin/pending-drag state and a roughly five-pixel movement threshold. A normal click only performs selection. When movement exceeds the threshold, begin the existing history transaction/hold and continue through the existing snap/velocity/flick path. Add:

```qml
Shortcut {
    sequence: "Ctrl+S"
    context: Qt.ApplicationShortcut
    enabled: root.open && !root.pickerSuspended
    autoRepeat: false
    onActivated: root.save()
}
```

Keep Escape routed through the existing cancel/close path and add compact shortcut discoverability text to the editor controls.

- [ ] **Step 4: Run focused and existing editor tests**

```bash
bash tests/test-quickshell-lockscreen-media-editor-polish.sh
bash tests/test-quickshell-lockscreen-editor.sh
bash tests/test-quickshell-lockscreen-editor-tooling.sh
```

Expected: PASS.

- [ ] **Step 5: Commit**

Commit message: `Polish lockscreen editor controls`

---

### Task 2: Direct editor shortcut and Quick Settings discoverability

**Files:**
- Modify: `config/quickshell/awtarchy/shell.qml`
- Modify: `config/quickshell/awtarchy/QuickSettings.qml`
- Modify: `config/hypr/hyprland.lua`
- Test: `tests/test-quickshell-lockscreen-media-editor-polish.sh`

**Interfaces:**
- Consumes: `LockscreenEditor.openFocused()` and existing Quickshell IPC/bind patterns.
- Produces: focused editor IPC action and `Super+Alt+E` Hyprland bind; Quick Settings hint `Super + Alt + E`.

- [ ] **Step 1: Extend the failing test**

Require one IPC path that calls `LockscreenEditor.openFocused()`, a Hyprland `SUPER + ALT + e` binding that invokes it through the established Quickshell command pattern, and the Quick Settings hint under `Edit Layout`.

- [ ] **Step 2: Run the focused test and verify RED**

```bash
bash tests/test-quickshell-lockscreen-media-editor-polish.sh
```

Expected: FAIL on IPC/bind/hint contracts.

- [ ] **Step 3: Implement the smallest wiring**

Expose a narrowly scoped IPC function from the existing shell process and bind `SUPER + ALT + e` without colliding with existing bindings. Keep Quick Settings’ click action unchanged and place muted shortcut text directly below the button.

- [ ] **Step 4: Run focused shell/Lua tests**

```bash
bash tests/test-quickshell-lockscreen-media-editor-polish.sh
bash tests/test-lua-validation.sh
```

Expected: PASS.

- [ ] **Step 5: Commit**

Commit message: `Add lockscreen editor shortcut`

---

### Task 3: Awtwall all-media selection and Qt Multimedia dependency

**Files:**
- Modify: `config/hypr/scripts/quickshell_lockscreen_wallpaper_picker.sh`
- Modify: package catalog in `local/share/awtarchy/awtarchy-runtime.sh`
- Modify existing picker tests whose old still-only contract is intentionally superseded.
- Test: `tests/test-quickshell-lockscreen-media-editor-polish.sh`

**Interfaces:**
- Consumes: Awtwall `--select-only --type all --select-result ...` behavior.
- Produces: lockscreen picker result path for still/GIF/MP4 and explicit Qt Multimedia runtime dependency.

- [ ] **Step 1: Add/adjust failing tests**

Require `--type all`; remove old assertions that require `--type images`. Require the verified Arch Qt Multimedia package name in the same official-package catalog used for Quickshell dependencies.

- [ ] **Step 2: Run picker/package contracts and verify RED**

```bash
bash tests/test-quickshell-lockscreen-media-editor-polish.sh
bash tests/test-quickshell-lockscreen-picker-targeting.sh
```

Expected: FAIL until picker/package implementation changes.

- [ ] **Step 3: Implement picker/package changes**

Switch both terminal launch paths to Awtwall all-media selection. Add the Qt Multimedia package to the existing official Arch package set without changing source/category semantics.

- [ ] **Step 4: Run syntax and package/picker tests**

```bash
bash -n config/hypr/scripts/quickshell_lockscreen_wallpaper_picker.sh
bash tests/test-quickshell-lockscreen-media-editor-polish.sh
bash tests/test-quickshell-lockscreen-picker-targeting.sh
bash tests/test-quickshell-lockscreen-runtime-polish.sh
```

Expected: PASS.

- [ ] **Step 5: Commit**

Commit message: `Allow lockscreen media selection`

---

### Task 4: Shared local media renderer

**Files:**
- Create: `config/quickshell/awtarchy-lock/LockMedia.qml`
- Modify: `config/quickshell/awtarchy-lock/LockScene.qml`
- Modify preview-side import/use only as required by current shared-scene architecture.
- Test: `tests/test-quickshell-lockscreen-media-editor-polish.sh`

**Interfaces:**
- `LockMedia.source: string`
- `LockMedia.fillMode: int`
- `LockMedia.mediaKind: "image" | "gif" | "video" | "none"`
- `LockMedia.ready: bool`
- `LockMedia.playbackAdvanced: bool`
- renderer owns `Image`, `AnimatedImage`, and `MediaPlayer`/`VideoOutput`; no `AudioOutput`.

- [ ] **Step 1: Add failing renderer contracts**

Require normalized case-insensitive `.gif`/`.mp4` detection, static fallback for supported still extensions, `AnimatedImage` for GIF, `MediaPlayer`+`VideoOutput` for MP4, looping playback, and absence of `AudioOutput`.

- [ ] **Step 2: Run focused test and verify RED**

```bash
bash tests/test-quickshell-lockscreen-media-editor-polish.sh
```

Expected: FAIL because `LockMedia.qml` does not exist.

- [ ] **Step 3: Implement `LockMedia.qml`**

Use one item that exposes source size/readiness and keeps only the selected renderer active. Video uses Qt Multimedia and starts automatically when a non-empty MP4 source is assigned; it loops infinitely and exposes decoded-frame advancement/readiness without audio output.

- [ ] **Step 4: Replace background/custom still-only renderer usage**

Use `LockMedia` in the background composition and custom media delegate while preserving the existing effect wrappers, normalized geometry, custom transforms, and spawn effects. Keep custom-media path/state schema compatible with existing saved `customImages` data.

- [ ] **Step 5: Run focused and scene regression tests**

```bash
bash tests/test-quickshell-lockscreen-media-editor-polish.sh
bash tests/test-quickshell-lockscreen-runtime-regressions.sh
bash tests/test-quickshell-lockscreen-transition-layer.sh
bash tests/test-quickshell-lockscreen-entry-transitions.sh
```

Expected: PASS.

- [ ] **Step 6: Commit**

Commit message: `Render lockscreen animated media`

---

### Task 5: Video pre-roll transition readiness

**Files:**
- Modify: `config/quickshell/awtarchy-lock/LockScene.qml`
- Modify: `config/quickshell/awtarchy-lock/LockSurface.qml`
- Modify preview/editor transition wiring as required for parity.
- Test: `tests/test-quickshell-lockscreen-media-editor-polish.sh`

**Interfaces:**
- Scene exposes whether background media needs pre-roll and whether video has advanced.
- Surface transition start is gated only at presentation level; WlSessionLock already exists regardless of readiness.
- Bounded fallback timer releases presentation even when video decode never advances.

- [ ] **Step 1: Add failing pre-roll contracts**

Require transition auto-start to be disabled for the secure surface, a readiness/fallback gate, more than one decoded-frame indication for video when available, and a bounded timeout under one second. Require the transition destination to remain live.

- [ ] **Step 2: Run focused test and verify RED**

```bash
bash tests/test-quickshell-lockscreen-media-editor-polish.sh
```

Expected: FAIL on pre-roll gate contracts.

- [ ] **Step 3: Implement presentation gate**

Construct the secure destination immediately so video starts decoding behind the desktop capture. Start `LockTransitionLayer.restart()` when non-video media is ready immediately, when video has demonstrably advanced frames, or when the bounded fallback fires. Do not gate session-lock creation/authentication on media.

- [ ] **Step 4: Preserve preview/runtime parity**

Apply equivalent readiness semantics to editor transition replay where needed so preview does not demonstrate a different frozen-first-frame behavior from runtime.

- [ ] **Step 5: Run transition/runtime regression tests**

```bash
bash tests/test-quickshell-lockscreen-media-editor-polish.sh
bash tests/test-quickshell-lockscreen-transition-layer.sh
bash tests/test-quickshell-lockscreen-entry-transitions.sh
bash tests/test-quickshell-lockscreen-runtime-regressions.sh
bash tests/test-quickshell-lockscreen-efficiency.mjs
```

Expected: PASS.

- [ ] **Step 6: Commit**

Commit message: `Pre-roll lockscreen video transitions`

---

### Task 6: Deterministic animated-media contrast and final validation

**Files:**
- Modify contrast helper/state only where current implementation requires animated-media handling.
- Update `tests/test-quickshell-lockscreen-media-editor-polish.sh` and affected existing tests.

**Interfaces:**
- Still-image contrast behavior remains unchanged.
- Animated media uses one deterministic representative sample or deterministic fallback; no continuous per-frame recalculation.

- [ ] **Step 1: Add failing contrast contract**

Require explicit animated-media handling that runs once per selection/save path and cannot continuously chase rendered frames.

- [ ] **Step 2: Verify RED, implement minimal deterministic handling, verify GREEN**

Run the focused test before and after implementation.

- [ ] **Step 3: Run broad automated validation**

```bash
bash tests/test-quickshell-lockscreen-media-editor-polish.sh
bash tests/test-quickshell-lockscreen-editor.sh
bash tests/test-quickshell-lockscreen-editor-tooling.sh
bash tests/test-quickshell-lockscreen-picker-targeting.sh
bash tests/test-quickshell-lockscreen-runtime-polish.sh
bash tests/test-quickshell-lockscreen-runtime-regressions.sh
bash tests/test-quickshell-lockscreen-transition-layer.sh
bash tests/test-quickshell-lockscreen-entry-transitions.sh
node tests/test-quickshell-lockscreen-efficiency.mjs
bash tests/test-lua-validation.sh
git diff --check
```

Also run `bash -n` on changed shell scripts and `shellcheck` where available.

- [ ] **Step 4: Verify branch target and diff**

Confirm branch head, changed files, no writes to `main`, and no auth/lock-authority changes outside presentation/media wiring.

- [ ] **Step 5: Commit**

Commit message: `Finish lockscreen media support`
