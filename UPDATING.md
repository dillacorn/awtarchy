# Updating Awtarchy

Use the installed `awtarchy` maintenance command for normal updates. Do not reclone the repository or rerun the full installer for routine upgrades.

## Update to the latest stable release

```bash
awtarchy update
```

Stable update/reset/review operations target published Awtarchy releases. The maintenance command/runtime itself can refresh from `main` independently so updater-only fixes do not require a new configuration release. Changes to release-managed configuration are available to normal stable updates only after a new published stable release includes them; editing release notes does not change the configuration payload users receive. Optional package choices remain separate.

When a Hyprland package upgrade is detected after you approve the config update, Awtarchy offers a **separate, optional full system upgrade** before changing managed files. It never installs Hyprland alone or upgrades the system without an interactive yes/no response. This uses Awtarchy's existing NVIDIA/kernel rollback safeguards, but a managed-config rollback does not reverse a system package upgrade. For a fresh, read-only upgrade check, install `pacman-contrib` (which provides `checkupdates`); otherwise Awtarchy consults the local pacman database, which might be stale. On Arch and CachyOS, use full system upgrades instead of partial package upgrades.

After updating, Awtarchy warns if the running Hyprland session may still be using an older compositor. Log out and log back in to activate the installed version. A full reboot may be needed separately for kernel or graphics-driver changes. Hyprland configuration errors still trigger the usual managed-file rollback, since restarting cannot fix invalid configuration.

## Review changes before applying them

```bash
awtarchy review
```

This previews release-managed configuration differences without applying the update.

Awtarchy intentionally distinguishes user-owned files/state from release-managed files. Normal updates preserve selected user configuration such as `hyprland.lua` according to the current updater policy and create backup files when managed local edits are overwritten.

## Reset managed configuration

```bash
awtarchy reset
```

Use reset when you intentionally want Awtarchy-managed configuration returned to the published release defaults. Review the updater prompts and backups rather than treating reset as a generic system wipe.

## Check installed/update state

```bash
awtarchy version
```

Awtarchy tracks maintenance-command/runtime state separately from managed configuration release state. The version output also shows Git-testing state when active.

## Test unreleased work

```bash
awtarchy git
```

`awtarchy git` is the explicit Git-testing path for an unreleased remote branch or exact branch commit. Git-testing remains separate from stable published release state; a repository branch is not treated as a stable release tag.

Use `awtarchy update` to return from Git-testing to the normal stable release path.

## Other maintenance commands

```text
awtarchy clean-backups   Review and clean Awtarchy backup files
awtarchy help            Show the full command list
```

For a fresh machine or intentional full reinstall, use [INSTALL.md](INSTALL.md).
