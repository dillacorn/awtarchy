#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
EDITOR="$ROOT/config/quickshell/awtarchy/LockscreenEditor.qml"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
contains() { grep -Fq -- "$2" "$1" || fail "$3"; }
rejects() { ! grep -Fq -- "$2" "$1" || fail "$3"; }

contains "$EDITOR" 'property var draftMonitorProfiles:' 'editor has no per-display profile draft map'
contains "$EDITOR" 'property var draftLastEditedProfile:' 'editor has no last-edited seed profile'
contains "$EDITOR" 'property string activeMonitorName:' 'editor has no active monitor identity'
contains "$EDITOR" 'function profileFromDraftScalars()' 'editor cannot snapshot a complete profile'
contains "$EDITOR" 'function flushActiveProfile()' 'editor cannot flush the active monitor profile'
contains "$EDITOR" 'function effectiveProfileForMonitor(name)' 'editor cannot resolve passive monitor previews'
contains "$EDITOR" 'function copyConfigurationTo(name)' 'editor lost explicit copy-to-display'
contains "$EDITOR" 'function copyConfigurationToAllOthers()' 'editor lost copy-to-all-other-displays'
contains "$EDITOR" 'function switchActiveMonitor(name)' 'editor cannot switch active displays'
contains "$EDITOR" 'function reconcileActiveMonitor()' 'editor cannot reconcile topology changes'
contains "$EDITOR" 'BarState.lockscreenMonitorProfiles()' 'editor does not load persisted per-display profiles'
contains "$EDITOR" 'BarState.lockscreenLastEditedProfile()' 'editor does not load last-edited profile'
contains "$EDITOR" 'JSON.stringify(draftMonitorProfiles)' 'Ctrl+S does not save per-display profiles'
contains "$EDITOR" 'JSON.stringify(draftLastEditedProfile)' 'Ctrl+S does not save last-edited profile'
contains "$EDITOR" 'JSON.stringify(draftSavedProfiles)' 'Ctrl+S does not save reusable configurations'

rejects "$EDITOR" 'property var draftSharedProfile:' 'Shared draft state still exists'
rejects "$EDITOR" 'property var draftMonitorOverrides:' 'Individual override state still exists'
rejects "$EDITOR" 'property var settledSharedProfile:' 'settled Shared preview state still exists'
rejects "$EDITOR" 'property bool sharedPreviewHoldActive:' 'Shared preview hold state still exists'
rejects "$EDITOR" 'property bool sharedSwitchConfirmOpen:' 'Shared switch modal state still exists'
rejects "$EDITOR" 'Use Shared Configuration' 'Shared mode UI still exists'
rejects "$EDITOR" 'Use Individual Configuration' 'Individual mode UI still exists'
rejects "$EDITOR" 'Use Existing Shared' 'Shared conversion dialog still exists'
rejects "$EDITOR" 'Use This Display as Shared' 'Shared promotion dialog still exists'
rejects "$EDITOR" 'function applySavedConfigurationToShared(' 'saved configurations still target Shared mode'

BAR="$ROOT/config/quickshell/awtarchy/BarState.qml"
rejects "$BAR" 'function lockscreenSharedProfile()' 'BarState still exposes active Shared profile facade'
rejects "$BAR" 'function lockscreenMonitorOverrides()' 'BarState still exposes active Individual override facade'

python3 - "$EDITOR" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")

def body(name):
    marker = f"function {name}("
    start = text.find(marker)
    if start < 0:
        raise SystemExit(f"FAIL: missing function {name}")
    brace = text.find("{", start)
    depth = 0
    quote = None
    escape = False
    for i in range(brace, len(text)):
        ch = text[i]
        if quote is not None:
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == quote:
                quote = None
            continue
        if ch in ('"', "'"):
            quote = ch
            continue
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return text[brace + 1:i]
    raise SystemExit(f"FAIL: unterminated function {name}")

load = body("loadPersistedDraft")
for needle in (
    "BarState.lockscreenMonitorProfiles()",
    "BarState.lockscreenLastEditedProfile()",
    "draftMonitorProfiles",
    "draftLastEditedProfile",
    "Quickshell.screens",
):
    if needle not in load:
        raise SystemExit(f"FAIL: editor load is missing {needle}")
if "lockscreenSharedProfile" in load or "lockscreenMonitorOverrides" in load:
    raise SystemExit("FAIL: editor still loads Shared/Individual state")

flush = body("flushActiveProfile")
for needle in (
    "draftMonitorProfiles",
    "activeMonitorName",
    "profileFromDraftScalars()",
    "draftLastEditedProfile",
):
    if needle not in flush:
        raise SystemExit(f"FAIL: active monitor flush is missing {needle}")
if "draftSharedProfile" in flush or "draftMonitorOverrides" in flush:
    raise SystemExit("FAIL: active monitor flush still writes Shared/Individual state")

switch = body("switchActiveMonitor")
if "loadPersistedDraft" in switch:
    raise SystemExit("FAIL: monitor switching reloads persisted state")
for needle in ("flushActiveProfile()", "draftMonitorProfiles", "loadProfileIntoDraft"):
    if needle not in switch:
        raise SystemExit(f"FAIL: monitor switching is missing {needle}")

copy_one = body("copyConfigurationTo")
if "draftMonitorProfiles" not in copy_one:
    raise SystemExit("FAIL: copy-to-display does not replace the target display profile")
if "draftMonitorOverrides" in copy_one:
    raise SystemExit("FAIL: copy-to-display still writes Individual overrides")

copy_all = body("copyConfigurationToAllOthers")
if "draftMonitorProfiles" not in copy_all or "Quickshell.screens" not in copy_all:
    raise SystemExit("FAIL: copy-to-all does not update connected display profiles")
if "draftMonitorOverrides" in copy_all:
    raise SystemExit("FAIL: copy-to-all still writes Individual overrides")

save = body("save")
for needle in (
    "flushActiveProfile()",
    "JSON.stringify(draftMonitorProfiles)",
    "JSON.stringify(draftLastEditedProfile)",
    "JSON.stringify(draftSavedProfiles)",
):
    if needle not in save:
        raise SystemExit(f"FAIL: atomic editor save is missing {needle}")

if 'readonly property var monitorProfile: root.effectiveProfileForMonitor(modelData.name)' not in text:
    raise SystemExit("FAIL: passive previews do not resolve their own monitor profile")
if "focusable: false" not in text:
    raise SystemExit("FAIL: passive preview became focusable")

active_key = body("activeProfileKey")
if '"monitor:" + activeMonitorName' not in active_key:
    raise SystemExit("FAIL: undo/redo history is not keyed only by monitor identity")
if "shared" in active_key.lower():
    raise SystemExit("FAIL: undo/redo history still has Shared identity")

print("PASS: lockscreen per-display editor session contracts")
PY
