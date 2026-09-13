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

contains "$EDITOR" 'onClicked: root.setDraftClockFormat(root.draftClockFormat === "24h" ? "12h" : "24h")' \
    'primary clock format toggle does not use the shared normalized state path'
contains "$EDITOR" 'label: root.draftClockFormat === "24h" ? "24-hour" : "12-hour"' \
    'primary clock toggle does not show its current format directly'

printf 'PASS: lockscreen themed fly-out selector and clock toggle contracts\n'
