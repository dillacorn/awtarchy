#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
EDITOR="${ROOT}/config/quickshell/awtarchy/LockscreenEditor.qml"
BAR="${ROOT}/config/quickshell/awtarchy/BarState.qml"
STATE="${ROOT}/config/hypr/scripts/quickshell_application_state.sh"
SECURE="${ROOT}/config/quickshell/awtarchy-lock/LockScene.qml"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
require_text() {
    local file="$1" text="$2" message="$3"
    grep -Fq -- "$text" "$file" || fail "$message"
}
reject_text() {
    local file="$1" text="$2" message="$3"
    if grep -Fq -- "$text" "$file"; then
        fail "$message"
    fi
}
require_count() {
    local file="$1" text="$2" expected="$3" message="$4" count
    count="$(grep -Fc -- "$text" "$file" || true)"
    [[ "$count" -eq "$expected" ]] || fail "$message (expected $expected, got $count)"
}

# Guides are transient editor state, never persistent or part of the secure scene.
require_text "$EDITOR" 'property bool showEditorGrid:' 'editor has no transient guide toggle'
require_text "$EDITOR" 'id: editorGridOverlay' 'editor guide overlay is missing'
require_text "$EDITOR" 'visible: root.showEditorGrid' 'editor guide overlay is not toggleable'
require_text "$EDITOR" 'id: safeAreaGuide' 'safe-area guide is missing'
require_text "$EDITOR" 'x: parent.width * 0.05' 'safe-area horizontal margin is not tied to element bounds'
require_text "$EDITOR" 'y: parent.height * 0.08' 'safe-area vertical margin is not tied to element bounds'
require_text "$EDITOR" 'x: parent.width / 3' 'first vertical third guide is missing'
require_text "$EDITOR" 'x: parent.width * 2 / 3' 'second vertical third guide is missing'
require_text "$EDITOR" 'y: parent.height / 3' 'first horizontal third guide is missing'
require_text "$EDITOR" 'y: parent.height * 2 / 3' 'second horizontal third guide is missing'
require_text "$EDITOR" 'x: parent.width / 2' 'vertical center guide is missing'
require_text "$EDITOR" 'y: parent.height / 2' 'horizontal center guide is missing'
require_text "$EDITOR" 'label: "Guides"' 'editor has no Guides control'
reject_text "$BAR" 'showEditorGrid' 'transient editor guides leaked into BarState'
reject_text "$STATE" 'showEditorGrid' 'transient editor guides leaked into persistent state backend'
reject_text "$SECURE" 'showEditorGrid' 'transient editor guides leaked into secure presentation scene'

# Four deterministic stock layouts exist and are applied only to editor draft state.
require_text "$EDITOR" 'function layoutPreset(name)' 'editor has no stock preset geometry source'
require_text "$EDITOR" 'function presetVisibility(name)' 'editor has no stock preset visibility source'
require_text "$EDITOR" 'function applyLayoutPreset(name)' 'editor has no preset application API'
for key in minimal centered information lower-third; do
    require_text "$EDITOR" "name === \"$key\"" "preset geometry missing: $key"
done
for label in Minimal Centered Information 'Lower Third'; do
    require_text "$EDITOR" "label: \"$label\"" "preset control missing: $label"
done

# Preset application must create exactly one undo point, clone current draft layout
# so colors survive, and directly replace geometry/visibility without invoking
# setters that would create additional undo records.
require_count "$EDITOR" 'function applyLayoutPreset(name)' 1 'preset application function is duplicated'
require_text "$EDITOR" 'const previous = editorSnapshot();' 'preset application does not capture one pre-change snapshot'
require_text "$EDITOR" 'const next = cloneLayout(draftLayout);' 'preset application does not preserve existing element colors'
require_text "$EDITOR" 'next[element].color = current.color;' 'preset application does not explicitly preserve colors'
require_text "$EDITOR" 'pushUndoSnapshot(previous);' 'preset application does not create one undo snapshot'
require_text "$EDITOR" 'draftVisibility = cloneVisibility(visibility);' 'preset application does not replace draft visibility atomically'
require_text "$EDITOR" 'visibility.password = true;' 'preset visibility does not force Password visible'

# Presets do not touch non-layout draft state. Keep these assignments out of the
# applyLayoutPreset function body specifically.
preset_body="$(awk '
    /function applyLayoutPreset\(name\)/ {inside=1}
    inside {print}
    inside && /^    }$/ {exit}
' "$EDITOR")"
[[ -n "$preset_body" ]] || fail 'could not isolate preset application body'
for forbidden in draftBackgroundMode draftBackgroundColor draftWallpaperPath draftWallpaperFit draftWallpaperFocalX draftWallpaperFocalY draftOverlayMode draftOverlayStrength draftWallpaperBlur draftWeatherUnits; do
    if grep -Fq -- "$forbidden" <<<"$preset_body"; then
        fail "preset application mutates unrelated draft state: $forbidden"
    fi
done
if grep -Fq 'setDraftVisible(' <<<"$preset_body" || grep -Fq 'setDraftPoint(' <<<"$preset_body"; then
    fail 'preset application uses per-element setters and can create multiple undo snapshots'
fi

# Visibility semantics from the approved plan.
require_text "$EDITOR" 'minimal: ({ logo: true, time: false, date: false, username: false, weather: false, password: true })' \
    'Minimal preset must show only Logo + Password'
require_text "$EDITOR" 'centered: ({ logo: true, time: true, date: true, username: false, weather: false, password: true })' \
    'Centered preset must show Logo + Time + Date + Password'
require_text "$EDITOR" 'information: ({ logo: true, time: true, date: true, username: true, weather: true, password: true })' \
    'Information preset must show every element'
require_text "$EDITOR" 'lowerThird: ({ logo: true, time: true, date: true, username: true, weather: true, password: true })' \
    'Lower Third preset must show every information element + Password'

printf '%s\n' 'PASS: lockscreen editor transient guides and stock layout preset contracts'
