# Awtarchy v4.0.1 Yazi Workspaces & Updater Fix

Awtarchy v4.0.1 brings persistent, reusable Yazi workspaces to Arch Linux, installs Yazi by default, and resolves the Foot migration error affecting regular updates from v4.0.0.

## Install and update

- New installations: [INSTALL.md](https://github.com/dillacorn/awtarchy/blob/main/INSTALL.md).
- Existing installations: [UPDATING.md](https://github.com/dillacorn/awtarchy/blob/main/UPDATING.md), or run `awtarchy update`.

## Yazi workspaces

- Save, load, rename, and delete named Tab Groups, restoring tab directories, order, focus, and custom names without extra tabs.
- Pin tabs using `t p` or right-click, including unfocused tabs. Pins and renamed tab titles persist across Yazi sessions, independently of saved groups.
- Add session-only Quick Mark and updated shortcuts for bookmarks, recents, tab controls, and the quit chooser.
- Include Yazi in the default Arch package selection and restore missing Yazi installations during Awtarchy updates.

## Updater reliability

- Fix updates from the v4.0.0 archive when the Foot migration helper is missing. Preserved Hyprland configurations retain personal changes while known legacy Alacritty shortcuts migrate to Foot.

## Validation

- Yazi PR [#280](https://github.com/dillacorn/awtarchy/pull/280) passed all 23 pre-merge GitHub Actions workflows; the new functionality was tested successfully on an Arch/Foot system.
- Foot updater PR [#281](https://github.com/dillacorn/awtarchy/pull/281) passed all 22 GitHub Actions workflows; the affected normal `awtarchy update` path was verified on the user's system.
