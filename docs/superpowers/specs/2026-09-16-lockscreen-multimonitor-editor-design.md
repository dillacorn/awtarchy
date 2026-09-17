# Lockscreen Multi-Monitor Editor Design

## Goal

Extend the existing Quickshell lockscreen editor so edit mode previews the real lockscreen composition on every connected display, while preserving shared-by-default behavior and allowing optional complete visual configuration overrides per display.

This design extends `docs/superpowers/specs/2026-09-16-lockscreen-media-editor-polish-design.md`. The existing media renderer, editor manipulation behavior, secure lock ownership, and authentication architecture remain the baseline unless explicitly changed below.

## User-facing behavior

### All-display preview

Opening the lockscreen editor must show a lockscreen preview on every currently connected Quickshell display.

One display is the active editing target. Its editor window owns keyboard focus, the settings UI, direct element manipulation, and save/cancel shortcuts. Every other display remains a live, non-interactive preview of the configuration that would actually be used on that display when the session locks.

The initial active editing target is the currently focused display. The editor must expose a monitor selector that can switch the active editing target without closing the editor.

Secondary displays must not merely mirror the active draft when they have an individual override. Each preview resolves its own effective configuration through the same shared/override resolution model used by the secure lockscreen.

### Shared configuration

Existing lockscreen state remains the shared/default configuration.

Every display uses the shared configuration unless that display has an explicit individual override. Existing users with no monitor override state must see exactly the current behavior.

Editing the shared configuration updates every preview whose display still uses Shared mode. Displays with individual overrides remain unchanged.

The editor must make the active display's mode visible, for example `DP-1 · Shared` or `DP-1 · Individual`.

### Individual configuration

The editor must provide an explicit `Use Individual Configuration` action for the active display.

Enabling it clones the active effective shared configuration into a new override for that display. The display must therefore look identical immediately before and after the mode switch; it simply becomes independently editable afterward.

An individual override controls the complete visual configuration that the lockscreen editor owns for that display, including:

- built-in element layout and transforms;
- built-in element visibility;
- custom media elements;
- custom text elements;
- timezone clock elements;
- visualizer configuration;
- background mode and color;
- wallpaper/media path, fit, and focal point;
- background opacity;
- blur amount and blur style;
- overlay mode and strength;
- persisted element color choices, including `auto`; derived Auto Contrast colors are calculated per monitor and are not separately persisted;
- weather units used by the lockscreen scene;
- logo spawn animation;
- entry transition and duration;
- password mask presentation;
- clock format;
- any editor-owned visual fields added to the same lockscreen profile in this feature branch.

Authentication state, PAM ownership, lock ownership, passwords, and unrelated global shell/performance/input settings are never per-monitor configuration.

### Return to shared

The editor must provide `Use Shared Configuration` for a display that currently has an individual override.

Selecting it removes that display's override from the draft. Its preview immediately resolves back to the current shared draft.

This action must not mutate the shared configuration.

### Copy configuration

The active display must expose `Copy Configuration To…`.

Targets are currently connected displays other than the source display, plus an `All Other Displays` action when more than one target exists.

Copying clones the source display's current effective visual configuration into an individual override for each selected target. The source configuration is not changed.

A copy to a target that already has an individual override replaces that target override atomically in the draft.

Copying from a Shared source still creates an Individual target override containing a snapshot of the current shared draft. Later edits to Shared therefore do not alter that copied target until the target returns to Shared mode.

Copy operations participate in the editor's unsaved draft. They are not persisted until `Ctrl+S` succeeds.

## Shortcut and close behavior

`Super+Alt+E` is a toggle for the lockscreen editor.

- editor closed: open the editor with the focused display as the active editing target;
- editor open: cancel/close the editor through the same unsaved-draft discard path as `Escape`.

The binding must exist in both the normal Hyprland binding context and the `noalt` submap so entering that submap does not remove editor access.

`Escape` remains an alternate cancel/close path.

`Ctrl+S` atomically saves the shared configuration and all monitor overrides, then keeps the editor open as it does now.

The editor hint remains `Ctrl+S Save • Esc Cancel`; the direct toggle shortcut remains separately discoverable in Quick Settings.

## Persistence model

### Backward compatibility

The current top-level `lockscreen_*` state remains authoritative for the shared/default profile. Do not migrate existing state into duplicated per-monitor profiles.

Add one new bounded top-level object whose override entries use the same persisted field names and meanings as the shared profile:

```json
{
  "lockscreen_monitor_overrides": {
    "DP-1": {
      "lockscreen_layout": {},
      "lockscreen_show_logo": true,
      "lockscreen_show_time": false,
      "lockscreen_show_date": false,
      "lockscreen_show_username": false,
      "lockscreen_show_weather": false,
      "lockscreen_custom_images": [],
      "lockscreen_timezone_clocks": [],
      "lockscreen_custom_texts": [],
      "lockscreen_visualizer": {},
      "lockscreen_background": "black",
      "lockscreen_background_color": "#000000",
      "lockscreen_wallpaper_path": "",
      "lockscreen_wallpaper_fit": "cover",
      "lockscreen_wallpaper_focal_x": 0.5,
      "lockscreen_wallpaper_focal_y": 0.5,
      "lockscreen_background_opacity": 100,
      "lockscreen_background_opacity_previous": 100,
      "lockscreen_overlay_mode": "none",
      "lockscreen_overlay_strength": 0,
      "lockscreen_wallpaper_blur": 10,
      "lockscreen_blur_style": "pixelated",
      "lockscreen_weather_units": "auto",
      "lockscreen_animation": "split",
      "lockscreen_entry_transition": "fade",
      "lockscreen_entry_transition_duration": 1800,
      "lockscreen_password_mask_mode": "squares",
      "lockscreen_password_mask_character": "•",
      "lockscreen_clock_format": "24h"
    }
  }
}
```

The exact values above are illustrative defaults, not a second source of defaults. Normalization must reuse the same defaults and validation rules as the shared profile. The password element remains always visible under the existing editor validation and therefore does not gain a separate persisted visibility field.

Auto Contrast output is derived from each monitor's effective background/media and persisted element color choices. It must be recomputed for that effective profile where needed, not stored as a separate override field.

The object is keyed by the Quickshell/Hyprland output name used by the existing screen objects, for example `DP-1`.

Missing `lockscreen_monitor_overrides`, a non-present monitor key, or an empty override map all mean Shared mode.

Disconnected monitor overrides are retained. If the same output name reconnects later, its configuration becomes effective again. Copy targets and the editor monitor selector only expose currently connected displays.

### Profile completeness

Each stored override is a complete normalized snapshot of the editor-owned visual profile, not a sparse patch against Shared.

This is deliberate:

- Shared edits cannot accidentally leak into an Individual display.
- Copy semantics are deterministic.
- Removing an override has one simple meaning: resume Shared.
- Secure-lock and editor resolution do not need recursive merge rules.

When a future release adds another editor-owned visual field, state normalization must supply the shared default for older override objects that predate that field.

### Atomic save

The save helper must persist the shared profile and `lockscreen_monitor_overrides` under the same state-file lock/temporary-file replacement transaction used for lockscreen editor state.

Validation failure in any override must reject the save without partially modifying the shared profile or another monitor override.

The editor remains open and reports the save failure through the existing error/status path.

## Draft model

The editor session owns two logical draft layers:

1. one shared draft profile;
2. a map of complete per-monitor draft overrides keyed by output name.

The active editing target determines which profile the editing controls read and mutate:

```text
active monitor has override -> active override draft
otherwise                   -> shared draft
```

Every preview window resolves independently using its own monitor name:

```text
preview monitor has override -> that monitor's override draft
otherwise                    -> shared draft
```

Switching the active target must not reload persisted state or discard the current session draft.

Undo/redo and manipulation history must remain scoped to the draft session and must record enough target identity to avoid applying an edit to the wrong monitor profile after the active monitor changes. A history entry therefore needs to identify whether it belongs to Shared or to a specific monitor override.

## Shared profile API

Do not duplicate rendering logic between the editor and secure lockscreen.

Introduce a small profile-resolution boundary that can answer:

```text
sharedProfile(state) -> normalized visual profile
monitorOverrides(state) -> normalized map of output name -> visual profile
profileForMonitor(shared, overrides, monitorName) -> override if present, otherwise shared
```

The QML representation may use equivalent functions/properties rather than these exact function signatures, but there must be one clear resolver contract consumed by both preview and secure lock surfaces.

The resolver returns visual configuration only. Authentication and `WlSessionLock` lifecycle are outside this boundary.

## Secure lockscreen behavior

Each secure lock surface resolves the profile for its own output name before binding visual state into `LockScene`.

This resolution must affect only presentation. It must not change when or whether `WlSessionLock` secures the session.

Per-monitor backgrounds may independently use still images, GIFs, or MP4 video. Existing silent looping playback, video pre-roll, bounded readiness fallback, blur, pixelation, overlays, and transitions remain applicable per surface.

If two monitors use different videos, each surface owns its own media playback/readiness lifecycle. A slow or failed media decode on one monitor must not weaken authentication, unlock another surface, or prevent lock ownership.

## Editor rendering and interaction

The existing secondary `Variants { model: Quickshell.screens }` approach remains the basis for displaying all monitors.

The active display is interactive and focusable. Secondary preview windows remain non-focusable and non-interactive to avoid multiple keyboard owners and duplicate editor toolbars.

When the active monitor changes, the interactive editor window retargets to the selected display while all other displays continue to show their effective previews. The editor must preserve the current unsaved draft during this retargeting.

Direct manipulation, element selection, drawers, and settings operate on the active profile only.

Shared-mode edits should repaint every Shared preview immediately. Individual-mode edits should repaint only the active Individual preview unless another display independently has an identical override by coincidence.

## Monitor topology changes while editing

A display connected while the editor is open appears as a preview using Shared mode unless a retained override already exists for its output name.

A display disconnected while editing disappears from the preview/selector but its draft override remains in the session and can still be saved. If the active editing target disappears, the editor selects another connected display, preferring the currently focused display and otherwise the first available Quickshell screen.

The editor must not crash or discard unsaved work when monitor topology changes.

## Security invariants

- `WlSessionLock` remains the sole secure lock authority.
- `LockAuth.qml` remains the PAM/authentication owner.
- No monitor profile contains secrets or authentication state.
- Editor visibility and media readiness never determine whether the session is securely locked.
- Per-monitor media remains inside the secure Quickshell lock surface.
- Cancelling the editor never writes draft state.
- Saving validates all profiles before replacing persisted state.

## Validation

Permanent automated contracts must cover at least:

- existing state with no override object resolves identically to current Shared behavior;
- all connected displays receive editor preview windows;
- the focused display becomes the initial active editing target;
- changing active monitor preserves the unsaved session draft;
- Shared edits update all Shared previews;
- enabling Individual clones the current effective profile without a visual reset;
- Individual edits do not alter Shared or another monitor override;
- returning to Shared removes only the selected monitor override;
- copying to one monitor creates/replaces exactly that target override;
- `All Other Displays` copies to every connected target without mutating the source;
- copying from Shared creates an independent snapshot;
- disconnected overrides are retained;
- monitor topology changes do not discard the draft;
- invalid override data rejects the entire save atomically;
- `Ctrl+S` saves shared plus override state and keeps the editor open;
- `Escape` cancels without persistence;
- `Super+Alt+E` toggles open/cancel-close;
- `Super+Alt+E` is bound in the normal Hyprland context and `noalt` submap;
- secure lock surfaces resolve their own monitor profile through the same resolution contract;
- per-monitor still/GIF/MP4 configuration preserves the existing media pipeline and never affects lock/auth ownership;
- existing lockscreen tests remain green.

Runtime acceptance on Hyprland must verify at minimum:

- every physical monitor shows its actual effective preview while editing;
- switching the active editor target is visually stable;
- Shared and Individual modes visibly match the secure lockscreen after locking;
- copying configurations produces the expected result on the target displays;
- mismatched monitor sizes/orientations can retain independent layouts;
- animated media remains silent and smooth on each configured display;
- `Super+Alt+E` opens and closes the editor in both normal and `noalt` contexts;
- `Ctrl+S` and `Escape` retain their tested behavior;
- PAM/unlock behavior and multi-monitor session-lock security remain unchanged.

## Non-goals

- Multiple simultaneously focusable editor toolbars/windows.
- Per-monitor authentication behavior.
- Sparse/inherited override patches.
- Automatic deletion of overrides for disconnected monitors.
- Automatic matching of renamed physical monitors to old output names.
- External media renderers such as mpv/mpvpaper/awww/hyprpaper.
