#!/usr/bin/env bash
# Awtarchy Quick Settings categories remain independently accessible.
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
QUICK="$ROOT/config/quickshell/awtarchy/QuickSettings.qml"
SOUND="$ROOT/config/quickshell/awtarchy/ScreenshotSoundSettings.qml"

python3 - "$QUICK" "$SOUND" <<'PY'
from pathlib import Path
import sys

quick = Path(sys.argv[1]).read_text(encoding="utf-8")
sound = Path(sys.argv[2]).read_text(encoding="utf-8")

def require(value, source, explanation):
    if value not in source:
        raise SystemExit("FAIL: " + explanation)

def reject(value, source, explanation):
    if value in source:
        raise SystemExit("FAIL: " + explanation)

reject("awtarchyEditMode", quick,
       "the legacy global Edit/Done mode still hides other Awtarchy categories")
reject("sectionActionColumnWidth", quick,
       "old fixed-width, stacked category action columns remain")
require("property bool soundSectionExpanded: true", quick,
        "sound switches are not available by default")
for name in ("cursor", "lockscreen"):
    require(f"property bool {name}SectionExpanded: false", quick,
            f"{name} initial expanded state changed")
    require(f"root.{name}SectionExpanded = !root.{name}SectionExpanded",
            quick, f"{name} must expand independently")

require("root.soundSectionExpanded = !root.soundSectionExpanded", quick,
        "sound must expand without entering an edit mode")
require("visible: root.soundSectionExpanded", quick,
        "sound controls are not tied to the Sound category")
require("visible: root.cursorSectionExpanded", quick,
        "cursor controls are not tied to the Cursor category")
require("visible: root.lockscreenSectionExpanded", quick,
        "lockscreen controls are not tied to the Lockscreen category")
require("active: visible && quickSettingsWindow.visible", quick,
        "cursor refresh must remain bound to the visible panel")
require("root.openLockscreenEditor()", quick,
        "lockscreen layout editor no longer opens")

card_start = quick.index("id: awtarchyContent")
card_end = quick.index('Layout.row: root.quickSettingsSectionRow("smtty")',
                       card_start)
card = quick[card_start:card_end]
ordered = [
    'text: "Awtarchy"',
    'label: "Tips"',
    'text: "Sound"',
    'id: screenshotSoundSettings',
    'text: "Cursor"',
    'id: awtarchyCursorThemeSection',
    'text: "Lockscreen"',
    'visible: root.lockscreenSectionExpanded',
    'label: "Edit Layout"',
    'text: "Lockscreen Animation"',
]
positions = [card.find(token) for token in ordered]
if -1 in positions or positions != sorted(positions) or len(set(positions)) != len(positions):
    raise SystemExit("FAIL: Awtarchy section ordering or lockscreen layout action changed")

# All existing lockscreen controls should remain available under the expansion.
for token in ('"set-lockscreen-animation"', '"set-lockscreen-background"',
              '"set-lockscreen-logo-physics-hz"',
              '"set-lockscreen-entry-transition"',
              '"set-lockscreen-visualizer-enabled"',
              'root.saveLockscreenWeatherLocation()',
              'root.resetLockscreenPresentation()'):
    require(token, card, "lost lockscreen customization: " + token)

require('text: "Login sound"', sound, "login audio switch removed")
require('text: "Screenshot sounds"', sound, "screenshot master switch removed")
require('label: root.expanded ? "Fewer options" : "Options"', sound,
        "shortcut-specific settings must be behind Screenshot Options")
for token in ('onClicked: root.change("login")',
              'onClicked: root.change("enabled")',
              'key: "direct"', 'key: "satty"', 'key: "print"'):
    require(token, sound, "sound preference behavior lost: " + token)
reject('text: "Sound settings"', sound,
       "duplicate Sound header was not removed")

if 'label: "Reverse Iris"' in quick or \
   '"set-lockscreen-entry-transition", "iris"' in quick:
    raise SystemExit("FAIL: retired Iris transition reappeared")

if 'Hide Quickshell Lock Settings Before Lock Capture' in quick:
    raise SystemExit("FAIL: retired lock-capture option reappeared")

print("PASS: Independent Awtarchy Sound, Cursor and Lockscreen categories, "
      "sound options and lockscreen customization")
PY
