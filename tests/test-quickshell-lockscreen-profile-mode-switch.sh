#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
EDITOR="$ROOT/config/quickshell/awtarchy/LockscreenEditor.qml"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
require_text() { grep -Fq -- "$2" "$1" || fail "$3"; }

require_text "$EDITOR" 'property bool sharedSwitchConfirmOpen:' 'Shared switch has no confirmation state'
require_text "$EDITOR" 'property string sharedSwitchMonitorName:' 'Shared switch does not pin the target monitor'
require_text "$EDITOR" 'function confirmUseExistingShared()' 'Shared switch cannot choose the existing Shared profile'
require_text "$EDITOR" 'function confirmPromoteIndividualToShared()' 'Shared switch cannot promote the current display to Shared'
require_text "$EDITOR" 'function cancelUseSharedConfiguration()' 'Shared switch has no cancel action'
require_text "$EDITOR" 'Use Existing Shared' 'Shared switch dialog is missing the existing Shared choice'
require_text "$EDITOR" 'Use This Display as Shared' 'Shared switch dialog is missing the promote-display choice'
require_text "$EDITOR" 'Individual configuration will be removed' 'Shared switch dialog does not warn about losing the Individual configuration'

python3 - "$EDITOR" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding='utf-8')

def between(start, end):
    a = text.find(start)
    b = text.find(end, a + len(start))
    if a < 0 or b < 0:
        raise SystemExit(f'FAIL: could not inspect {start}')
    return text[a:b]

request = between('function useSharedConfiguration()', 'function confirmUseExistingShared()')
if 'sharedSwitchConfirmOpen = true' not in request:
    raise SystemExit('FAIL: Use Shared does not open confirmation')
if 'delete next[activeMonitorName]' in request or 'delete next[sharedSwitchMonitorName]' in request:
    raise SystemExit('FAIL: Use Shared still deletes the Individual profile before confirmation')

existing = between('function confirmUseExistingShared()', 'function confirmPromoteIndividualToShared()')
for needle in (
    'delete next[targetName]',
    'loadProfileIntoDraft(draftSharedProfile)',
    'sharedSwitchConfirmOpen = false',
):
    if needle not in existing:
        raise SystemExit(f'FAIL: existing Shared conversion missing {needle}')

promote = between('function confirmPromoteIndividualToShared()', 'function cancelUseSharedConfiguration()')
for needle in (
    'const promoted = cloneSnapshot(profileFromDraftScalars())',
    'draftSharedProfile = promoted',
    'settledSharedProfile = cloneSnapshot(promoted)',
    'delete next[targetName]',
    'sharedSwitchConfirmOpen = false',
):
    if needle not in promote:
        raise SystemExit(f'FAIL: promote-to-Shared conversion missing {needle}')

cancel = between('function cancelUseSharedConfiguration()', 'function copyConfigurationTo(')
if 'sharedSwitchConfirmOpen = false' not in cancel:
    raise SystemExit('FAIL: cancel does not close Shared switch confirmation')
if 'draftMonitorOverrides' in cancel or 'draftSharedProfile' in cancel:
    raise SystemExit('FAIL: cancel mutates profile drafts')

print('PASS: lockscreen Shared/Individual mode switching is non-destructive')
PY
