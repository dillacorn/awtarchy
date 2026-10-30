# Awtarchy v4.1.4 Qalc

Restores Qalc's native terminal interface and improves the Hyprland update experience.

## Install and update

- [Installation guide](https://github.com/dillacorn/awtarchy/blob/main/INSTALL.md)
- [Updating guide](https://github.com/dillacorn/awtarchy/blob/main/UPDATING.md)
- Existing installations: `awtarchy update`.

## Qalc

- Runs native `qalc -s 'autocalc on'` inside Foot instead of the custom Python interface. Normal terminal scrollback and calculation history are available again.
- Preserves existing calculator hotkeys, floating-window behavior, and dimensions.

## Hyprland

- When a package upgrade postpones managed-config updates, Awtarchy can reopen the interactive update once after a new Hyprland login.
- The startup hook must already be installed; customized configurations without the hook retain the safe manual second-pass update. No packages or configs are applied without normal user approval.

## Maintenance

- Corrects the Default Applications desktop launcher's freedesktop Exec validation.
- Fixes ShellCheck annotations for indirectly invoked USB-security test stubs.

## Validation

- Native Qalc launcher, deferred Hyprland resume, managed-history, and release-note contract checks passed in CI.
- The ShellCheck stage passed after the USB test annotation correction.
- Live automatic update resumption after Hyprland login has not yet been tested on a desktop.
