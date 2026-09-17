# Lockscreen Profile Presets And Sync Design

## Scope

This pass addresses the runtime feedback from the multi-monitor lockscreen editor candidate after `v3.7.0`:

1. `Ctrl+S` can fail with `invalid lockscreen profile` even though the editor produced the profile.
2. Shared-mode passive previews mirror direct manipulation continuously, causing avoidable cross-monitor lag.
3. Switching an Individual display back to Shared can silently discard substantial per-display work.
4. Users need reusable named visual configurations that can be applied to any display.

Authentication remains out of scope. `WlSessionLock` remains the sole secure lock authority and `LockAuth.qml` remains the PAM/authentication owner.

## Save Correctness And Schema Parity

The presentation resolver is the canonical normalizer for editor-owned visual profiles. Any profile returned by `LockscreenPresentationState.normalizedProfile()`, `sharedProfile()`, `monitorOverrides()`, or `profileForMonitor()` must satisfy the persistence backend's profile schema.

The persistence backend remains strict and atomic: Shared plus all monitor overrides either save together or nothing is changed. The fix must not weaken path, timezone, transform, enum, count, or type validation.

A permanent parity regression must cover resolver output through the real `save-lockscreen-editor-profiles` backend path, including old/out-of-range profile values that the resolver is expected to normalize. Validation failures should identify the failing profile section in stderr rather than collapsing everything into an opaque generic error.

## Settled Shared Preview Synchronization

The active display remains fully live during pointer manipulation.

For displays resolving the same Shared profile:

- drag, resize, rotation, visualizer width manipulation, and equivalent direct pointer manipulation update only the active display continuously;
- passive Shared previews render the last settled Shared snapshot while manipulation is active;
- when manipulation fully settles, including any supported post-release inertia, one final Shared snapshot is published and passive previews jump directly to the final result;
- keyboard nudges, discrete buttons, text fields, toggles, presets, and other non-continuous edits may continue updating Shared previews immediately.

This reduces redundant rendering without changing saved semantics.

## Safe Individual To Shared Switching

`Use Individual Configuration` remains a visual no-op: it clones the current effective Shared profile into a complete Individual override.

`Use Shared Configuration` becomes an explicit confirmation flow. It must not delete the Individual draft immediately. The dialog explains that the display's Individual configuration will be removed if the switch proceeds and provides exactly these choices:

- **Use Existing Shared**: discard the selected display's Individual draft and begin editing the current Shared draft.
- **Use This Display as Shared**: promote the selected display's current Individual profile to the Shared draft, remove that display's Individual override, and immediately update every display currently using Shared.
- **Cancel**: leave all drafts unchanged.

No persisted state changes until the normal editor save action succeeds. `Escape` or closing the editor still discards the entire unsaved session.

## Named Reusable Configurations

Named configurations are global reusable presets, not monitor-bound objects.

Persist them in Quickshell application state as `lockscreen_saved_profiles`, an ordered array. Each entry contains:

- stable generated `id`;
- user-facing `name`;
- one complete normalized visual `profile` snapshot.

Names must contain visible content, be bounded in length, and be unique case-insensitively. The saved profile uses the same complete schema as Shared and monitor overrides. Presets never contain authentication/session state, monitor identity, derived Auto Contrast colors, or other unrelated shell settings.

The Layout tab gains a Saved Configurations section supporting:

- save the currently effective display profile under a new name;
- rename a preset;
- delete a preset with confirmation;
- move a preset up or down in the ordered list;
- overwrite a preset from the currently effective selected-display profile;
- apply a preset to the currently selected display;
- apply a preset to any other currently connected display;
- apply a preset explicitly to Shared Configuration.

Applying a preset to a named display creates or replaces that display's Individual override so applying to one monitor never unexpectedly mutates every Shared monitor. Applying to **Shared Configuration** replaces the Shared draft and updates all displays currently using Shared.

All preset edits remain draft-only until `Ctrl+S`. Saving persists Shared, monitor overrides, and saved presets atomically under the same state-file lock and temp-file replacement. If any profile or preset is invalid, the entire transaction fails and the editor remains open.

Disconnected monitor overrides remain retained exactly as before. Preset application targets only connected displays plus the explicit Shared target.

## Undo, Drafts, And Session Behavior

Applying a preset to the active profile participates in that profile's undo/redo history. Applying to another display replaces that target Individual draft atomically and resets that target profile's undo/redo stack because no interactive history exists for the imported snapshot.

Renaming, reordering, deleting, creating, and overwriting saved presets are editor-session draft operations. `Escape` discards them together with every other unsaved editor change.

Monitor switching still never reloads persisted state during an open session.

## Validation

Permanent coverage must prove:

- resolver output is accepted by the backend profile schema;
- save remains atomic on invalid Shared, override, or saved-preset input;
- passive Shared previews freeze during direct manipulation and publish once on settle;
- Individual-to-Shared switching cannot silently discard a profile;
- both Shared switch choices produce the specified draft state;
- named presets create, rename, reorder, overwrite, delete, and apply correctly;
- applying to a display creates/replaces an Individual override;
- applying to Shared changes only the Shared draft plus displays that resolve it;
- saved-preset order and names survive persistence/reload;
- existing multi-monitor, editor shortcuts, transitions, media, weather, contrast, secure lock, managed-history, Lua, and production-readiness regressions remain green.

Real Hyprland interaction, perceived lag reduction, dialog usability, and secure multi-monitor rendering remain runtime acceptance items for the maintainer.