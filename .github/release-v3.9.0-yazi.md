# Awtarchy v3.9.0 Yazi

Awtarchy v3.9.0 is a Yazi-focused release that improves tab organization, mouse workflows, context menus, file information, selectable text handling, and archive dependency delivery.

## Install and update

- New installation: [INSTALL.md](https://github.com/dillacorn/awtarchy/blob/main/INSTALL.md)
- Existing Awtarchy users: [UPDATING.md](https://github.com/dillacorn/awtarchy/blob/main/UPDATING.md) or run `awtarchy update`.

## Yazi improvements

- Left-drag tabs to reorder them; numbered tab navigation follows the new order.
- Right-click a tab to switch to it and open Yazi's native interactive rename prompt.
- `Ctrl+A` now uses native selection inversion: it selects all from an empty selection and inverts an existing selection.
- `i` toggles file information like Tab, including closing the information view with `i`.
- Right-click menus are action-only instead of duplicating clipped shortcut directions; keyboard guidance stays in native Yazi Help.
- Context menus add **Help** and **Open PCManFM-Qt here**.
- Mouse-wheel scrolling works in Yazi Help while ordinary manager and preview scrolling retain native behavior.
- Selectable text mode accepts either Enter or Esc to return to Yazi through a POSIX-compatible terminal-state-safe input path.
- Stable install/update paths now guarantee the required Arch `7zip` dependency before managed Yazi ZIP actions are applied.

## Validation

- PR #266 passed every triggered workflow on final feature head `fe280f2532cd6d67446de19c468096a6171bbef9`, including the full **Validate Awtarchy** workflow, package reconciliation, stable release-note validation, PolicyKit, and relevant Quickshell regressions.
- Exact release target `1b998a7d1e8a3329f8672672799c803b8f7e97e3` passed all 12 triggered post-merge `main` workflows, including the complete **Validate Awtarchy** integration suite.
- The Windows WGDot implementation of the shared native Yazi interaction design was maintainer runtime-tested and approved before the same native tab/context behavior was ported to Awtarchy; Awtarchy-specific Linux paths remain covered by repository validation rather than a separate Linux runtime claim.
