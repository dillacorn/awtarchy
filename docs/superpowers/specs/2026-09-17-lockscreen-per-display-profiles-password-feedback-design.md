# Lockscreen per-display profiles and password feedback design

Date: 2026-09-17

## Context

The current lockscreen editor supports a Shared profile plus optional Individual monitor overrides. Runtime testing showed that this model is confusing and destructive in normal editing: switching a monitor back to Shared can discard work, and users have to reason about inheritance while trying to edit a concrete display.

The same runtime pass exposed a separate save round-trip failure. A resolver-normalized profile containing custom media could load correctly but fail unchanged on Ctrl+S. The failure had two causes:

- the generic resolver added an unused `color` field to custom-media entries while the authoritative backend forbids that field;
- the backend profile path validator used a malformed control-character regex that rejected ordinary absolute paths.

That bounded save bug is covered by `tests/test-quickshell-lockscreen-profile-save-parity.sh` and is fixed separately from this architectural redesign.

## Goals

- Remove Shared/Individual configuration modes from the editor.
- Give every display one complete independent lockscreen profile keyed by output name.
- Reuse a display's last saved profile when that same output name reconnects.
- Seed a genuinely unseen display from the most recently edited complete profile.
- Keep copying deliberate through `Copy Configuration To…`; editing one display must never live-mutate another display.
- Preserve the global reusable saved-configuration library.
- Prevent visible elements from using opacity below 5%.
- Add an explicit Element-tab selector so canvas clicking is optional.
- Add password feedback modes for sparks, localized mini-flashes, existing masks, and hidden feedback.
- Show a brief red edge-light failure effect on every locked display when authentication fails, including when password feedback is hidden.
- Preserve all authentication/security ownership: `WlSessionLock` remains the secure lock authority and `LockAuth.qml` remains the PAM owner.

## Non-goals

- No per-monitor PAM/authentication sessions.
- No monitor EDID/serial renaming or fuzzy monitor identity matching.
- No sparse per-display patches.
- No synchronization of drag motion between displays.
- No full-screen flash on every typed password character.
- No external renderer for password effects.
- No release, merge, or `main` changes as part of this development pass.

## Chosen profile model

### Persisted state

The lockscreen state gains:

- `lockscreen_monitor_profiles`: object keyed by exact output name. Every value is one complete normalized visual profile.
- `lockscreen_last_edited_profile`: one complete normalized profile used only as the seed for an output name that has never been seen before.
- `lockscreen_saved_profiles`: existing ordered global reusable preset library.

The old `lockscreen_monitor_overrides` field is migration input only after this redesign. It is not an active source of truth.

The existing top-level `lockscreen_*` visual fields remain as a legacy/default migration source and downgrade fallback. On successful saves they mirror the last-edited profile, but runtime/editor resolution uses `lockscreen_monitor_profiles`, not the top-level fields.

### Migration

When the new resolver loads old state:

1. Normalize the legacy top-level lockscreen fields into the legacy/default profile.
2. If `lockscreen_monitor_profiles` already exists, normalize and use it.
3. Otherwise migrate every valid `lockscreen_monitor_overrides[output]` entry into the new monitor profile map.
4. Every currently connected output without a migrated override receives a clone of the legacy/default profile in the editor session.
5. Disconnected legacy overrides are retained by exact output name.
6. `lockscreen_last_edited_profile` resolves from its persisted value when present, otherwise from the normalized legacy/default profile.
7. The first successful Ctrl+S writes the new map atomically and removes the old override map so there is only one active per-monitor source of truth.

A reconnect using the same output name restores that output's saved profile.

A truly unseen output receives a draft clone of `lockscreen_last_edited_profile`. It becomes a persistent independent monitor profile on the next successful Ctrl+S.

## Editor session model

The editor owns:

- `draftMonitorProfiles`
- `draftLastEditedProfile`
- `draftSavedProfiles`
- `activeMonitorName`
- undo/redo history partitioned by monitor name

There is no `draftSharedProfile`, Shared mode, Individual mode, mode-switch confirmation, or profile inheritance during editing.

Opening the editor:

- loads persisted/migrated monitor profiles once;
- chooses the focused connected output as active;
- seeds any currently connected unseen outputs from the last-edited profile;
- shows a passive preview for every connected output;
- keeps only the active display focusable/directly manipulable.

Switching displays flushes the active draft to its monitor entry, changes the active monitor, and loads that target's in-memory draft. It never reloads disk state.

### Copying

`Copy Configuration To…` clones the source display's complete current draft into the chosen target display.

- The source remains unchanged.
- The target is replaced atomically in the editor draft.
- `All Other Displays` remains available.
- Copying is undoable for the affected target profile.
- A copied configuration is not persisted until Ctrl+S.
- Continuous drag/resize/rotate motion never propagates to another display.

### Topology changes

- Newly connected known output: use its retained draft/persisted profile.
- Newly connected unseen output: seed from the current last-edited profile.
- Disconnected output: remove only its live preview; retain its draft/profile.
- If the active output disappears, switch to the focused connected output when possible, otherwise the first connected output.
- No draft loss when topology changes.

## Saved configurations

The existing global saved-configuration library remains independent of monitor identity.

Layout-tab actions remain:

- Save Current Configuration
- Rename
- Delete with confirmation
- Move Up
- Move Down
- Overwrite with confirmation
- Apply To any connected display
- Apply To All Other Displays

The old `Apply To Shared Configuration` target is removed because Shared no longer exists.

Applying a saved configuration replaces the selected target display's complete draft profile and is undoable. It does not save automatically.

## Opacity and visibility

Element opacity is constrained to **5–100%** for every visible editable element:

- logo
- time
- date
- username
- weather
- password presentation
- visualizer
- custom media
- timezone clocks
- custom text

Background opacity remains a separate composition control and may still use its existing 0–100% range.

Migration/normalization rules:

- persisted element opacity from 1–4 becomes 5;
- persisted element opacity 0 preserves the old invisible result by converting the corresponding visibility state to hidden/disabled where that element has an explicit visibility field;
- custom media, timezone clocks, and custom text use their `visible` field for true hiding;
- built-in elements use their existing show/hide booleans;
- visualizer opacity 0 migrates to disabled;
- password opacity 0 migrates to hidden password feedback;
- all newly edited visible elements clamp at 5 and cannot be dragged/slid/typed below 5.

The UI continues to expose Hide/Show as the correct way to remove an element visually.

## Explicit Element selection

The Element drawer gains a selector listing every currently editable element:

- Awtarchy Logo
- Time
- Date
- Username
- Weather
- Password
- Visualizer
- each custom media element
- each timezone clock
- each custom text element

Choosing an entry performs the same primary selection as clicking the element on the canvas:

- `selectedElement` becomes the chosen item;
- `selectedElements` becomes that single item;
- its controls become active;
- canvas clicking remains supported;
- deleted dynamic elements disappear from the selector immediately.

This is a selection mechanism only. It does not change element visibility.

## Password presentation model

### Persisted field

Replace the mask-only concept with:

`lockscreen_password_feedback_mode`

Allowed values:

- `squares`
- `dots`
- `custom`
- `sparks`
- `mini-flash`
- `hidden`

`lockscreen_password_mask_character` remains for `custom`.

Legacy `lockscreen_password_mask_mode` migrates directly for `squares`, `dots`, and `custom`. Missing/unknown legacy values fall back to `squares`.

### Typing behavior

The secure `TextInput` remains the password input owner inside `LockSurface.qml`. Password characters are never sent to the presentation effect.

Effects use only insertion events/length changes:

- **Squares**: current persistent square mask behavior.
- **Dots**: current persistent dot mask behavior.
- **Custom**: current persistent custom-character mask behavior.
- **Sparks**: each inserted character creates a small randomized group of short-lived particles inside the password zone. No persistent mask is shown.
- **Mini Flash**: each inserted character creates one small localized soft flash at a randomized point inside the password zone, then fades. No persistent mask is shown.
- **Hidden**: no per-character visual feedback.

Backspace/deletion does not create sparks or mini-flashes.

There is no whole-display typing flash.

The editor preview can show the chosen static mask mode and can trigger a short local demo for Sparks/Mini Flash without touching authentication.

### Authentication failure feedback

Every `LockSurface` listens to the existing shared `LockAuth.authenticationFailed()` signal.

On failure:

- increment a local failure-effect epoch;
- briefly light the display edges red;
- fade the effect quickly;
- clear the typed password exactly as today;
- return focus to the password input;
- do not alter PAM state or retry semantics.

Because all secure surfaces share the same `LockAuth` object, all locked displays receive the same failure signal and show the red edge response together.

The red edge effect occurs for every feedback mode, especially `hidden`.

The failure effect is presentation-only and never delays, suppresses, or changes authentication.

## Security invariants

- `WlSessionLock` remains the sole lock authority.
- `LockAuth.qml` remains the sole PAM/authentication owner.
- No password content is logged, persisted, placed in argv/environment, or passed to visual components.
- Spark/flash animation uses only a presentation epoch and password-length delta.
- Hidden feedback still accepts keyboard input normally.
- No monitor can expose the desktop while another remains locked.
- Media pre-roll and visual effects remain presentation-only and cannot delay lock acquisition/authentication ownership.

## Save behavior and validation

Ctrl+S performs one atomic transaction containing:

- complete `lockscreen_monitor_profiles`;
- `lockscreen_last_edited_profile`;
- global `lockscreen_saved_profiles`;
- legacy top-level mirror of the last-edited profile.

Any invalid monitor profile or saved preset rejects the whole transaction. The editor stays open and shows the specific validation failure.

The resolver/backend parity contract expands so every normalized profile emitted by the JS resolver is accepted unchanged by the authoritative Bash backend.

Custom-media path/control-character validation uses code-point checks rather than regex escaping that can diverge between JavaScript and jq.

## Testing strategy

Production changes follow TDD.

Permanent regressions cover:

1. Resolver/backend no-change round trips including custom media.
2. Migration from legacy Shared + monitor overrides to complete per-output profiles.
3. Exact-output reconnect behavior and unseen-output seeding from last edited profile.
4. Removal of Shared/Individual editor controls and state.
5. Monitor switching without disk reload or draft loss.
6. Copy-to-one and copy-to-all monitor semantics.
7. Atomic save/rollback of monitor profiles + last-edited profile + saved configurations.
8. 5% minimum opacity for visible elements and migration of legacy opacity zero to hidden/disabled state.
9. Explicit Element-tab selection of built-in and dynamic elements.
10. Password feedback schema migration and editor controls.
11. Secure Sparks/Mini Flash staying within the password zone.
12. Hidden password feedback producing no per-key visuals.
13. Authentication failure triggering red edge feedback on every secure surface without modifying `LockAuth`.
14. Existing lock transitions, media pre-roll, weather, timezone, Auto Contrast, visualizer, and secure multi-monitor behavior.
15. Managed-history refresh, Lua validation, production-readiness checks, Bash syntax, and `git diff --check`.

Runtime/visual/performance behavior remains unconfirmed until tested under Hyprland on real displays.
