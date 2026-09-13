# Lockscreen editor elements and spawn design

Date: 2026-09-13
Branch: `feature/lockscreen-interactive-effects`
Parent acceptance: #187
Related scope: #188, #189, #190

## Goal

Finish the next maintainer-approved lockscreen editor pass without changing lock authority, authentication ownership, the accepted Pixel / Resolution Collapse transition, or the single persisted source of truth.

The pass corrects editor preview semantics, restores themed fly-out selection for spawn modes, adds configurable image/logo sequencing, makes rotation a generic transform, adds optional timezone clocks and arbitrary text elements, and fixes the Cursor/Lockscreen Quick Settings header alignment and wording.

## Non-negotiable architecture

- `WlSessionLock` remains the sole lock authority.
- `LockAuth.qml` remains the PAM/authentication owner.
- Secure password input remains owned by the secure lock surface; decorative presentation code cannot submit passwords.
- Editor preview is non-authentication UI.
- The accepted Pixel / Resolution Collapse implementation is preserved unless a targeted regression requires repair.
- Existing persisted lockscreen state remains the source of truth. Do not introduce separate Quick Settings/editor/runtime copies of the same setting.
- Old state that lacks new fields must normalize to backward-compatible defaults.
- Runtime/visual/audio/compositor behavior is not accepted until maintainer Hyprland testing.

## Themed fly-out selectors

`LockscreenCompactSelector.qml` keeps its small editor-bar footprint and public `model`, `currentIndex`, and `activated(index)` contract, but stops cycling values with left/right click zones.

Clicking the control opens a compact Awtarchy-themed fly-out containing all options. The current value is shown in the closed control with one disclosure indicator. The menu uses existing Awtarchy popup/button colors, border language, typography, hover state, keyboard focus, and rounded geometry.

Keyboard behavior:

- Enter/Space opens the fly-out.
- Up/Down moves through choices.
- Enter commits the highlighted choice.
- Escape closes without changing the value.

Use this selector for custom-image spawn type, logo spawn type, and password-mask mode. Clock 12/24-hour format is not a selector; it becomes a direct two-state toggle.

## Editor preview semantics for custom images

A custom image's persisted spawn mode describes playback, not its normal editing position.

When the editor is idle:

- every custom image is rendered at its final x/y/scale/stretch/rotation regardless of spawn mode;
- changing spawn mode does not move, hide, clip, or partially expose the image at an edge;
- changing spawn timing does not move or hide it;
- selecting, dragging, resizing, rotating, or editing values works against the settled geometry.

Animation offsets/progress become active only while an explicit replay is in progress.

Each selected custom image gets an individual `Play Spawn` action. This replays only that image from its selected spawn mode and returns it to the final settled location. It must not replay the desktop transition, logo, other images, or authentication presentation.

The full editor Replay action still exercises the complete presentation sequence.

## Custom-image sequencing

Each custom image gains:

```text
spawn_timing = during-logo | after-logo
```

Default: `during-logo`.

Semantics:

- `spawn_animation = none`: image stays settled and does not animate; timing is irrelevant.
- `during-logo`: image spawn begins when logo entry begins and may overlap logo formation.
- `after-logo`: image remains withheld during logo entry and begins after logo entry completes.

The secure runtime and full editor replay consume the same timing state. Individual image replay ignores global phase gating because it is an explicit editor action.

Legacy images without `spawn_timing` normalize to `during-logo`.

## Logo spawn control

Logo spawn uses the same themed fly-out selector instead of left/right cycling. Changing the mode in the editor must not unintentionally replay it. An explicit Replay/Preview action remains available.

## Clock format and additional timezone clocks

The primary clock keeps the existing `24h` default and becomes a direct 12h/24h toggle in the settings bar.

Users may add bounded optional timezone-clock elements. Each timezone clock has:

- stable id;
- optional user label;
- IANA timezone identifier such as `America/New_York`;
- 12h/24h format;
- x/y;
- scale;
- horizontal/vertical stretch;
- opacity;
- color;
- rotation;
- visibility.

Timezone values are validated against local `/usr/share/zoneinfo` data. Rendering must remain network-free and DST-aware. Invalid/missing zones fail safely to a normalized fallback or reject the edit; they never invoke an arbitrary shell command.

The secure lockscreen uses a bounded local helper/data path to produce display strings. Do not start an unbounded process per frame or per monitor. Editor primary and secondary previews consume the same normalized timezone-clock state and formatting results.

Timezone clocks participate in selection, direct manipulation, numeric controls, visibility, color, rotation, reset, undo/redo, atomic persistence, preview, and secure rendering.

## Generic rotation

Rotation becomes part of the common presentation transform.

Built-in layout points (`logo`, `time`, `date`, `username`, `weather`, `password`) gain `rotation`, default `0`.

The visualizer gains `rotation`, default `0`.

Custom images retain their current rotation field.

Timezone clocks and custom text elements include rotation from creation.

For any single selected editable element, the editor shows the same rotation controls currently available for custom images:

- direct rotation handle where practical;
- numeric exact angle input;
- preset 0°, 90°, 180°, 270° actions;
- same normalized state for handle/preset/typed input.

Rotation participates in undo/redo, reset/default, Reset All, persistence, editor preview, and secure rendering. The Password presentation may rotate, but its hidden secure TextInput/authentication ownership remains unchanged.

## Arbitrary text elements

Add a bounded `lockscreen_custom_texts` array rather than overloading the built-in username element.

Each text element has:

- stable id;
- `variants`: one or more user strings;
- `randomize`: boolean;
- `alignment`: `left`, `center`, or `right`;
- x/y;
- scale;
- horizontal/vertical stretch;
- opacity;
- color;
- rotation;
- visibility.

Users can create multiple text elements.

### Content editing

The editor provides a multiline text editor. Newlines and indentation are preserved. Shift+Enter explicitly inserts a line break/indented continuation instead of committing/closing the edit. Tabs/newlines are allowed; NUL and unsafe control characters are rejected. Persisted text length/count are bounded.

When randomization is off, the first variant is rendered. When randomization is on, one user-provided variant is selected once for a presentation session/replay, not once per frame. Editor preview may expose an explicit shuffle/replay action to show another variant without mutating the saved variants.

Text alignment is a direct left/center/right control. Text elements use the same transform/color/visibility/reset/undo/persistence machinery as other presentation elements.

## Dynamic element identity

Dynamic element names remain stable during an editor session:

- `image:<id>`
- `timezone:<id>`
- `text:<id>`

Common element helpers dispatch by prefix so generic move/scale/stretch/opacity/color/rotation/visibility/reset/history operations do not fork into separate state systems.

`Ctrl+A`, Ctrl+Mouse1 multi-selection, group drag, group scale where supported, and group visibility continue to operate through the same selection/history path. Password remains non-hideable.

## Persistence and migration

Keep the established first 19 arguments to `quickshell_application_state.sh save-lockscreen-editor` intact.

The wrapper continues to own presentation extensions and gains bounded JSON inputs for timezone clocks and custom text. Current logo/mask/clock fields remain normalized there.

Normalization changes:

- built-in layout point: accept `rotation`, default `0`;
- visualizer: accept `rotation`, default `0`;
- custom image: accept `spawn_timing`, default `during-logo`;
- timezone clocks: strict bounded array/object validation;
- custom text: strict bounded array/object/string validation.

All writes remain atomic. No password contents are persisted. Invalid state falls back safely rather than reaching authentication code.

## Quick Settings Cursor/Lockscreen headers

Cursor and Lockscreen section headers use the same structural layout and right-side action column so their expand controls align vertically/horizontally.

Labels become explicit:

- `Expand Cursor` / `Collapse Cursor`
- `Expand Lockscreen` / `Collapse Lockscreen`

The Lockscreen `Edit Layout` action remains directly below its expand/collapse button. The small current animation value must not distort the expand-button column; move it into expanded content or another aligned location if it remains useful.

Detailed lockscreen editing remains in the editor, not duplicated into Quick Settings.

## Rendering and performance

- Settled editor state does not run spawn animations or hidden timers unnecessarily.
- Individual replay activates only the selected image animation.
- Dynamic text/timezone element counts are bounded.
- Timezone refresh cadence is coarse enough for minute-resolution clocks and does not poll per frame.
- Random text choice is stable for the presentation epoch.
- No new unbounded shader/tile/process workload.

## Tests

TDD additions must cover at minimum:

1. themed fly-out selector has menu/open/close/keyboard semantics and no click-zone cycling;
2. changing image spawn mode/timing leaves editor image settled;
3. individual image replay targets one image;
4. `during-logo` is the migration/default and begins with logo; `after-logo` begins after logo completion;
5. full replay/secure runtime share timing semantics;
6. clock format uses a toggle;
7. timezone clock normalization, bounded persistence, safe timezone validation, preview/secure render parity;
8. rotation on all built-ins, Password presentation, visualizer, images, timezone clocks, and text;
9. custom text multiline/random/alignment normalization and editor/secure parity;
10. Quick Settings explicit labels and Cursor/Lockscreen header alignment structure;
11. atomic save/failure cleanup and no persisted password content;
12. secure/preview scene parity where the repository requires byte-identical renderers;
13. managed-history current stock hashes for every modified managed file.

## Runtime acceptance

Automated green status is necessary but not sufficient. Final maintainer testing must verify:

- fly-out visual/theme quality;
- settled image preview when switching spawn modes/timing;
- per-image replay;
- overlap timing for `during-logo` and sequencing for `after-logo`;
- logo spawn fly-out;
- clock toggle and multiple timezone clocks;
- rotation behavior for every element type, including Password and visualizer;
- arbitrary multiline/random/aligned text;
- Cursor/Lockscreen Quick Settings header alignment and clearer labels;
- secondary-monitor preview parity;
- authentication remains immediately usable and unaffected by decorative animation.