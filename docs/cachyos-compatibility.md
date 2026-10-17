# CachyOS-specific Awtarchy behavior

Awtarchy targets a minimal Arch installation. CachyOS can supply additional
system-wide shell defaults that are not part of Awtarchy's configuration.

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

To opt out of that greeting, edit the existing
`~/.config/fish/config.fish` and define an empty function **after** the
CachyOS configuration has been sourced:

```fish
function fish_greeting
end
```

The CachyOS template may already have a commented-out `fish_greeting`
example; uncommenting its definition and matching `end` is preferable to
adding a duplicate. Preserve the rest of the user's Fish configuration.
A new interactive Foot/Fish window is enough to verify the greeting change.

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
