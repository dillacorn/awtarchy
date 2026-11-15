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
reject("soundSectionExpanded", quick,
       "sound controls must not occupy a separate full-height section")
for name in ("cursor", "lockscreen"):
    require(f"property bool {name}SectionExpanded: false", quick,
            f"{name} initial expanded state changed")
    require(f"root.{name}SectionExpanded = !root.{name}SectionExpanded",
            quick, f"{name} must expand independently")

require("id: screenshotSoundSettings", quick,
        "compact inline Sound controls must be present in Awtarchy card")
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

require('text: "Sound"', sound, "compact sound row is missing its title")
require('text: "Login"', sound, "login audio control must be inline")
require('text: "Screenshots"', sound, "screenshot audio control must be inline")
require('label: root.expanded ? "Less" : "Options"', sound,
        "shortcut-specific sound options must remain expandable")
require('property bool expanded: false', sound,
        "screenshot options must remain collapsed by default")
sound_row_start = sound.index('    RowLayout {', sound.index('id: writer'))
sound_details_start = sound.index('    ColumnLayout {', sound_row_start)
sound_row = sound[sound_row_start:sound_details_start]
for token in ('text: "Sound"', 'text: "Login"', 'text: "Screenshots"',
              'root.change("login")', 'root.change("enabled")',
              'root.expanded = !root.expanded'):
    require(token, sound_row, "sound option moved out of compact row: " + token)
if sound.count('text: "Sound"') != 1 or sound.count('    RowLayout {') != 2:
    # The second RowLayout belongs to repeated per-shortcut option rows.
    raise SystemExit("FAIL: compact Sound area must use a single default row")
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

require('anchors.margins: 6', card,
        "Awtarchy card is no longer compactly inset")
require('spacing: 3', card, "Awtarchy section spacing expanded again")
reject('text: "Pointer theme"', card, "redundant cursor subtitle returned")
reject('text: "Animation, appearance and layout"', card,
       "redundant lockscreen subtitle returned")
print("PASS: Compact inline audio controls, independent Awtarchy categories, "
      "sound options and lockscreen customization")
PY
