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

## Keyboard shortcut parity audit

Audited against `config/hypr/hyprland.lua` on this branch. Native-key
equivalence is separate from tested runtime success. Sway's `outputs` and
`../workspaces` includes can be user-modified; Umbriel's generated
`migrated.toml` loads after its native profile, but skips reserved keys.
These are source-contract findings, not proof of personalized live binds.

| Hyprland shortcut family | Sway | Umbriel |
| --- | --- | --- |
| Launcher Alt+P / Super+D; Super+Shift+Space as extra alias | Quickshell, no Fuzzel | Quickshell, no Fuzzel |
| Power, clipboard, notifications, theme, browser, terminal, file manager | Adapted Quickshell/Foot | Adapted Quickshell/Foot |
| Super+Alt+E lockscreen layout editor; Super+Alt+Equal/Minus output brightness | Adapted compositor-local IPC and Sway-aware DDC | Adapted compositor-local IPC and Umbriel-aware DDC |
| Super+W/Shift+W/Ctrl+W/Alt+W wallpaper picker/random variants | Awtwall via packaged-binary preference | Awtwall via packaged-binary preference |
| Window focus/move arrows + hjkl; numbered workspaces, transfers, display moves | Native Sway (including Ctrl+Shift+brackets) | Native Umbriel (including Ctrl+Shift+brackets) |
| Alt/Super+Ctrl window resize; Alt+Y/O/U/I; Super equivalents in noalt | Native shrink/grow 30 px | Divider-direction-aware Dwindle helper; native fractional floating resize |
| Alt+Shift+R / Super+Shift+R flip focused split | `split toggle`; explicit reload moved to Super+Alt+Shift+R | `layout-toggle-split` |
| Alt+R / Super+R Hyprland `swapsplit` | Approximate `split toggle`, not child-swap parity | No exact native child-swap shortcut |
| Alt+Tab, floating/fullscreen, scratchpad, pinned, window switching | Native or Sway-only helper, geometry differences | Native or Umbriel helper, geometry differences |
| Default/noalt/mouse/vm modes | Native Sway modes; Alt-mouse still required in mouse mode | Native Umbriel submaps; Alt-mouse still required in mouse mode |
| Media keys | Native playerctl; lacks Hyprland Spotify/YTM play-pause priority | Native playerctl; lacks Hyprland Spotify/YTM play-pause priority |
| Hypr-specific Hyprbars, color picker, shader vibrance/sunset, zoom, workspace mixing, GIF, QR and debug keys | **Not ported**; no invented unsafe stand-ins | **Not ported**; no invented unsafe stand-ins |
| Hyprland power-menu-fast raw-key submap | Quickshell power menu; exact raw-key sequence unverified | Quickshell power menu; exact raw-key sequence unverified |

Retired Fuzzel is deliberately excluded from the Sway/Umbriel installer
package lists, setup prerequisites and keybindings. Historical cleanup
and obsolete-package references in the Awtarchy updater remain intentional.
Live validation must still confirm the Quickshell editor, wallpaper, resize
repeats, mode transitions, display-targeted DDC and effective includes.

Before any new compositor release, audit all Hyprland-generated bindings,
include order, UI controls and compositor-specific limitations per `AGENTS.md`.
Umbriel's `migrated.toml` is read AFTER `config.toml`; imported shortcuts
must not replace the native Awtarchy-owned hotkeys.
