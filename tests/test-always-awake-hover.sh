#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLTIP="$ROOT/config/quickshell/awtarchy/BarTooltip.qml"
BAR="$ROOT/config/quickshell/awtarchy/Bar.qml"
SYSTEM_STATE="$ROOT/config/quickshell/awtarchy/SystemState.qml"
INHIBITOR="$ROOT/config/hypr/scripts/idle_inhibitor_global.sh"
MANAGED_HISTORY="$ROOT/local/share/awtarchy/quickshell-managed-history.sha256"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

require_file_text() {
    local file="$1" needle="$2" message="$3"
    grep -Fq -- "$needle" "$file" || fail "$message"
}

# The normal eye click remains the fast Keep Awake action. Hovering the eye
# exposes the stronger mode, but it must be explicit about the safety tradeoff.
require_file_text "$TOOLTIP" 'readonly property bool idleControl:' \
    'bar tooltip does not identify the idle-eye control'
require_file_text "$TOOLTIP" 'text: "Always Awake"' \
    'idle-eye hover card does not expose the Always Awake control'
require_file_text "$TOOLTIP" 'text: "Keeps the session unlocked and displays on after 4 hours idle."' \
    'idle-eye hover card does not explain the stronger mode'
require_file_text "$TOOLTIP" '"Enable Always Awake (Not Recommended)"' \
    'Always Awake enable action lacks the not-recommended warning'
require_file_text "$TOOLTIP" '"Recommended: click the eye to toggle Keep Awake. The 4-hour safety stays active."' \
    'idle-eye hover card does not recommend normal Keep Awake'
require_file_text "$TOOLTIP" 'SystemState.setIdleMode(' \
    'idle-eye hover card cannot select the shared Always Awake mode'
require_file_text "$TOOLTIP" 'SystemState.idleMode === "always-awake" ? "off" : "always-awake"' \
    'idle-eye hover card does not toggle the explicit Always Awake mode'
require_file_text "$TOOLTIP" 'text: SystemState.alwaysAwakePersistent ? "" : ""' \
    'Always Awake does not expose locked/unlocked persistence icons'
require_file_text "$TOOLTIP" 'color: SystemState.alwaysAwakePersistent ? Theme.urgent : Theme.foreground' \
    'persistent Always Awake lock is not visually red while the unlocked icon uses normal foreground'
require_file_text "$TOOLTIP" 'visible: SystemState.idleMode === "always-awake"' \
    'Always Awake persistence lock is visible outside Always Awake mode'
require_file_text "$TOOLTIP" 'SystemState.setAlwaysAwakePersistent(' \
    'Always Awake lock button does not toggle shared persistence state'
require_file_text "$SYSTEM_STATE" 'property bool alwaysAwakePersistent: false' \
    'SystemState does not track persistent Always Awake'
require_file_text "$SYSTEM_STATE" 'function setAlwaysAwakePersistent(locked)' \
    'SystemState cannot toggle persistent Always Awake'
require_file_text "$INHIBITOR" 'ALWAYS_AWAKE_LOCK_FILE=' \
    'idle inhibitor has no persistent Always Awake state file'
require_file_text "$INHIBITOR" 'restore_persistent_always_awake' \
    'idle inhibitor cannot restore persistent Always Awake after restart'
require_file_text "$INHIBITOR" 'lock-always-awake)' \
    'idle inhibitor lacks the persistence lock action'
require_file_text "$INHIBITOR" 'unlock-always-awake)' \
    'idle inhibitor lacks the persistence unlock action'
require_file_text "$TOOLTIP" 'width: root.idleControl ? popup.width : 0' \
    'idle-eye hover card is not pointer-interactive while normal tooltips remain click-through'
require_file_text "$TOOLTIP" 'acceptedButtons: Qt.NoButton' \
    'idle hover surface does not preserve non-button hover tracking'
require_file_text "$BAR" 'onRightClicked: SystemState.toggleIdle()' \
    'horizontal idle eye no longer keeps right-click as normal Keep Awake'

# On a top bar, Keep Awake stays nearest the bar and the stronger Always Awake
# action moves below it. Bottom, left, and right bars keep the existing ordering.
require_file_text "$TOOLTIP" 'readonly property string barPosition:' \
    'idle-eye hover card does not resolve the bar edge'
require_file_text "$TOOLTIP" 'BarState.positionFor(monitorName)' \
    'idle-eye hover card does not use the monitor-specific bar position'
require_file_text "$TOOLTIP" 'readonly property bool keepAwakeFirst: idleControl && barPosition === "top"' \
    'top-bar hover card does not select Keep Awake as the near-bar section'
require_file_text "$TOOLTIP" 'Layout.row: root.keepAwakeFirst ? 2 : 0' \
    'Always Awake section does not move away from a top bar'
require_file_text "$TOOLTIP" 'Layout.row: root.keepAwakeFirst ? 0 : 2' \
    'Keep Awake section does not move next to a top bar'

current_entry="$(sha256sum "$TOOLTIP" | awk '{print $1}')"$'\t'".config/quickshell/awtarchy/BarTooltip.qml"
grep -Fqx -- "$current_entry" "$MANAGED_HISTORY" \
    || fail "managed history is missing current stock hash for BarTooltip.qml: $current_entry"

printf '%s\n' 'PASS: idle-eye hover exposes the warned Always Awake control with edge-aware ordering.'
