#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SELECTOR="$ROOT/config/quickshell/awtarchy/LockscreenCompactSelector.qml"
EDITOR="$ROOT/config/quickshell/awtarchy/LockscreenEditor.qml"

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
contains "$SELECTOR" 'y: root.flyoutOpensUpward ? -height - 4 : root.height + 4' \
    'compact selector does not place its menu above or below according to available space'
count_at_least "$EDITOR" 'popupBoundary: editorFocus' 5 \
    'editor compact selectors are not all bounded to the preview viewport'

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
contains "$SELECTOR" 'visible: root.menuOpen && !root.directClockToggle' \
    'primary clock toggle can still open the option fly-out'
contains "$SELECTOR" '? (currentIndex === 0 ? "24-hour" : "12-hour")' \
    'primary clock toggle does not show its current format directly'
contains "$EDITOR" 'model: root.clockFormatPresets' \
    'editor clock control does not use the normalized clock-format model'
contains "$EDITOR" 'onActivated: index => root.setDraftClockFormat(root.clockFormatPresets[index].key)' \
    'primary clock toggle does not commit through the shared normalized state path'

contains "$EDITOR" 'function selectElement(name, additive) {' \
    'editor has no shared element selection path'
contains "$EDITOR" 'activeDrawer = "element";' \
    'element selection does not activate the Element settings drawer'
contains "$EDITOR" 'if (additive) root.selectElement(parent.elementName, true);' \
    'additive preview selection does not use the shared element selection path'
contains "$EDITOR" 'else if (!root.selectedContains(parent.elementName)) root.selectElement(parent.elementName, false);' \
    'new single-element preview selection does not use the shared element selection path'
contains "$EDITOR" 'else root.activeDrawer = "element";' \
    'pressing an already-selected group member does not expose Element settings while preserving the group'

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

printf 'PASS: lockscreen adaptive selectors, element settings, opacity, and settings-bar drag contracts\n'
