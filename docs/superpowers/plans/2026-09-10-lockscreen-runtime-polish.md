# Lockscreen Runtime Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn PR #181's first runtime candidate into a compact, usable lockscreen editor with working Awtwall selection, cohesive Quick Settings organization, and per-block gooey logo interaction.

**Architecture:** Keep existing state/auth ownership intact. Integrate Awtwall through the existing helper while suspending and restoring only the unlocked editor surface; refactor presentation controls without moving state ownership; replace connected-group pointer offsets with local per-cell deformation plus bounded neighbor cohesion.

**Tech Stack:** QML/Quickshell, Bash helpers, Hyprland layer-shell, existing shell regression tests and GitHub Actions validation.

**Spec:** `docs/superpowers/specs/2026-09-10-lockscreen-runtime-polish-design.md`

## Global Constraints

- `WlSessionLock` remains the sole lock authority.
- `LockAuth.qml` remains the PAM/authentication owner and must not be modified.
- The real secure password input remains in `LockSurface.qml`.
- PR #181 remains draft and unmerged until maintainer runtime approval.
- No release/tag changes.
- Visual/runtime success is not claimed from CI alone.

---

### Task 1: Runtime-polish regressions

**Files:**
- Create: `tests/test-quickshell-lockscreen-runtime-polish.sh`
- Modify: `tests/test-bibata-cursor-migration.sh`

**Interfaces:**
- Produces: failing contracts for picker suspension, compact editor drawers, compact Awtarchy edit/subsections, no cursor selector in FlyoutSettings, and per-cell pointer deformation.

- [ ] **Step 1: Write failing tests before production edits**
- [ ] **Step 2: Run focused tests and verify RED**

Run: `bash tests/test-quickshell-lockscreen-runtime-polish.sh && bash tests/test-bibata-cursor-migration.sh`
Expected: at least the new runtime-polish assertions fail against the current branch.

### Task 2: Awtwall picker suspend/resume

**Files:**
- Modify: `config/quickshell/awtarchy/LockscreenEditor.qml`
- Preserve: `config/hypr/scripts/quickshell_lockscreen_wallpaper_picker.sh`
- Test: `tests/test-quickshell-lockscreen-runtime-polish.sh`

**Interfaces:**
- Produces: `pickerSuspended` editor state and suspend/resume functions that preserve draft/history/selection state.

- [ ] **Step 1: Add picker-suspended state and helpers**

Hide the editor window and release its overlay without invoking `close()`; after picker exit, restore the same screen, reclaim overlay, and refocus the editor.

- [ ] **Step 2: Keep returned-path handling draft-only**

A valid returned path updates only draft wallpaper state; cancellation leaves draft unchanged.

- [ ] **Step 3: Run focused regression**

### Task 3: Compact lockscreen editor dock

**Files:**
- Modify: `config/quickshell/awtarchy/LockscreenEditor.qml`
- Test: `tests/test-quickshell-lockscreen-runtime-polish.sh`

**Interfaces:**
- Produces: one content-driven base dock plus mutually exclusive `Element`, `Layout`, `Background`, and `Weather` drawers opening upward.

- [ ] **Step 1: Replace fixed 282/432 px control slab with compact base row**
- [ ] **Step 2: Move secondary controls into mutually exclusive drawers**
- [ ] **Step 3: Keep Save/Cancel and position/scale/undo controls immediately accessible**
- [ ] **Step 4: Run focused editor tests**

### Task 4: Consolidate Awtarchy Quick Settings cell

**Files:**
- Modify: `config/quickshell/awtarchy/QuickSettings.qml`
- Modify: `config/quickshell/awtarchy/FlyoutSettings.qml`
- Modify: `tests/test-bibata-cursor-migration.sh`
- Test: `tests/test-quickshell-lockscreen-runtime-polish.sh`

**Interfaces:**
- Produces: compact Awtarchy header with `Edit`; independent expandable Cursor and Lockscreen subsections; no generic-cog cursor selector.

- [ ] **Step 1: Add Awtarchy edit-mode state and compact header**
- [ ] **Step 2: Place `CursorThemeSettings` only in the Cursor subsection**
- [ ] **Step 3: Keep all existing lockscreen state controls under Lockscreen subsection**
- [ ] **Step 4: Remove `CursorThemeSettings` from `FlyoutSettings.qml` and update tests**
- [ ] **Step 5: Run cursor and Quick Settings regressions**

### Task 5: Gooey per-block pointer deformation

**Files:**
- Modify: `config/quickshell/awtarchy/LockPreviewScene.qml`
- Modify matching secure presentation source required by parity tests.
- Test: existing lockscreen effects/parity tests plus `tests/test-quickshell-lockscreen-runtime-polish.sh`

**Interfaces:**
- Produces: per-filled-cell pointer/click targets with local neighbor blending and bounded smooth return; formation and audio controls remain independent.

- [ ] **Step 1: Replace shared connected-group pointer target with cell-local radial target**
- [ ] **Step 2: Blend local orthogonal-neighbor targets at a smaller weight**
- [ ] **Step 3: Preserve displacement caps, formation gating, and idle timer behavior**
- [ ] **Step 4: Keep secure/editor presentation parity byte-identical where required**
- [ ] **Step 5: Run focused physics/effects/parity tests**

### Task 6: Managed history and broad validation

**Files:**
- Modify: `local/share/awtarchy/quickshell-managed-history.sha256` only as required by existing managed-history tooling/tests.
- Modify affected tests/workflow expectations only when behavior intentionally changed.

- [ ] **Step 1: Run changed Bash syntax and ShellCheck checks**
- [ ] **Step 2: Run all lockscreen, cursor, Quick Settings, managed-history, and runtime-stress focused tests**
- [ ] **Step 3: Run full Validate Awtarchy workflow on exact head**
- [ ] **Step 4: Re-read `LockAuth.qml` and secure lock ownership to prove unchanged auth authority**
- [ ] **Step 5: Record exact candidate SHA and provide `awtarchy git update --branch feature/lockscreen-interactive-effects --commit <sha>` only after CI is green**
