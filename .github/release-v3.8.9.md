# Awtarchy v3.8.9 Runtime Fixes

Awtarchy v3.8.9 completes a Hyprland Lua runtime cleanup and improves Sunshine/Moonlight integration, with fixes focused on predictable window, monitor, and streaming behavior.

## Install and update

- New installation: [INSTALL.md](https://github.com/dillacorn/awtarchy/blob/main/INSTALL.md)
- Existing Awtarchy users: [UPDATING.md](https://github.com/dillacorn/awtarchy/blob/main/UPDATING.md) or run `awtarchy update`.

## Hyprland runtime fixes

- Vibrance, workspace mix, zoom, Sunshine/Moonlight, and resize helpers now use Lua-native Hyprland runtime APIs instead of legacy keyword/text-dispatch paths.
- Workspace mix now restores saved floating and pseudo state explicitly, fixing the restore case that could leave tiled windows looking floating-sized.
- Steam monitor launch-option examples now use the Lua monitor API.

## Sunshine / Moonlight

- Awtarchy automatically adds its connect helper to Sunshine's global preparation commands when Sunshine is installed, while preserving existing Sunshine configuration and leaving service/autostart state unchanged.
- Adds Sunshine autostart controls to the Awtarchy maintenance menu and CLI. Enabling or disabling autostart affects future logins without starting or stopping Sunshine immediately.
- Allows `/usr/bin/sunshine` screencopy under Awtarchy's enforced Hyprland permissions, eliminating the capture permission prompt after the Hyprland session restarts.
- Optional-package guidance now points to LizardByte's official Arch repository instead of the unsupported AUR `sunshine-bin` package.

## Validation

- PR #264 passed all 30 triggered checks on final feature head `a0c46fa7b04e201649a2b2405b0817abfbb1bab6`, including the full **Validate Awtarchy** workflow and the managed-history regression that caught the final Hyprland config hash update.
- The maintainer runtime-tested the affected paths, including vibrance, workspace mix, zoom, a real Sunshine/Moonlight Steam Big Picture session, automatic Sunshine hook configuration, disabled-by-default autostart state, screencopy permission after logout/login, and a real DP-1 monitor mode switch/restore. The resize helper has no current user-facing caller; its Lua dispatcher path is covered by dynamic contract validation.
- Exact release target `bce758d19d1cf477407ae15ea8cab2f56fbf44c4` passed all 16 triggered post-merge `main` workflows, including **Validate Awtarchy**, **Validate Package Reconciler**, **Validate Screen Share Guard**, and the triggered Quickshell lockscreen validation.
