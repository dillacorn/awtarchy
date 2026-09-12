#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STATE="$ROOT/config/hypr/scripts/quickshell_application_state.sh"
BAR_STATE="$ROOT/config/quickshell/awtarchy/BarState.qml"
EDITOR="$ROOT/config/quickshell/awtarchy/LockscreenEditor.qml"
SCENE="$ROOT/config/quickshell/awtarchy-lock/LockScene.qml"
PREVIEW_SCENE="$ROOT/config/quickshell/awtarchy/LockPreviewScene.qml"
SURFACE="$ROOT/config/quickshell/awtarchy-lock/LockSurface.qml"
SHELL="$ROOT/config/quickshell/awtarchy-lock/shell.qml"
LAYER="$ROOT/config/quickshell/awtarchy-lock/LockTransitionLayer.qml"
PREVIEW_LAYER="$ROOT/config/quickshell/awtarchy/LockPreviewTransitionLayer.qml"
AUTH="$ROOT/config/quickshell/awtarchy-lock/LockAuth.qml"
PERMANENT_WORKFLOW="$ROOT/.github/workflows/validate-quickshell-lockscreen-interactive-effects.yml"

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

[[ -f "$LAYER" ]] || fail 'shared LockTransitionLayer.qml is missing'
cmp -s "$SCENE" "$PREVIEW_SCENE" \
    || fail 'secure and preview scene copies diverged'

# Persisted transition choice remains allowlisted and duration is the approved
# slower 1.8s default with an 0.8-6.0s defensive range everywhere.
contains "$STATE" 'LOCKSCREEN_ENTRY_TRANSITIONS_JSON=' \
    'entry transition allowlist is missing'
for key in fade pixel iris edges wipe; do
    grep -Fq -- "\"$key\"" "$STATE" || fail "state allowlist is missing transition: $key"
done
contains "$STATE" 'validate_lockscreen_entry_transition()' \
    'entry transition validator is missing'
contains "$STATE" 'set-lockscreen-entry-transition)' \
    'entry transition command dispatch is missing'
contains "$STATE" '.lockscreen_entry_transition_duration = 1800' \
    'state reset/default does not restore the approved 1800ms duration'
contains "$STATE" '800 6000' \
    'state helper does not enforce the approved 800-6000ms duration range'

TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT
mkdir -p "$TMP/cache/awtarchy" "$TMP/home"
printf '%s\n' '{}' >"$TMP/cache/awtarchy/quickshell-state.json"
run_state() {
    HOME="$TMP/home" XDG_CACHE_HOME="$TMP/cache" bash "$STATE" "$@"
}

layout='{"logo":{"x":0.5,"y":0.34},"time":{"x":0.5,"y":0.51},"date":{"x":0.5,"y":0.555},"username":{"x":0.5,"y":0.595},"weather":{"x":0.5,"y":0.635},"password":{"x":0.5,"y":0.7}}'
visibility='{"logo":true,"time":false,"date":false,"username":false,"weather":false,"password":true}'
visualizer='{"enabled":false,"shape":"straight","sensitivity":140,"performance":"balanced"}'
save_duration() {
    local duration="$1"
    run_state save-lockscreen-editor "$layout" "$visibility" black '#000000' '' \
        cover 0.5 0.5 none 0 0 auto '[]' "$visualizer" 100 pixel "$duration"
}

save_duration 800
[[ "$(jq -r '.lockscreen_entry_transition_duration' "$TMP/cache/awtarchy/quickshell-state.json")" == 800 ]] \
    || fail '800ms lower duration boundary was not persisted'
save_duration 6000
[[ "$(jq -r '.lockscreen_entry_transition_duration' "$TMP/cache/awtarchy/quickshell-state.json")" == 6000 ]] \
    || fail '6000ms upper duration boundary was not persisted'
duration_state_before="$(sha256sum "$TMP/cache/awtarchy/quickshell-state.json" | awk '{print $1}')"
if save_duration 799 >/dev/null 2>&1; then
    fail 'transition duration below 800ms was accepted'
fi
[[ "$(sha256sum "$TMP/cache/awtarchy/quickshell-state.json" | awk '{print $1}')" == "$duration_state_before" ]] \
    || fail 'invalid low duration partially changed persisted state'
if save_duration 6001 >/dev/null 2>&1; then
    fail 'transition duration above 6000ms was accepted'
fi
[[ "$(sha256sum "$TMP/cache/awtarchy/quickshell-state.json" | awk '{print $1}')" == "$duration_state_before" ]] \
    || fail 'invalid high duration partially changed persisted state'
run_state reset-lockscreen-presentation
[[ "$(jq -r '.lockscreen_entry_transition_duration' "$TMP/cache/awtarchy/quickshell-state.json")" == 1800 ]] \
    || fail 'reset-lockscreen-presentation did not restore 1800ms transition duration'

contains "$BAR_STATE" 'lockscreen_entry_transition: "fade"' \
    'BarState empty state does not default to Fade'
contains "$BAR_STATE" '? Math.max(800, Math.min(6000, value)) : 1800;' \
    'BarState does not clamp persisted duration to 800-6000ms with an 1800ms fallback'
contains "$BAR_STATE" 'function lockscreenEntryTransition()' \
    'BarState transition reader is missing'
contains "$BAR_STATE" 'function lockscreenEntryTransitionDuration()' \
    'BarState duration reader is missing'

contains "$SHELL" 'property string lockEntryTransition: "fade"' \
    'secure shell transition state is missing'
contains "$SHELL" 'property int lockEntryTransitionDuration: 1800' \
    'secure shell does not use the approved 1800ms default'
contains "$SHELL" 'Math.max(800, Math.min(6000' \
    'secure shell does not clamp transition duration to 800-6000ms'
contains "$SHELL" 'entryTransition: root.lockEntryTransition' \
    'secure shell does not pass entry transition to lock surfaces'
contains "$SHELL" 'entryTransitionDuration: root.lockEntryTransitionDuration' \
    'secure shell does not pass transition duration to lock surfaces'

# The secure runtime and unlocked editor both use the same shared renderer.
contains "$LAYER" 'property Item startSource' \
    'shared transition layer lacks a source input'
contains "$LAYER" 'property Item endSource' \
    'shared transition layer lacks a destination input'
contains "$LAYER" 'Math.max(800, Math.min(6000' \
    'shared transition layer does not clamp duration to 800-6000ms'
contains "$LAYER" ': 1800' \
    'shared transition layer lost its 1800ms fallback'
contains "$LAYER" 'smooth: false' \
    'shared pixel transition is not nearest-neighbor'
contains "$LAYER" 'textureSize:' \
    'shared pixel transition does not perform resolution collapse'
contains "$SURFACE" 'LockTransitionLayer {' \
    'secure surface does not use the shared transition renderer'
contains "$SURFACE" 'startSource: desktopBacking' \
    'secure transition does not begin from the frozen desktop'
contains "$SURFACE" 'endSource: securePresentation' \
    'secure transition does not end at the actual lockscreen presentation'

contains "$EDITOR" 'property int draftEntryTransitionDuration: 1800' \
    'editor does not use the approved 1800ms draft default'
contains "$EDITOR" 'Math.max(800, Math.min(6000' \
    'editor does not clamp transition duration to 800-6000ms'
[[ -f "$PREVIEW_LAYER" ]] || fail 'config-local preview transition renderer is missing'
cmp -s "$LAYER" "$PREVIEW_LAYER" \
    || fail 'secure/editor transition renderers diverged'
rejects "$EDITOR" 'import "../awtarchy-lock"' \
    'editor crosses the secure Quickshell configuration boundary'
contains "$EDITOR" 'id: editorTransitionStart' \
    'editor has no synthetic transition start source'
contains "$EDITOR" 'LockPreviewTransitionLayer {' \
    'editor Replay does not use the config-local parity transition renderer'
contains "$EDITOR" 'startSource: editorTransitionStart' \
    'editor Replay does not begin from its synthetic desktop source'
contains "$EDITOR" 'endSource: previewScene' \
    'editor Replay does not transition into the actual preview scene'
contains "$EDITOR" 'replayToken: root.entryTransitionReplayToken' \
    'editor Replay action does not restart the shared transition renderer'
contains "$EDITOR" 'externallyManagedEntryTransition: true' \
    'editor preview still uses the rejected legacy black-cover transition'
contains "$EDITOR" 'externalEntryTransitionRunning: editorTransitionLayer.running' \
    'editor preview logo formation is not gated by the shared transition'
rejects "$EDITOR" 'entryTransitionReplayToken: root.entryTransitionReplayToken' \
    'editor Replay still drives the legacy LockScene transition directly'
rejects "$EDITOR" 'AWTARCHY_LOCK_CAPTURE_DIR' \
    'editor must not consume secure live desktop captures'
rejects "$EDITOR" 'quickshell_lockscreen_capture.sh' \
    'editor Replay must use a synthetic source instead of capturing the desktop'

# Transition speed uses an Awtarchy-style direct pointer control, not the stock
# QML Slider that previously duplicated the wrong range.
contains "$EDITOR" 'id: entryTransitionDurationTrack' \
    'editor transition duration custom track is missing'
contains "$EDITOR" 'function setEntryTransitionDurationFromPointer' \
    'editor transition duration is not directly pointer-driven'
rejects "$EDITOR" 'Slider { Layout.preferredWidth: 120; from: 400; to: 4000' \
    'legacy stock transition-speed slider remains'

# Auth remains completely isolated from presentation state.
contains "$SURFACE" 'inputMethodHints: Qt.ImhSensitiveData' \
    'secure password input lost sensitive-data handling'
contains "$SURFACE" 'auth.submit(response)' \
    'secure password submit path changed'
rejects "$AUTH" 'entryTransition' \
    'authentication owner must not consume entry transition state'
rejects "$AUTH" 'lockscreen_entry_transition' \
    'authentication owner must not consume persisted transition state'
contains "$SCENE" 'property bool externallyManagedEntryTransition' \
    'presentation scene cannot defer entry timing to the shared renderer'
contains "$SCENE" 'effectiveEntryTransitionRunning' \
    'logo entry gating is not coordinated with the shared renderer'

# Temporary implementation helpers must never survive into a candidate.
[[ ! -e "$ROOT/.github/workflows/dev-lockscreen-entry-transitions.yml" ]] \
    || fail 'temporary entry-transition development workflow is still present'
[[ ! -e "$ROOT/.github/workflows/dev-lockscreen-transition-startup.yml" ]] \
    || fail 'temporary transition-startup workflow is still present'
[[ ! -e "$ROOT/.github/scripts/apply-lockscreen-entry-transitions.py" ]] \
    || fail 'temporary entry-transition patcher is still present'
rejects "$PERMANENT_WORKFLOW" 'contents: write' \
    'permanent interactive-effects workflow regained branch write permission'

printf '%s\n' 'PASS: shared secure/editor transition replay, 1800ms default, 800-6000ms range, and auth isolation'
