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

printf 'PASS: lockscreen themed fly-out selector and clock toggle contracts\n'
