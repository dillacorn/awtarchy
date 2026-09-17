#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL="$ROOT/config/quickshell/awtarchy-lock/shell.qml"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
require_text() {
    local file="$1" text="$2" message="$3"
    grep -Fq -- "$text" "$file" || fail "$message"
}

# Capture cleanup is global, but presentation transition duration is profile-local.
# The capture directory must remain alive long enough for the slowest monitor.
require_text "$SHELL" 'readonly property int captureCleanupTransitionDuration:' \
    'secure shell has no global cleanup duration derived from monitor profiles'
require_text "$SHELL" 'root.lockSharedProfile.lockscreen_entry_transition_duration' \
    'capture cleanup does not include the Shared transition duration'
require_text "$SHELL" 'root.lockMonitorOverrides' \
    'capture cleanup does not inspect Individual monitor transitions'
require_text "$SHELL" 'Math.max(maximum, Number(profile.lockscreen_entry_transition_duration))' \
    'capture cleanup does not select the slowest monitor transition'
require_text "$SHELL" 'root.captureCleanupTransitionDuration + 2000' \
    'capture cleanup timer does not use the slowest effective transition duration'

printf '%s\n' 'PASS: transition captures survive the slowest monitor profile reveal'
