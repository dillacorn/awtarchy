#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
EDITOR="$ROOT/config/quickshell/awtarchy/LockscreenEditor.qml"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

python3 - "$EDITOR" <<'PY'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")

required = [
    'property var draftSharedProfile:',
    'property var draftMonitorOverrides:',
    'property string activeMonitorName:',
    'property bool profileLoadActive:',
    'property var profileUndoStacks:',
    'property var profileRedoStacks:',
    'function profileFromDraftScalars()',
    'function flushActiveProfile()',
    'function loadProfileIntoDraft(profile)',
    'function effectiveProfileForMonitor(name)',
    'function useIndividualConfiguration()',
    'function useSharedConfiguration()',
    'function copyConfigurationTo(name)',
    'function copyConfigurationToAllOthers()',
    'function switchActiveMonitor(name)',
    'function reconcileActiveMonitor()',
    'BarState.lockscreenSharedProfile()',
    'BarState.lockscreenMonitorOverrides()',
    '"--profiles"',
    'effectiveProfileForMonitor(modelData.name)',
    'Copy Configuration To',
    'Use Individual Configuration',
    'Use Shared Configuration',
]
for needle in required:
    if needle not in text:
        raise SystemExit(f"FAIL: missing multi-monitor editor contract: {needle}")

# QML rejects duplicate property declarations while constructing the singleton.
# Keep the session/profile state single-owned so the desktop shell can start.
singleton_properties = [
    'property var draftSharedProfile:',
    'property var draftMonitorOverrides:',
    'property string activeMonitorName:',
    'property bool profileLoadActive:',
    'property var profileUndoStacks:',
    'property var profileRedoStacks:',
]
for declaration in singleton_properties:
    count = text.count(declaration)
    if count != 1:
        raise SystemExit(
            f'FAIL: lockscreen editor property must be declared exactly once: '
            f'{declaration} (found {count})'
        )

# Monitor switching must operate only on the in-memory session and never reload
# persisted state. Persisted state is loaded when the editor session opens.
switch = re.search(r'function switchActiveMonitor\(name\)\s*\{(.*?)\n\s*\}', text, re.S)
if not switch:
    raise SystemExit('FAIL: switchActiveMonitor body missing')
if 'loadPersistedDraft' in switch.group(1):
    raise SystemExit('FAIL: monitor switching reloads persisted state')
if 'flushActiveProfile' not in switch.group(1) or 'loadProfileIntoDraft' not in switch.group(1):
    raise SystemExit('FAIL: monitor switching does not flush/load in-memory profiles')

open_body = re.search(r'function openForScreen\(target\)\s*\{(.*?)\n\s*\}', text, re.S)
if not open_body or open_body.group(1).count('loadPersistedDraft()') != 1:
    raise SystemExit('FAIL: editor open must load persisted profiles exactly once')

save_body = re.search(r'function save\(\)\s*\{(.*?)\n\s*\}', text, re.S)
if not save_body:
    raise SystemExit('FAIL: save body missing')
for needle in ('flushActiveProfile()', 'JSON.stringify(draftSharedProfile)', 'JSON.stringify(draftMonitorOverrides)'):
    if needle not in save_body.group(1):
        raise SystemExit(f'FAIL: atomic profile save missing {needle}')

# Passive previews must resolve their own profile rather than mirroring active
# scalar state. The active editor remains the only focusable/interactive surface.
if 'readonly property var monitorProfile: root.effectiveProfileForMonitor(modelData.name)' not in text:
    raise SystemExit('FAIL: passive preview has no effective monitor profile')
if 'focusable: false' not in text:
    raise SystemExit('FAIL: passive preview became focusable')
if 'secondaryWallpaperState' not in text or 'monitorProfile.lockscreen_wallpaper_path' not in text:
    raise SystemExit('FAIL: passive preview wallpaper is still shared with active monitor')

# Undo/redo state must be partitioned by Shared vs monitor profile identity.
for needle in ('function activeProfileKey()', 'stashHistoryForActiveProfile()', 'restoreHistoryForActiveProfile()'):
    if needle not in text:
        raise SystemExit(f'FAIL: profile-safe history missing {needle}')

print('PASS: lockscreen multi-monitor editor contracts')
PY
