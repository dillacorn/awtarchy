# CachyOS-specific Awtarchy behavior

**CachyOS is an officially supported Awtarchy base starting with v4.1.0.**
Vanilla Arch Linux remains recommended. Community testing has verified a CachyOS
desktop with NVIDIA graphics, Ly login, working networking, Quickshell, and Yazi.
Laptop power handling and some unusual existing-system configurations have not
had comparable hardware coverage. See the [installation guide](../INSTALL.md).

Awtarchy respects existing CachyOS drivers, network/DNS services, display
managers, and desktop files where possible. CachyOS also supplies shell defaults
that are different from a minimal Arch installation.

## Fastfetch when opening Foot

CachyOS's `cachyos-fish-config` provides a `fish_greeting` function in
`/usr/share/cachyos-fish-config/cachyos-config.fish` that runs `fastfetch`.
The CachyOS `~/.config/fish/config.fish` template sources this file. When
Fish is the user's default interactive shell, opening Foot with
`Super+Enter` therefore displays Fastfetch even though Awtarchy's
Hyprland shortcut launches only `foot`.

This is expected behavior from the installed Fish setup, not a Foot startup
command configured by Awtarchy. Do **not** change package-owned files under
`/usr/share`, replace the user's shell, or overwrite their Fish config
during an Awtarchy update.

Awtarchy now handles the **unmodified CachyOS Fish user template**
automatically during installation and after a successful configuration
update. When Fish is the login shell and the system's CachyOS greeting
still runs Fastfetch, the helper:
- recognizes the original user template and CachyOS vendor greeting;
- saves the exact original as `~/.config/fish/config.fish.backup.TIMESTAMP`;
- appends an empty user `fish_greeting` function, so opening Foot is quiet.

It does not remove Fastfetch, change `~/.config/fastfetch`, modify
`/usr/share`, change the login shell, or touch Fish files with custom
active commands or existing greeting overrides. Re-running the updater
does not repeat the edit or create extra backups.

On an existing installation, run `awtarchy update` to apply the latest published
Awtarchy configuration. The maintenance runtime can refresh from `main` separately.

Custom Fish configurations are deliberately preserved. Users with
customized startup files who also want to disable their greeting can add
this function at the end of `~/.config/fish/config.fish`:

```fish
function fish_greeting
end
```

Open a new Foot window to confirm the change; running `fastfetch`
manually still uses the installed Awtarchy appearance.

References:

- [CachyOS Fish default greeting](https://github.com/CachyOS/cachyos-fish-config/blob/main/cachyos-config.fish)
- [CachyOS Fish user config template](https://github.com/CachyOS/cachyos-fish-config/blob/main/config.fish)

## Quickshell bar wheel direction

Awtarchy's `config/quickshell/awtarchy/BarButton.qml` handles brightness
and volume scrolling. Its normalized pixel-based wheel events should follow
the same sign convention as angle-based wheel events: positive is up,
negative is down. A separate Awtarchy change corrects double inversion of
the pixel path.

Qt/Wayland commonly omits pixel deltas for conventional wheel hardware.
If a CachyOS user's mouse still scrolls brightness/volume backward after
that correction, **do not** invert system mouse settings blindly. Confirm
the received Qt wheel event directions and whether the mouse uses pixel
or angle deltas before proposing a device-specific workaround.

- [Qt WheelEvent semantics](https://doc.qt.io/qt-6/qml-qtquick-wheelevent.html)
- [Quickshell wheel investigation](https://github.com/dillacorn/awtarchy/issues/286)

## NVIDIA cursor handling

During installation and configuration updates, Awtarchy configures Hyprland's
`cursor.no_hardware_cursors` according to detected GPU hardware. NVIDIA systems
(including hybrid NVIDIA + Intel/AMD systems) use `1` (software cursor); AMD/Intel-only
systems use `2` (automatic). When GPU detection is inconclusive, the existing
cursor setting is retained when available. Personal Hyprland configurations
continue through Awtarchy's usual update backup and rollback handling.
