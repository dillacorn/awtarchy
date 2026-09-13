# Lockscreen Element System Pass 2 Design

## Scope

This spec implements issue #189 on draft PR #181. It extends the existing fixed six-element lockscreen editor into a backward-compatible element system with per-element opacity, generic transforms, and user-inserted local images. It does not implement the standalone audio visualizer or background transparency; those remain Pass 3 / issue #190 and will consume the generic transform model introduced here.

## Security boundaries

- `config/quickshell/awtarchy-lock/shell.qml` remains the sole `WlSessionLock` owner.
- `config/quickshell/awtarchy-lock/LockAuth.qml` remains the PAM/authentication owner and is not modified for element behavior.
- The real password `TextInput`, focus routing, submission, and authentication status remain in `LockSurface.qml`.
- Custom-image paths and presentation state never enter the authentication path.
- Password presentation cannot be hidden. Its opacity may be faded only to a safe minimum of 20%; the real authentication input/focus path remains unaffected.
- Custom images render behind the built-in lockscreen subjects so a user image cannot replace or cover the password presentation layer.

## Built-in transform model

The existing `lockscreen_layout` object remains the source of truth for Logo, Time, Date, Username, Weather, and Password. Existing saved layouts remain valid.

Each normalized built-in entry becomes:

```json
{
  "x": 0.5,
  "y": 0.5,
  "scale": 1.0,
  "stretch_x": 1.0,
  "stretch_y": 1.0,
  "opacity": 100,
  "color": "auto"
}
```

Defaults for missing fields are `scale=1.0`, `stretch_x=1.0`, `stretch_y=1.0`, `opacity=100`, and `color="auto"`. This preserves every existing saved `{x,y}`, `{x,y,scale}`, and `{x,y,scale,color}` layout.

Validation:

- overall `scale`: 0.50–2.00;
- `stretch_x` and `stretch_y`: 0.25–4.00;
- opacity: 0–100 for Logo/Time/Date/Username/Weather;
- Password opacity: 20–100;
- existing normalized position bounds remain unchanged;
- existing color validation remains `auto` or `#RRGGBB`.

The editor exposes uniform direct resize through the existing visual handle. Exact overall scale, horizontal stretch, vertical stretch, and opacity remain available as secondary precision controls.

## Custom image state

Custom images are persisted separately as `lockscreen_custom_images`, an ordered array with a hard maximum of 12 entries. A saved entry is:

```json
{
  "id": "image-<stable-id>",
  "path": "/absolute/local/image.png",
  "x": 0.5,
  "y": 0.5,
  "scale": 1.0,
  "stretch_x": 1.0,
  "stretch_y": 1.0,
  "opacity": 100,
  "visible": true
}
```

Requirements:

- `id` must be unique inside the array and match `image-[A-Za-z0-9_-]+` with a bounded length;
- `path` must be an absolute readable local file when it is persisted; persistence canonicalizes it with `readlink -f`;
- protocol/URL values, control characters, missing files, unreadable files, duplicate IDs, unknown keys, invalid transforms, and more than 12 images are rejected atomically;
- the secure shell re-normalizes persisted image objects and rejects non-absolute/protocol/control-character paths before passing them to the scene;
- if a previously valid file disappears later, the QML `Image` simply fails closed and renders nothing;
- custom-image opacity may be 0–100 and visibility may be toggled;
- array order is stable and defines image-to-image rendering order.

## Editor behavior

The editor builds its selectable element list from the six built-ins plus draft custom-image IDs. The same selection, drag, snapping, keyboard nudge, group movement, undo/redo, direct resize, and numeric positioning machinery must accept both categories.

Custom images use the same normalized center-position model and general safe bounds as non-password built-ins. Their selection frame tracks the rendered image footprint rather than a generic label box.

Selected-element controls:

- Built-ins: visibility where allowed, Reset Position, overall scale, Stretch X, Stretch Y, Opacity, position, and existing color controls.
- Password: Reset Position, overall scale, Stretch X, Stretch Y, Opacity with a 20% floor, position, and existing color controls; visibility remains required.
- Custom image: Visible, Remove Image, Reset Position, overall scale, Stretch X, Stretch Y, Opacity, and position. No text-color control is shown for images.

`Add Image` reuses the existing fullscreen Awtwall selection-only image picker. A selected path creates only a draft image. Save persists it; Cancel discards it. Removing an image is likewise draft-only until Save.

Undo/redo snapshots include custom images and all new transform fields.

## Scene behavior

`LockScene.qml` and the byte-identical unlocked `LockPreviewScene.qml` accept a `customImages` property.

The generic transform helpers provide:

- normalized position;
- overall scale;
- horizontal/vertical stretch;
- configured opacity;
- visibility;
- visual width/height for editor selection geometry.

Custom images render above the background/composition layer but below Logo/Time/Date/Username/Weather/password presentation. They use only local `file://` sources after path normalization.

Built-in opacity multiplies existing intentional stylistic alpha values instead of replacing them. Hidden items remain faded/selectable in editor mode, but saved opacity is still previewed.

## Persistence and atomic Save

`save-lockscreen-editor` is extended to persist `lockscreen_custom_images` in the same atomic state-file replacement as layout, visibility, background, wallpaper composition, and weather units. A malformed custom-image array or invalid new transform rejects the entire save without partial state mutation.

`reset-lockscreen-presentation` restores all built-in transform defaults and empties `lockscreen_custom_images`.

`BarState.qml` returns normalized defaults for missing new fields and an empty image array when legacy state has none.

## Pass 3 interface

Pass 3 will reuse the same generic transform conventions for the standalone visualizer: normalized x/y, overall scale, stretch_x/stretch_y, opacity, visibility, and editor selection/drag/resize. Pass 2 does not add visualizer-specific state or UI.

## TDD and validation

A focused `tests/test-quickshell-lockscreen-element-system.sh` is added before production changes and must be observed failing because the new schema and image model do not exist yet.

It must cover:

- legacy built-in layouts still normalize successfully with new defaults;
- new opacity/stretch fields validate and persist;
- Password opacity below 20 is rejected;
- custom images validate local readable paths, transforms, visibility, unique IDs, and maximum count;
- malformed image arrays fail atomically;
- Save and Reset include custom-image state;
- `BarState.qml`, secure shell, scene, preview scene, and editor expose the new model;
- editor controls include Add/Remove Image, opacity, stretch, and existing direct manipulation;
- custom images render below password/built-in presentation and never enter `LockAuth.qml`;
- secure/editor scene parity remains exact;
- managed-history, focused lockscreen workflows, and full Awtarchy validation remain green.

Runtime image appearance, drag/resize feel, and multi-monitor visual behavior remain unverified until the maintainer tests them in a real Hyprland session.