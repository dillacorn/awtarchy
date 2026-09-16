# Awtarchy v3.7.0 Quickshell

Awtarchy v3.7.0 is a major lockscreen customization update. It adds a visual editor, new transitions and effects, custom images and text, weather and timezone elements, background controls, and an audio visualizer.

## Install and update

Fresh installation: [INSTALL.md](https://github.com/dillacorn/awtarchy/blob/main/INSTALL.md)

Existing Awtarchy installations and stable updates: [UPDATING.md](https://github.com/dillacorn/awtarchy/blob/main/UPDATING.md)

Quick update:

```bash
awtarchy update
```

## Lockscreen customization

- New visual editor for moving, resizing, rotating, coloring, hiding, and resetting lockscreen elements.
- Undo/redo, snapping, guides, keyboard nudging, multi-selection, group editing, and layout presets.
- Add custom images and text, extra timezone clocks, weather information, and other lockscreen elements.
- Choose a dedicated lockscreen wallpaper or solid color and adjust fit, focal point, brightness, blur, and opacity.

## Transitions and effects

- New lockscreen transitions: Fade, Pixel / Resolution Collapse, Edges, and Wipe.
- The AWTARCHY logo reacts to cursor movement and clicks with animated physics effects.
- Optional CAVA/PipeWire audio visualizer with straight, arc, and circle layouts.
- Blur and transparency can show a secure frozen image of the desktop behind the lockscreen without exposing the live unlocked desktop.

## Other improvements

- `Super+P` opens the Power Menu immediately.
- Quick `Super+P` then `L` locking remains responsive.

## Validation

- Exact release target: `74e6edca328be90ddddf12f9417b2cd7051a312b`.
- Automated CI passed on the exact release target, including the full Awtarchy integration suite and focused lockscreen tests.
- The lockscreen editor, transitions, effects, and final Power Menu lock behavior were runtime-tested on Hyprland before release.

## Post-release updates

_Placeholder for possible tested post-release patches to v3.7.0._
