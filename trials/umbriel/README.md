# Umbriel feasibility and Awtarchy configuration portability

Status: **investigation only**. This branch starts from Awtarchy's `main`,
independent of the isolated KWin trial branch. Do not ship an Umbriel
compositor menu choice, install a session entry in Ly, or modify any of the
working Hyprland, Sway, KWin, Quickshell, GPU, or XDG portal configurations.

## Initial read-only inspection

From a checkout of this branch:

```bash
python3 trials/umbriel/preflight.py
python3 tests/test-umbriel-preflight.py
```

The survey reads local DRM vendor IDs, local pacman metadata (without
syncing), and standard Wayland session file names. It does not check AUR
build success, nor does vendor detection establish feature support.

## Packaging and session gates

- Upstream: https://github.com/noctalia-dev/umbriel
- Installation: https://docs.noctalia.dev/umbriel/installation/
- Native launch command documented upstream: `start-umbriel`, not a bare
  `umbriel` login command. Preserve upstream's managed `umbriel.service`
  and startup environment handling rather than inventing an alternate
  launcher or a competing service.
- CachyOS currently publishes an `umbriel` binary package in its
  `cachyos` repository. A package being visible upstream is not proof
  that it is available in the user's configured sync databases; check
  `pacman -Si umbriel` first.
- Upstream documents AUR `umbriel-git` for Arch. AUR build reliability
  is not established. Do not treat the independently named `umbriel` AUR
  entry as the CachyOS official binary package.
- If an Umbriel test is approved later, require an explicit opt-in, a
  dedicated session, an exact-file rollback ledger, and preservation
  of any custom Ly `waylandsessions` directory. Never create
  duplicative package-owned entries, mutate existing Hyprland/Sway
  session launchers, or remove another compositor.
- Check exact installed package files, paths, version, service units,
  and portals before writing installation scripts. Portal
  `xdg-desktop-portal-umbriel` may need independent packaging.

## GPU and gaming evidence gates

Awtarchy should expose *observed* capabilities rather than a brand-based
promise of support:

1. Inventory GPUs, DRM primary/render nodes, kernel drivers, Xwayland,
   compositor backend, and which card drives each output. Hybrid
   systems require per-card distinction.
2. Check explicit-sync protocol/runtime behavior, fullscreen VRR,
   tearing (asynchronous presentation), direct scanout, HDR, and
   fullscreen focus transitions separately. A supported config key
   is not sufficient proof of functional support.
3. Verify AMD, Intel, NVIDIA proprietary and hybrid configurations.
   Never inject NVIDIA workarounds for all machines or default to
   enabling tearing without measured behavior and a per-device opt-in.
4. Validate both per-output workspace ownership and the
   display/hotplug remapping model before applying the current
   Awtarchy workspace UI.
5. Gate shell integration behind a compositor-specific adapter for
   workspace state, focus, windows, monitor geometry, screenshots,
   session lock, capture, and notifications. Reuse the existing
   Awtarchy Quickshell UI; do not install Noctalia as a dependency.

## Portable Awtarchy configuration: separate from compositor support

User goal: GPU-aware configuration controls and one-machine-to-another
export/import. This is valuable even if Umbriel is never installed.
Prototype it independently in a follow-on feature branch before wiring
UI controls or migration hooks into the Awtarchy installer.

Proposed safety contract:

1. **Inventory sources**: distinguish tracked managed defaults,
   user-customized settings under `~/.config`, persistent shell state,
   and the installed command/config version metadata. Do not blindly
   export `~/.config` or caches.
2. **Explicit scopes**: shell appearance/widgets; launchers/keybinds;
   wallpapers/assets; compositor settings; outputs/workspaces; optional
   application preferences. Preserve per-host settings separately.
3. **GPU configurator**: show detected devices and available relevant
   options; distinguish current state, compatible settings, untested
   suggestions, and settings requiring logout. Never write unverified
   driver/Xorg/DRM environment flags on import.
4. **Export**: generate a versioned manifest, relative file paths,
   integrity hashes, and a reviewable, local archive. Omit credentials,
   keys, tokens, secrets and volatile IPC/session paths by default;
   provide an explicit redaction report. Warn that commands/hooks and
   user-authored custom fields can contain undiscovered secrets.
5. **Preview before import**: reject traversal, links escaping the
   archive, dangerous file types, unexpected destinations and version
   mismatches. Show conflicts and unsupported components, including
   missing programs, outputs, fonts, and hardware.
6. **Apply carefully**: never replace personal files without explicit
   confirmation; stage privately, make recoverable backups, preserve
   file ownership/modes, validate syntax before activating, and allow
   rollback. Per-host monitor/output mapping is always previewed.
7. **No cross-compositor guessing**: export the original configuration
   along with its compositor identity. Do not assume a Sway keybind,
   Hyprland Lua option or Umbriel TOML key is interchangeable.
8. **Security boundary**: no implicit upload, sync account, telemetry,
   remote execution, encrypted-secret export, or cloud requirement.

Noctalia's reference design keeps user-authored TOML separate from GUI
overrides, supports configuration validation and merged export, and warns
about credentials (see
https://docs.noctalia.dev/noctalia/configuration/). Copy the *principles*,
not Noctalia's application-specific schema or binaries.

## Next milestones

- Read-only packaging and hardware inventory (this branch)
- Per-compositor adapter contracts based on real Umbriel IPC output
- Offline config parser and renderer tests against a pinned upstream
  revision, no installation side effects
- Reversible Ly/TTY smoke launcher once installation paths and hardware
  reliability are verified
- Full Awtarchy Quickshell integration and GPU gaming validation
- Separately, implement export/validate/preview/import as a
  compositor-independent Awtarchy feature

Keep KWin work on `KWinWM_Migration_Trial_Investigation` and the
production compositor choices on `main` unchanged.
