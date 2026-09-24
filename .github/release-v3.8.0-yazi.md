# Awtarchy v3.8.0 Quickshell

Awtarchy v3.8.0 is the biggest Yazi-focused update to the dots so far, bringing the expanded mouse-and-keyboard file-management workflow to Arch while preserving Linux-native behavior and stable Yazi APIs.

## Install and update

Fresh installation: [INSTALL.md](https://github.com/dillacorn/awtarchy/blob/main/INSTALL.md)

Existing Awtarchy installations and stable updates: [UPDATING.md](https://github.com/dillacorn/awtarchy/blob/main/UPDATING.md)

Quick update:

```bash
awtarchy update
```

## Yazi

- Mouse-first navigation now supports first-click selection, second-click open/enter, middle-click new tabs, selection-aware context menus, drag-to-folder copy/move, and keyboard parity for the same core actions.
- Persistent bookmarks and recently opened items use real local collection folders under Yazi state. `g b` and `g r` enter those collections, markers resolve safely to their real targets, deleting collection markers never deletes the real target, stale entries are pruned lazily on activation, and history is bounded to 1000 entries.
- Preview handling now uses Yazi's native `app:resize` reflow path. `m v` hides/shows preview, `m x` maximizes/restores it, clickable bottom controls teach those shortcuts directly, text wraps to the new width, and redundant forced preview regeneration is avoided.
- `m c` works directly on highlighted text-like files and suspends Yazi into a Linux-native plain-text terminal view. Mouse selection remains available, Alacritty copies with Ctrl+Shift+C, and Enter returns to Yazi.
- Yazi now includes clickable breadcrumbs, `Ctrl+F` name/content search, a safer delete chooser, direct tab shortcuts, Git status signs, PolicyKit-backed mount handling, task feedback, square managed styling, and clearer active-command header coloring.
- Awtarchy's updater now detects same-user Yazi processes when the planned update will change managed Yazi config. It asks `Close Yazi and continue? [Y/n]`, verifies Yazi exited before managed writes, and cancels before partial writes if consent is refused or termination fails.

## Validation

- Exact release target: `46eadde776a4d881507545968a69ef3cb5e2906e`.
- PR #230 passed all 23 exact-head checks before merge.
- All 15 post-merge `main` checks passed on the exact release target, including the stable-release-note contract and command/updater integration validation.
- Interactive Linux runtime behavior is not inferred from CI alone; the release target is automated-test/CI validated.

## Post-release updates

_Placeholder for possible tested post-release patches to v3.8.0._
