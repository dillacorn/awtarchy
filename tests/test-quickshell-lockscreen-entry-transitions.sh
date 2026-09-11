#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STATE="$ROOT/config/hypr/scripts/quickshell_application_state.sh"
BAR_STATE="$ROOT/config/quickshell/awtarchy/BarState.qml"
EDITOR="$ROOT/config/quickshell/awtarchy/LockscreenEditor.qml"
QUICK_SETTINGS="$ROOT/config/quickshell/awtarchy/QuickSettings.qml"
SCENE="$ROOT/config/quickshell/awtarchy-lock/LockScene.qml"
PREVIEW_SCENE="$ROOT/config/quickshell/awtarchy/LockPreviewScene.qml"
SURFACE="$ROOT/config/quickshell/awtarchy-lock/LockSurface.qml"
SHELL="$ROOT/config/quickshell/awtarchy-lock/shell.qml"
AUTH="$ROOT/config/quickshell/awtarchy-lock/LockAuth.qml"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

contains() {
    local file="$1" needle="$2" message="$3"
    grep -Fq -- "$needle" "$file" || fail "$message"
}

rejects() {
    local file="$1" needle="$2" message="$3"
    ! grep -Fq -- "$needle" "$file" || fail "$message"
}

contains "$STATE" 'LOCKSCREEN_ENTRY_TRANSITIONS_JSON=' \
    'entry transition allowlist is missing'
for key in fade pixel iris edges wipe; do
    grep -Fq -- "\"$key\"" "$STATE" || fail "state allowlist is missing transition: $key"
done
contains "$STATE" 'validate_lockscreen_entry_transition()' \
    'entry transition validator is missing'
contains "$STATE" 'set_lockscreen_entry_transition()' \
    'entry transition setter is missing'
contains "$STATE" 'set-lockscreen-entry-transition)' \
    'entry transition command dispatch is missing'
contains "$STATE" '.lockscreen_entry_transition = "fade"' \
    'Awtarchy reset does not restore Fade entry transition'

TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT
mkdir -p "$TMP/cache/awtarchy" "$TMP/home"
printf '%s\n' '{}' >"$TMP/cache/awtarchy/quickshell-state.json"

run_state() {
    HOME="$TMP/home" XDG_CACHE_HOME="$TMP/cache" \
        bash "$STATE" "$@"
}

run_state set-lockscreen-entry-transition pixel
[[ "$(jq -r '.lockscreen_entry_transition' "$TMP/cache/awtarchy/quickshell-state.json")" == pixel ]] \
    || fail 'entry transition setter did not persist pixel'
if run_state set-lockscreen-entry-transition glitch >/dev/null 2>&1; then
    fail 'invalid entry transition was accepted'
fi
[[ "$(jq -r '.lockscreen_entry_transition' "$TMP/cache/awtarchy/quickshell-state.json")" == pixel ]] \
    || fail 'invalid transition attempt changed persisted state'

contains "$BAR_STATE" 'lockscreenEntryTransitionPresets' \
    'BarState transition presets are missing'
contains "$BAR_STATE" 'lockscreen_entry_transition: "fade"' \
    'BarState empty state does not default to Fade'
contains "$BAR_STATE" 'function lockscreenEntryTransition()' \
    'BarState transition reader is missing'
for label in Fade Pixel 'Reverse Iris' Edges Wipe; do
    grep -Fq -- "label: \"$label\"" "$BAR_STATE" \
        || fail "BarState preset label is missing: $label"
done

contains "$SHELL" 'property string lockEntryTransition: "fade"' \
    'secure shell transition state is missing'
contains "$SHELL" 'function normalizedEntryTransition(value)' \
    'secure shell transition normalization is missing'
contains "$SHELL" 'lockEntryTransition = normalizedEntryTransition(parsed.lockscreen_entry_transition);' \
    'secure shell does not load persisted entry transition'
contains "$SHELL" 'entryTransition: root.lockEntryTransition' \
    'secure shell does not pass entry transition to lock surfaces'

contains "$SURFACE" 'required property string entryTransition' \
    'secure surface entry transition property is missing'
contains "$SURFACE" 'entryTransition: root.entryTransition' \
    'secure surface does not pass transition to the scene'
contains "$SURFACE" 'scene.securePasswordEntryOpacity' \
    'secure password presentation is not gated by entry reveal state'
contains "$SURFACE" 'inputMethodHints: Qt.ImhSensitiveData' \
    'secure password input lost sensitive-data handling'
contains "$SURFACE" 'auth.submit(response)' \
    'secure password submit path changed'

rejects "$AUTH" 'entryTransition' \
    'authentication owner must not consume entry transition state'
rejects "$AUTH" 'lockscreen_entry_transition' \
    'authentication owner must not consume persisted transition state'

cmp -s "$SCENE" "$PREVIEW_SCENE" \
    || fail 'secure and preview scene copies diverged'
contains "$SCENE" 'required property string entryTransition' \
    'scene entry transition property is missing'
contains "$SCENE" 'property int entryTransitionReplayToken: 0' \
    'scene replay token is missing'
contains "$SCENE" 'function replayEntryTransition()' \
    'scene replay function is missing'
contains "$SCENE" 'readonly property int entryTileColumns: 24' \
    'entry transition tile column bound changed'
contains "$SCENE" 'readonly property int entryTileRows: 14' \
    'entry transition tile row bound changed'
contains "$SCENE" 'root.entryTileColumns * root.entryTileRows' \
    'pixel/iris transitions are not bounded by the fixed tile grid'
for key in pixel iris edges wipe; do
    grep -Fq -- "\"$key\"" "$SCENE" || fail "scene transition implementation is missing: $key"
done
rejects "$SCENE" 'ShaderEffect' \
    'entry transitions must not add a shader path'

contains "$EDITOR" 'property string draftEntryTransition: "fade"' \
    'editor transition draft is missing'
contains "$EDITOR" 'property int entryTransitionReplayToken: 0' \
    'editor replay token is missing'
contains "$EDITOR" 'entryTransition: root.draftEntryTransition' \
    'editor preview does not use the draft transition'
contains "$EDITOR" 'entryTransitionReplayToken: root.entryTransitionReplayToken' \
    'editor preview does not receive replay requests'
contains "$EDITOR" 'function replayEntryTransition()' \
    'editor Replay Transition action is missing'
contains "$EDITOR" 'draftEntryTransition = BarState.lockscreenEntryTransition();' \
    'editor does not load persisted transition state'
contains "$EDITOR" 'entryTransition: draftEntryTransition' \
    'editor history snapshot does not include entry transition'
contains "$EDITOR" 'String(draftEntryTransition)' \
    'editor atomic save does not include entry transition'
contains "$EDITOR" 'text: "Entry Transition"' \
    'editor transition control heading is missing'
contains "$EDITOR" 'label: "Replay Transition"' \
    'editor Replay Transition button is missing'

contains "$QUICK_SETTINGS" 'text: "Entry Transition"' \
    'Quick Settings transition heading is missing'
for label in Fade Pixel 'Reverse Iris' Edges Wipe; do
    grep -Fq -- "label: \"$label\"" "$QUICK_SETTINGS" \
        || fail "Quick Settings transition option is missing: $label"
done
contains "$QUICK_SETTINGS" '"set-lockscreen-entry-transition"' \
    'Quick Settings transition controls do not persist through the state helper'

printf '%s\n' 'PASS: lockscreen entry transitions are persisted, previewable, bounded, selectable in Quick Settings, and isolated from authentication.'
