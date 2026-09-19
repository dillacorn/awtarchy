# Awtarchy v3.7.3 Quickshell

Awtarchy v3.7.3 is a performance enhancement and optimization release focused on making Quickshell hotkeys, Quick Settings, the bar, and flyout interactions feel substantially more immediate.

## Install and update

Fresh installation: [INSTALL.md](https://github.com/dillacorn/awtarchy/blob/main/INSTALL.md)

Existing Awtarchy installations and stable updates: [UPDATING.md](https://github.com/dillacorn/awtarchy/blob/main/UPDATING.md)

Quick update:

```bash
awtarchy update
```

## Performance and responsiveness

- Quickshell hotkeys now use direct IPC fast paths instead of repeating shell startup and state-normalization work before every action.
- Quick Settings prewarms and reuses monitor geometry, saved view/layout state, and status data, while heavier live refresh work is deferred until after the first frame.
- Launcher, Clipboard, Notifications, Network, Bluetooth, and Battery now reuse prepared flyout geometry instead of blocking on the same setup work every time they open.
- Bar flyout buttons prewarm the exact hovered monitor before the click lands, and the previous 250 ms toggle cooldown is removed so deliberate rapid open/close/open clicks are no longer discarded.
- Bar position and auto-hide shortcuts update live Quickshell state immediately, then persist the change in the background.
- Clipboard keeps its existing rows visible while fresh history reloads instead of blanking the popup first.
- Existing flyout fades and the global `Super+A` animation toggle remain intact while the work behind those animations is reduced.

## Validation

- Exact release target: `e9c5048722c6a2c46c14ab51e0d6c4c1f9473c7c`.
- Pull request #213 passed all 30 PR workflows on the exact release-candidate head before merge.
- All 17 `main` push workflows passed on the exact release target after merge.
- The maintainer runtime-tested the optimized bar, Quick Settings, launcher, rapid flyout toggling, and cross-flyout switching on Hyprland and confirmed the responsiveness improvements.

## Post-release updates

_Placeholder for possible tested post-release patches to v3.7.3._
