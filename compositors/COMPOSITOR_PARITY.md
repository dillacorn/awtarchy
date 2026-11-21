# Optional compositor parity inventory

Authoritative reference: `config/hypr/hyprland.lua`, its
`config/hypr/scripts/` helpers and `config/quickshell/awtarchy/`.
Entries below distinguish implementation from hardware/session confirmation.

| Function | Sway | Umbriel |
| --- | --- | --- |
| Optional session/install | Adapted | Adapted; experimental |
| Default/noalt/mouse/vm shortcuts | Native modes, adapted | Native submaps, adapted |
| Alt/Super+Ctrl window resize (arrows/hjkl) | Native 30px width/height shrink-grows in default/noalt modes; runtime verify | Dwindle uses live IPC to move an adjacent divider in the physical arrow direction from either side; floats and other layouts retain ±3% primary/secondary extent; runtime verify |
| btop, Wiremix and wdisplays floating/toggle | Sway IPC; runtime verify | Umbriel IPC; fixed imported-chord collision; runtime verify |
| Bar rotate/flip/autohide shortcuts | Quickshell control IPC; verify | Quickshell control IPC; verify |
| Bar Alt+left drag | Layer-shell; no continuous lift | Layer-shell, visual press feedback; verify |
| Launcher/clipboard/network/Bluetooth resize | Layer-shell, staged | Layer-shell, live; verify |
| Notification Center resize | Layer-shell, staged | Live, fixed edge anchor during drag; verify |
| Focus on hover | Native Sway policy | Native sloppy focus |
| Tiled-border drag without modifier | Compositor limitation | Compositor limitation |
| Hyprland pointer-only mouse submap | Alt drag required | Alt drag required |
| Global floating-only preference | Not equivalent | User verified working |
| Quickshell DDC brightness | Adapted | User verified working |
| Screen-share guard | Unsupported | Native Umbriel guard, user verified |
| Per-monitor bar/flyout state | Shared Quickshell manager | Shared Quickshell manager |
| Screenshot sounds and login audio | Private helper and exact managed MP3; runtime verify | Private helper and exact managed MP3; runtime verify |
| sched-ext Quick Settings | Shared trusted scheduler bridge; runtime verify | Shared trusted scheduler bridge; runtime verify |
| Window placement preview tint | Native Sway behavior | `colors.insert_hint` follows selected active border, 50% alpha; runtime verify |
| Personal file/config preservation | Managed | Managed checksum |

Before any new compositor release, audit all Hyprland-generated bindings,
include order, UI controls and compositor-specific limitations per `AGENTS.md`.
Umbriel's `migrated.toml` is read AFTER `config.toml`; imported shortcuts
must not replace the native Awtarchy-owned hotkeys.
