# Awtarchy v3.8.3

Makes the persistent Floating Windows spawn mode harder to trigger accidentally while preserving the VM-specific active-window float shortcut.

## Install and update

- New installation: [INSTALL.md](https://github.com/dillacorn/awtarchy/blob/main/INSTALL.md)
- Existing Awtarchy users: [UPDATING.md](https://github.com/dillacorn/awtarchy/blob/main/UPDATING.md) or run `awtarchy update`.

## Changes

- Removed the normal and `noalt` `Super+Alt+F` shortcut for persistent global floating-spawn mode.
- Persistent Floating Windows mode now remains an intentional Quick Settings/bar action.
- Preserved `Super+F` for focused-window floating and VM `Super+Alt+F` for active-window floating.
- Updated Floating Windows UI/notification text and regression coverage to make that ownership explicit.

## Validation

- PR #248 passed the full Validate Awtarchy workflow and all triggered checks, including Floating Windows and Submap Persistence validation.
- Stable release-note validation is required before publication and is re-run against the published release body.
