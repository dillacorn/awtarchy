# Lockscreen Runtime Polish and Awtwall Picker Integration Design

## Scope

This design is a follow-up to `2026-09-08-lockscreen-interactive-effects-design.md` and addresses issues found during the first real Hyprland runtime test of draft PR #181.

The work spans two repositories:

- `dillacorn/awtarchy`, continuing on `feature/lockscreen-interactive-effects` / draft PR #181.
- `dillacorn/awtwall`, implementing issue #2 on a dedicated feature branch before Awtarchy consumes it.

The changes cover five connected problems:

1. the lockscreen editor control area occupies too much screen space;
2. `Choose Wallpaper` cannot currently use Awtwall because Awtwall lacks the required selection-only interface and the fullscreen editor can obscure a normal terminal window;
3. the AWTARCHY logo pointer effect moves large connected groups too rigidly instead of behaving like deformable blocks;
4. the Awtarchy Quick Settings card presents Cursor and Lockscreen controls as an oversized flat cluster instead of one cohesive editable Awtarchy section;
5. Cursor controls are duplicated in the generic Quick Settings cog/settings surface and should exist only in the Awtarchy card.

This work does not change lock authority, PAM ownership, release state, or stable update behavior.

## Non-negotiable invariants

- `WlSessionLock` remains the sole lock authority.
- `config/quickshell/awtarchy-lock/LockAuth.qml` remains the sole PAM/authentication owner.
- `LockSurface.qml` remains responsible for the real secure password input.
- The unlocked editor never receives or submits password data.
- The lockscreen presentation scene remains presentation-only.
- Awtwall selection-only mode must never apply a desktop wallpaper or mutate normal wallpaper/backend state.
- PR #181 remains draft, open, and unmerged until runtime validation is complete.
- No Awtarchy or Awtwall release/tag is created, moved, edited, or replaced as part of this work.
- Interactive/visual behavior is not considered runtime-verified until the maintainer tests the exact candidate on Hyprland.

## Architecture overview

The work is split into two repository-level components and then integrated:

1. Awtwall gains a pure picker mode that returns a selected image path without applying anything.
2. Awtarchy temporarily suspends its fullscreen lockscreen editor surface while the external picker is visible, then restores the same unsaved editor draft when the picker exits.
3. The lockscreen editor control surface becomes a compact dock with expandable contextual drawers.
4. The Awtarchy Quick Settings card becomes a compact Awtarchy settings hub with expandable Cursor and Lockscreen subsections.
5. The wordmark pointer deformation changes from connected-group rigid motion to bounded per-block displacement with soft neighbor cohesion.

## Awtwall selection-only picker

### Interface

Implement issue `dillacorn/awtwall#2` with these command-line options:

```text
--select-only
--select-result FILE
```

`--select-only` switches Awtwall from wallpaper-applicator mode to image-picker mode.

`--select-result FILE` is valid only with `--select-only`. On successful selection, Awtwall atomically writes exactly one absolute local path plus a trailing newline to that file, then closes. Awtarchy already expects this interface.

Awtwall should also continue to print the selected absolute path to stdout when practical, but Awtarchy integration must use `--select-result FILE` so terminal rendering/output cannot corrupt the machine-readable result.

### Picker behavior

Selection-only mode reuses the normal wallpaper library scan, filtering, thumbnail rendering, search, paging, and navigation behavior.

When active:

- `--type images` filters to still images;
- mouse click, Space, or Enter on an image accepts that exact file;
- Escape or `q` cancels and exits without writing a result;
- the display selector and output-target controls are hidden/disabled;
- wallpaper backend selection and transition controls are irrelevant and must not be entered;
- random-apply actions are unavailable;
- post-exec configuration/actions are unavailable;
- no wallpaper application occurs.

Normal Awtwall behavior remains unchanged when `--select-only` is absent.

### State and backend isolation

Selection-only mode must not initialize or invoke:

- `awww` / `swww` application paths;
- `hyprpaper` application paths;
- `mpvpaper` application paths.

It must not modify:

- `LAST_APPLIED`;
- per-output wallpaper state;
- backend state files;
- persisted display target;
- post-exec enabled state or command;
- wallpaper transition settings as a side effect of selection;
- the desktop wallpaper itself.

It may still use Awtwall's existing non-destructive library/cache data required to render the picker, including thumbnail cache and saved browse position if current behavior already does so.

### Result-file safety

`--select-result FILE` must reject an empty path and must not treat the value as shell code.

On selection:

1. resolve the selected file as the exact absolute path already present in Awtwall's scanned file list;
2. write to a temporary file in the result file's directory;
3. rename the temporary file over the requested result path;
4. close the picker.

On cancel, error before selection, or normal close without selection, leave the result path absent or empty so the consumer can distinguish cancellation from selection.

## Awtarchy external picker lifecycle

### Existing problem

The lockscreen editor is a fullscreen layer-shell surface with `aboveWindows: true` and exclusive keyboard focus. A normal Alacritty window launched for Awtwall can therefore be hidden behind the editor or fail to receive usable focus.

### Required behavior

The editor must keep its draft state in memory while temporarily removing its fullscreen surface from the screen.

When `Choose Wallpaper` starts:

1. snapshot no new persisted state; continue using the current in-memory draft;
2. mark the editor as picker-suspended;
3. hide/suspend the fullscreen editor window and release the editor overlay claim needed to stop it covering/focusing above normal windows;
4. launch the existing wallpaper-picker helper;
5. allow Alacritty/Awtwall to become the normal visible focused window.

When the picker exits:

- if a valid path was returned, update `draftWallpaperPath`, switch the draft background to wallpaper mode, and schedule preview contrast refresh;
- if the picker was cancelled, leave the draft unchanged;
- restore the editor window on the same monitor;
- reclaim the editor overlay;
- restore keyboard focus to the editor;
- preserve undo/redo stacks, selected element(s), draft layout, background controls, visibility, weather units, palette state, and all other unsaved draft values.

The editor must not call its normal `close()` path for picker suspension because `close()` reloads persisted state and would destroy unsaved changes.

If Awtwall does not support `--select-only`, the helper should continue to fail with a clear compatibility message rather than falling back to normal wallpaper-application mode.

## Compact lockscreen editor controls

### Goal

The lockscreen preview should occupy almost the entire display. Controls should expose advanced functionality without permanently consuming a large bottom section.

### Dock structure

Replace the current fixed 282 px / 432 px bottom slab with a compact bottom dock.

The collapsed/base dock contains only the controls needed constantly while arranging elements:

- selected element label;
- visibility state for the selected element;
- scale decrement/value/increment;
- X and Y numeric fields;
- Undo / Redo;
- contextual drawer buttons: `Element`, `Layout`, `Background`, `Weather`;
- Save / Cancel;
- short status text when space permits.

Target height should be approximately one compact control row plus margins, with responsive wrapping only when monitor width makes one row impossible. The exact QML implicit height should be content-driven rather than a large fixed slab.

### Contextual drawers

Only one drawer is open at a time. Drawers open upward from the dock so they do not permanently reduce the preview.

`Element` contains:

- Reset Position;
- selected element color presets;
- custom inline color picker;
- `Auto All`, `White All`, `Black All`.

`Layout` contains:

- Minimal;
- Centered;
- Information;
- Lower Third;
- Guides;
- selection/group-use hints if needed.

`Background` contains:

- Black;
- Wallpaper;
- Choose Wallpaper;
- Color;
- background palette;
- Cover / Contain;
- Darken / Lighten / None;
- overlay amount;
- blur amount;
- wallpaper filename/status.

`Weather` contains:

- Auto;
- Fahrenheit;
- Celsius.

Restore Defaults belongs in an overflow/secondary area or the relevant Layout drawer rather than permanently occupying the base dock.

Opening a color palette must expand only the active drawer, not add a large fixed height to the whole editor.

### Responsiveness

The dock must remain usable on common 16:9, 16:10, 3:2, and narrower logical monitor widths.

Controls may wrap into a second compact row when required, but should not return to a multi-row full-width settings panel that obscures a large part of the composition.

## Awtarchy Quick Settings information architecture

### Goal

The Awtarchy card should read as one product/settings area rather than several unrelated controls stacked together.

### Default state

The Awtarchy card should be compact by default and show:

- `Awtarchy` title;
- `Awtarchy Tips` shortcut;
- one `Edit` control.

Existing non-edit informational text may remain if it fits the compact header without materially increasing height.

### Edit mode

Pressing `Edit` expands the Awtarchy card and reveals two subsections:

- `Cursor`;
- `Lockscreen`.

Each subsection has its own expand/collapse control and summary. The user should not have to expand both to reach one category.

`Cursor` owns all Awtarchy cursor preferences:

- Color;
- Shape;
- Hand.

`Lockscreen` owns all lockscreen presentation preferences currently exposed in Quick Settings:

- formation animation;
- Edit Layout;
- background summary/control;
- Mouse Interaction;
- Audio Reactive;
- optional metadata controls currently owned by the section;
- weather location override;
- restore lockscreen/Awtarchy defaults behavior.

The exact existing state commands and persistence owners remain unchanged unless an existing command cannot support the compact presentation.

### Remove duplicate cursor settings

Remove `CursorThemeSettings` from the generic Quick Settings cog/settings surface (`FlyoutSettings.qml`).

Cursor settings remain only in the Awtarchy card.

Update regression tests that currently require the selector in both locations so they instead require:

- Cursor settings present in the Awtarchy card;
- Cursor settings absent from the generic Quick Settings settings panel;
- existing cursor persistence/migration behavior unchanged.

## Gooey per-block AWTARCHY deformation

### Existing problem

The current pointer model first groups every connected wordmark region and then assigns one deformation offset to the entire cohesion group. That makes connected letters/chunks move like rigid objects.

### Desired behavior

The assembled wordmark should remain readable and cohesive, but nearby blocks should be able to separate slightly under pointer/click influence and then reform smoothly.

### Per-block deformation model

Keep existing formation coordinates and animation behavior.

For each filled wordmark block after formation is substantially complete:

1. calculate pointer/click radial displacement from that block's own center, not the connected group's center;
2. cap direct displacement to a bounded logical-pixel amount;
3. blend a smaller fraction of neighboring blocks' direct displacement into the block's target so adjacent cells pull in similar directions without being rigidly identical;
4. animate the block target quickly toward the pointer-induced offset;
5. when influence disappears, return smoothly to zero using a slower spring-like/eased return.

The visual result should resemble soft connected pixels: local pieces spread, stretch, and slide relative to one another, but neighboring cells still influence one another enough that the logo reforms as one wordmark.

### Neighbor cohesion

Use the existing grid topology rather than a full general-purpose physics solver.

Each block needs only its local orthogonal neighbors, optionally including diagonals if the effect is too segmented during runtime tuning.

A simple target blend is sufficient:

```text
final target = direct pointer/click offset
             + small weighted average of neighbor direct offsets
```

Do not add an unconstrained iterative spring simulation, collision system, or permanent high-frequency physics loop.

Audio displacement remains weaker and may continue to use its existing behavior as long as it composes cleanly with the new per-block pointer deformation.

### Performance constraints

- no new always-running timer when the pointer is idle;
- reuse the existing bounded pointer update cadence;
- do not allocate large transient structures per frame;
- cap displacement so blocks cannot scatter across the screen;
- interaction remains disabled until formation is essentially complete;
- pointer interaction off means zero pointer/click deformation and no hidden work for it.

## Testing strategy

Production changes follow RED -> GREEN -> refactor.

### Awtwall focused regression

Add a non-interactive shell test harness that proves selection-only isolation without requiring an actual terminal wallpaper apply.

The test must fail before implementation and then prove at least:

- help exposes `--select-only` and `--select-result`;
- `--select-result` without `--select-only` is rejected;
- selection-only mode does not call the wallpaper apply functions/backend commands;
- selection-only mode does not enter display-target selection/application paths;
- the accepted image path written to the result file matches the selected scanned file exactly;
- cancel leaves no selected result;
- normal non-selection CLI parsing remains unchanged.

Where direct interactive key simulation would be brittle, factor the final accept/cancel behavior into small shell functions that can be exercised directly while the TUI continues to call the same functions.

### Awtarchy focused regressions

Add/update focused tests for:

- wallpaper picker suspend/resume preserving draft editor state;
- no fallback to normal Awtwall apply mode;
- compact editor dock/drawer structure and removal of the fixed oversized panel heights;
- compact Awtarchy card edit mode with separate Cursor and Lockscreen subsections;
- absence of `CursorThemeSettings` from `FlyoutSettings.qml`;
- cursor selector still present in the Awtarchy card;
- per-block pointer target calculation rather than one shared connected-group pointer offset;
- `LockAuth.qml` unchanged;
- one `WlSessionLock` authority preserved;
- preview/secure presentation parity requirements already enforced by PR #181 remain intact.

### Broad validation

Before presenting a runtime candidate:

- run syntax checks and ShellCheck for changed shell files where available;
- run all focused lockscreen tests;
- run cursor/Bibata tests affected by the Quick Settings move;
- run Quick Settings layout/lifecycle tests;
- run managed-history tests when managed Quickshell/helper files change;
- run Runtime Stress Analysis;
- run full `Validate Awtarchy` integration on the exact final PR head;
- require the exact Awtwall feature head's focused test to pass.

Static/CI success does not prove editor visual ergonomics, terminal visibility over Hyprland, or gooey motion quality. Those require maintainer runtime testing.

## Runtime acceptance test

The exact test candidate is ready for maintainer testing only after all automated validation passes.

Runtime acceptance should verify:

1. opening the lockscreen editor leaves most of the lockscreen visible;
2. contextual drawers open/close without the permanent oversized slab returning;
3. current unsaved edits survive opening and cancelling Awtwall;
4. `Choose Wallpaper` makes Awtwall visibly appear and receive input;
5. selecting an image changes only the lockscreen draft and does not alter any desktop wallpaper;
6. Save persists the selected lockscreen wallpaper and reopening the editor shows it;
7. Cursor controls exist in the Awtarchy card and no longer appear in the generic cog/settings panel;
8. Awtarchy `Edit`, Cursor, and Lockscreen expansion/collapse feels compact and coherent;
9. pointer interaction locally separates logo blocks and they smoothly reform after the pointer moves away;
10. disabling Mouse Interaction returns the logo to non-interactive behavior;
11. real locking, wrong-password handling, and successful PAM unlock still work normally;
12. multi-monitor lock surfaces remain secure and visually consistent.

## Repository and delivery state

Awtwall implementation is developed on an isolated feature branch for issue #2. Once its focused tests pass, provide the maintainer an exact commit SHA and a copy-ready command to install/run that commit for testing without publishing a release.

Awtarchy work continues on `feature/lockscreen-interactive-effects` so draft PR #181 remains the single integration PR for this lockscreen feature.

Do not merge either feature merely because automated validation passes. The next Awtarchy candidate is delivered as an exact `awtarchy git update --branch feature/lockscreen-interactive-effects --commit <full-sha>` command only after both repository heads are internally consistent and CI passes.
