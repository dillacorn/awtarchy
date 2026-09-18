#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SELECTOR="$ROOT/config/quickshell/awtarchy/LockscreenCompactSelector.qml"
EDITOR="$ROOT/config/quickshell/awtarchy/LockscreenEditor.qml"
SCENE="$ROOT/config/quickshell/awtarchy-lock/LockScene.qml"
PREVIEW_SCENE="$ROOT/config/quickshell/awtarchy/LockPreviewScene.qml"
LOCK_SHELL="$ROOT/config/quickshell/awtarchy-lock/shell.qml"
BARSTATE="$ROOT/config/quickshell/awtarchy/BarState.qml"
SAVE="$ROOT/config/hypr/scripts/quickshell_lockscreen_editor_save.sh"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

contains() {
    grep -Fq -- "$2" "$1" || fail "$3"
}

not_contains() {
    if grep -Fq -- "$2" "$1"; then
        fail "$3"
    fi
}

count_at_least() {
    local file="$1"
    local pattern="$2"
    local minimum="$3"
    local message="$4"
    local count
    count="$(grep -Fc -- "$pattern" "$file" || true)"
    (( count >= minimum )) || fail "$message"
}

contains "$SELECTOR" 'property bool menuOpen: false' \
    'compact selector has no themed fly-out open state'
contains "$SELECTOR" 'property int highlightedIndex:' \
    'compact selector has no keyboard-highlighted option state'
contains "$SELECTOR" 'function openMenu()' \
    'compact selector cannot open its fly-out explicitly'
contains "$SELECTOR" 'function closeMenu()' \
    'compact selector cannot close its fly-out explicitly'
contains "$SELECTOR" 'function activateHighlighted()' \
    'compact selector cannot commit a highlighted fly-out option'
contains "$SELECTOR" 'Repeater {' \
    'compact selector does not render its option list as a fly-out'
contains "$SELECTOR" 'Keys.onEscapePressed' \
    'compact selector fly-out cannot be cancelled with Escape'
not_contains "$SELECTOR" 'mouse.x < width * 0.30' \
    'compact selector still cycles options through left/right click zones'
not_contains "$SELECTOR" 'text: "‹"' \
    'compact selector still exposes a previous-value arrow control'
not_contains "$SELECTOR" 'text: "›"' \
    'compact selector still exposes a next-value arrow control'

contains "$SELECTOR" 'property Item popupBoundary: null' \
    'compact selector cannot measure editor viewport space for adaptive fly-out direction'
contains "$SELECTOR" 'readonly property bool flyoutOpensUpward:' \
    'compact selector has no adaptive upward fly-out decision'
contains "$SELECTOR" 'const availableBelow =' \
    'compact selector does not measure space below the control'
contains "$SELECTOR" 'const availableAbove =' \
    'compact selector does not measure space above the control'
contains "$SELECTOR" 'if (availableBelow >= flyout.height)' \
    'compact selector does not prefer downward expansion when the full menu fits'
contains "$SELECTOR" 'return availableAbove > availableBelow;' \
    'compact selector does not fall back toward the roomier upward side'
count_at_least "$EDITOR" 'popupBoundary: editorFocus' 5 \
    'editor compact selectors are not all bounded to the preview viewport'
not_contains "$EDITOR" 'popupBoundary: editorFocus Layout.' \
    'compact selector popup boundary is fused to the next QML property'

# The fly-out must own its visible input area. Quickshell PopupWindow is the
# native popup surface for PanelWindow content; grabFocus dismisses it on an
# outside press instead of letting presses inside the visible menu fall through.
contains "$SELECTOR" 'import Quickshell' \
    'compact selector does not import the native Quickshell popup surface'
contains "$SELECTOR" 'PopupWindow {' \
    'compact selector fly-out is not implemented as a PopupWindow'
contains "$SELECTOR" 'anchor.item: root' \
    'compact selector popup is not anchored to the selector item'
contains "$SELECTOR" 'grabFocus: true' \
    'compact selector popup does not own/dismiss pointer focus safely'
contains "$SELECTOR" 'onVisibleChanged:' \
    'compact selector popup dismissal is not synchronized back to menu state'
contains "$SELECTOR" 'Flickable {' \
    'compact selector popup cannot scroll long option sets'
contains "$SELECTOR" 'clip: true' \
    'compact selector popup does not clip its scrollable option viewport'
contains "$SELECTOR" 'color: closedMouse.containsMouse || root.activeFocus ? Theme.hover : Theme.background' \
    'compact selector does not render a valid themed background before hover'
not_contains "$SELECTOR" 'Theme.surface' \
    'compact selector still references undefined Theme.surface'

contains "$SELECTOR" 'readonly property bool directClockToggle:' \
    'compact selector does not recognize the primary 24h/12h clock model'
contains "$SELECTOR" 'String(model[0].key || "") === "24h"' \
    'direct clock toggle is not restricted to the 24-hour key'
contains "$SELECTOR" 'String(model[1].key || "") === "12h"' \
    'direct clock toggle is not restricted to the 12-hour key'
contains "$SELECTOR" 'function toggleClockFormat()' \
    'primary clock selector has no direct toggle path'
contains "$SELECTOR" 'activateIndex(currentIndex === 0 ? 1 : 0);' \
    'primary clock selector does not switch directly between the two normalized states'
contains "$EDITOR" 'model: root.clockFormatPresets' \
    'editor clock control does not use the normalized clock-format model'
contains "$EDITOR" 'onActivated: index => root.setDraftClockFormat(root.clockFormatPresets[index].key)' \
    'primary clock toggle does not commit through the shared normalized state path'

# Extra clocks should expose a useful global timezone set rather than the old
# six-entry UI whitelist. The backend already validates arbitrary installed
# IANA zoneinfo entries.
python3 - "$EDITOR" <<'PY'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text()
match = re.search(r'readonly property var timezonePresets:\s*\[(.*?)\n\s*\]', text, re.S)
if not match:
    raise SystemExit('FAIL: timezone preset model is missing')
block = match.group(1)
zones = re.findall(r'key:\s*"([^"]+)"', block)
if len(zones) < 30:
    raise SystemExit(f'FAIL: timezone picker still exposes only {len(zones)} presets; expected at least 30')
required = {
    'America/Chicago', 'America/Denver', 'America/Phoenix',
    'Europe/Paris', 'Europe/Berlin', 'Asia/Kolkata',
    'Asia/Singapore', 'Asia/Shanghai', 'Pacific/Auckland'
}
missing = sorted(required.difference(zones))
if missing:
    raise SystemExit('FAIL: timezone picker is missing representative zones: ' + ', '.join(missing))
PY

# A timezone clock's city/zone label is optional and must survive editor,
# persistence, preview, and secure normalization with old configs defaulting on.
contains "$EDITOR" 'show_label: raw.show_label !== false' \
    'editor does not preserve the optional timezone label state'
contains "$EDITOR" 'show_label: true' \
    'new timezone clocks do not show their zone label by default'
contains "$EDITOR" 'function setTimezoneClockShowLabel(name, visible)' \
    'editor cannot toggle the timezone label independently'
contains "$EDITOR" 'root.setTimezoneClockShowLabel(' \
    'timezone element controls do not expose the label toggle'
contains "$SCENE" 'clock.show_label === false' \
    'shared renderer cannot hide UTC/Tokyo-style timezone labels'
contains "$LOCK_SHELL" 'show_label:' \
    'secure timezone normalization drops the optional label state'
contains "$BARSTATE" 'show_label:' \
    'desktop timezone normalization drops the optional label state'
contains "$SAVE" 'show_label:' \
    'timezone label state is not persisted by the editor save wrapper'
cmp -s "$SCENE" "$PREVIEW_SCENE" \
    || fail 'secure/editor scene copies diverged after timezone-label support'

contains "$EDITOR" 'function selectElement(name, additive) {' \
    'editor has no shared element selection path'
contains "$EDITOR" 'activeDrawer = "element";' \
    'element selection does not activate the Element settings drawer'
python3 - "$EDITOR" <<'PY_SELECTION'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
pattern = re.compile(
    r'if\s*\(additive\)\s*'
    r'root\.selectElement\(parent\.elementName,\s*true\);\s*'
    r'else\s+if\s*\(!root\.selectedContains\(parent\.elementName\)\)\s*'
    r'root\.selectElement\(parent\.elementName,\s*false\);\s*'
    r'else\s*root\.activeDrawer\s*=\s*"element";',
    re.S,
)
if not pattern.search(text):
    raise SystemExit(
        'FAIL: preview press selection no longer routes additive, new-single, and existing-group cases through the shared selection path'
    )
PY_SELECTION

# Selected-element transform handles must sit above overlapping element hitboxes
# so grabbing rotate/resize never selects a different element underneath.
contains "$EDITOR" 'z: root.selectedElement === elementName ? 230 : 200' \
    'selected element hitbox is not raised above overlapping sibling elements'
contains "$EDITOR" 'id: rotationHandle' \
    'rotation handle is missing'
contains "$EDITOR" 'z: 240' \
    'rotation handle is not above all editable element hitboxes'

contains "$EDITOR" 'id: settingsBarDragArea' \
    'settings bar has no plain-left-button blank-area drag surface'
contains "$EDITOR" 'cursorShape: Qt.SizeVerCursor' \
    'settings bar blank-area drag does not communicate vertical-only movement'
contains "$EDITOR" 'settingsBar.mapToItem(editorFocus, mouse.x, mouse.y)' \
    'settings bar drag does not measure pointer movement in preview coordinates'
contains "$EDITOR" 'root.settingsBarOffsetY = Math.max(0, Math.min(limit,' \
    'settings bar drag is not clamped vertically inside the preview'
not_contains "$EDITOR" 'id: settingsBarAltDrag' \
    'legacy Alt+Mouse1 settings-bar dragging still exists'
not_contains "$EDITOR" 'acceptedModifiers: Qt.AltModifier' \
    'settings-bar dragging still requires Alt'

contains "$EDITOR" 'function selectElementByName(name)' \
    'Element tab has no explicit selection action'
contains "$EDITOR" 'function elementSelectorModel()' \
    'Element tab has no selector model for built-in and dynamic elements'
contains "$EDITOR" 'Text { text: "Select Element";' \
    'Element tab has no explicit element selector label'
contains "$EDITOR" 'model: root.elementSelectorModel()' \
    'Element selector does not include the current editable element set'
contains "$EDITOR" 'root.selectElementByName(root.elementSelectorModel()[index].key)' \
    'Element selector does not select the chosen element'

contains "$EDITOR" 'Text { text: "Opacity";' \
    'selected element settings do not expose opacity'
contains "$EDITOR" 'onEditingFinished: root.setDraftOpacity(root.selectedElement, text)' \
    'selected element opacity field does not commit through the shared opacity path'
contains "$EDITOR" 'if (name === "visualizer") { const next = cloneVisualizer(draftVisualizer); next.opacity = value; draftVisualizer = next; }' \
    'visualizer opacity is not handled by the shared element opacity path'
contains "$EDITOR" 'else if (isCustomImage(name)) { const next = cloneCustomImages(draftCustomImages);' \
    'custom-image opacity is not handled by the shared element opacity path'
contains "$EDITOR" 'else if(isTimezoneClock(name)){const next=cloneTimezoneClocks(draftTimezoneClocks);next[timezoneClockIndex(name)].opacity=value;draftTimezoneClocks=next;}' \
    'timezone-clock opacity is not handled by the shared element opacity path'
contains "$EDITOR" 'else if(isCustomText(name)){const next=cloneCustomTexts(draftCustomTexts);next[customTextIndex(name)].opacity=value;draftCustomTexts=next;}' \
    'custom-text opacity is not handled by the shared element opacity path'
contains "$EDITOR" 'else { const next = cloneLayout(draftLayout); next[name].opacity = value; draftLayout = next; }' \
    'built-in element opacity is not handled by the shared element opacity path'

# Custom image opacity intentionally stays compact: numeric precision with arrow-key
# editing plus Reset/Opaque actions, without a horizontal drag slider.
contains "$EDITOR" 'id: imageOpacityField' \
    'custom image opacity numeric field is missing'
not_contains "$EDITOR" 'id: imageOpacityTrack' \
    'custom image opacity slider still exists'
contains "$EDITOR" 'function resetSelectedElementOpacity()' \
    'custom image opacity has no Reset behavior'
contains "$EDITOR" 'function toggleSelectedElementOpaque()' \
    'custom image opacity has no Opaque behavior'
contains "$EDITOR" 'SettingsButton { label: "Reset"; textSize: 9; onClicked: root.resetSelectedElementOpacity() }' \
    'custom image opacity has no Reset button'
contains "$EDITOR" 'SettingsButton { label: "Opaque"; textSize: 9; active: Math.round(root.elementOpacity(root.selectedElement)) === 100; onClicked: root.toggleSelectedElementOpaque() }' \
    'custom image opacity has no Opaque button'

# Keep the final editor usability contracts together so runtime candidates
# cannot regress selector input ownership, timezone controls, transform priority,
# image opacity, direct selection, or bar drag.
printf 'PASS: lockscreen selector input ownership, timezone, transforms, opacity, and settings-bar contracts\n'
