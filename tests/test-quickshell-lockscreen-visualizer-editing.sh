#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
APP_STATE="${ROOT}/config/hypr/scripts/quickshell_application_state.sh"
BAR_STATE="${ROOT}/config/quickshell/awtarchy/BarState.qml"
EDITOR="${ROOT}/config/quickshell/awtarchy/LockscreenEditor.qml"
SCENE="${ROOT}/config/quickshell/awtarchy-lock/LockScene.qml"
PREVIEW_SCENE="${ROOT}/config/quickshell/awtarchy/LockPreviewScene.qml"
LOCK_SHELL="${ROOT}/config/quickshell/awtarchy-lock/shell.qml"
AUDIO_HELPER="${ROOT}/config/hypr/scripts/quickshell_lockscreen_audio.sh"
ANALYZER="${ROOT}/config/quickshell/awtarchy-lock/LockAudioAnalyzer.qml"
PREVIEW_ANALYZER="${ROOT}/config/quickshell/awtarchy/LockPreviewAudioAnalyzer.qml"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

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

run_state() {
    XDG_CACHE_HOME="$TMP/cache" XDG_CONFIG_HOME="$TMP/config" HOME="$TMP/home" \
        bash "$APP_STATE" "$@"
}

state_file="$TMP/cache/awtarchy/quickshell-state.json"
mkdir -p "$TMP/cache/awtarchy" "$TMP/config" "$TMP/home"
printf '%s\n' '{"enabled":true,"monitors":{},"launcher_sizes":{},"update_notifications_enabled":true}' >"$state_file"

layout='{"logo":{"x":0.5,"y":0.34,"scale":1,"stretch_x":1,"stretch_y":1,"opacity":100,"color":"auto"},"time":{"x":0.5,"y":0.51,"scale":1,"stretch_x":1,"stretch_y":1,"opacity":100,"color":"auto"},"date":{"x":0.5,"y":0.555,"scale":1,"stretch_x":1,"stretch_y":1,"opacity":100,"color":"auto"},"username":{"x":0.5,"y":0.595,"scale":1,"stretch_x":1,"stretch_y":1,"opacity":100,"color":"auto"},"weather":{"x":0.5,"y":0.635,"scale":1,"stretch_x":1,"stretch_y":1,"opacity":100,"color":"auto"},"password":{"x":0.5,"y":0.7,"scale":1,"stretch_x":1,"stretch_y":1,"opacity":100,"color":"auto"}}'
visibility='{"logo":true,"time":false,"date":false,"username":false,"weather":false,"password":true}'
visualizer='{"enabled":true,"x":0.5,"y":0.8,"scale":1,"stretch_x":3.25,"stretch_y":1,"opacity":100,"color":"auto","bands":16,"gap":4,"height":100,"sensitivity":180,"shape":"arc","bend":1500,"performance":"high"}'

# Extreme signed curvature, stronger sensitivity, High 120 mode, and precise
# width all remain one atomic visualizer object.
run_state save-lockscreen-editor \
    "$layout" "$visibility" black '#000000' '' \
    cover 0.5 0.5 none 0 0 auto '[]' "$visualizer" 100

jq -e '
    .lockscreen_visualizer.stretch_x == 3.25
    and .lockscreen_visualizer.bend == 1500
    and .lockscreen_visualizer.sensitivity == 180
    and .lockscreen_visualizer.performance == "high"
    and .lockscreen_visualizer.shape == "arc"
' "$state_file" >/dev/null || fail 'wide arc / sensitivity / High 120 visualizer settings did not persist atomically'

for invalid in 2001 -2001; do
    bad_visualizer="${visualizer/\"bend\":1500/\"bend\":${invalid}}"
    state_before="$(sha256sum "$state_file" | awk '{print $1}')"
    if run_state save-lockscreen-editor \
        "$layout" "$visibility" black '#000000' '' \
        cover 0.5 0.5 none 0 0 auto '[]' "$bad_visualizer" 100 >/dev/null 2>&1; then
        fail "visualizer bend outside the signed -2000..2000 safety bound was accepted: $invalid"
    fi
    [[ "$(sha256sum "$state_file" | awk '{print $1}')" == "$state_before" ]] \
        || fail 'invalid visualizer bend partially mutated persistent state'
done

bad_performance="${visualizer/\"performance\":\"high\"/\"performance\":\"ultra\"}"
if run_state save-lockscreen-editor \
    "$layout" "$visibility" black '#000000' '' \
    cover 0.5 0.5 none 0 0 auto '[]' "$bad_performance" 100 >/dev/null 2>&1; then
    fail 'unsupported visualizer performance mode was accepted'
fi

require_text "$APP_STATE" '$bend >= -2000 and $bend <= 2000' \
    'state backend does not expose the approved -2000..2000 arc bend range'
require_text "$APP_STATE" '$performance == "high"' \
    'state backend does not allow High 120 visualizer mode'
require_text "$BAR_STATE" 'bend < -2000 || bend > 2000' \
    'BarState does not enforce the approved arc bend range'
require_text "$BAR_STATE" '["balanced", "responsive", "high"]' \
    'BarState does not normalize all three visualizer performance modes'
require_text "$LOCK_SHELL" 'bend < -2000 || bend > 2000' \
    'secure shell does not enforce the approved arc bend range'
require_text "$LOCK_SHELL" '["balanced", "responsive", "high"]' \
    'secure shell does not normalize all three visualizer performance modes'
require_text "$SCENE" 'visualizerNumber("bend", 45, -2000, 2000)' \
    'shared renderer clips arc bend below the approved range'
require_text "$SCENE" 'visualizerNumber("sensitivity", 180, 25, 300)' \
    'shared renderer does not use the stronger stock sensitivity'
cmp -s "$SCENE" "$PREVIEW_SCENE" || fail 'secure/editor scene parity drifted in visualizer editing'

# The production cadence is explicit and bounded to the approved 60/90/120 FPS modes.
require_text "$AUDIO_HELPER" 'balanced) framerate=60' \
    'Balanced visualizer cadence is not 60 FPS'
require_text "$AUDIO_HELPER" 'responsive) framerate=90' \
    'Responsive visualizer cadence is not 90 FPS'
require_text "$AUDIO_HELPER" 'high) framerate=120' \
    'High visualizer cadence is not 120 FPS'
require_text "$ANALYZER" 'command: [root.helper, root.performanceMode]' \
    'secure analyzer does not pass selected cadence to CAVA helper'
require_text "$ANALYZER" 'onPerformanceModeChanged: root.restartAnalyzer()' \
    'secure analyzer does not restart when cadence changes'
cmp -s "$ANALYZER" "$PREVIEW_ANALYZER" \
    || fail 'secure/editor analyzer implementations diverged'

# Arc Bend is precision-first numeric input, not a restrictive slider.
require_text "$EDITOR" 'text: "Arc Bend"' \
    'editor has no explicit Arc Bend numeric label'
require_text "$EDITOR" 'DoubleValidator { bottom: -2000; top: 2000; decimals: 0 }' \
    'Arc Bend numeric input does not expose the approved signed range'
require_text "$EDITOR" 'onEditingFinished: root.setDraftVisualizerSetting("bend", text)' \
    'Arc Bend numeric input does not update the existing visualizer state'
require_text "$EDITOR" 'bend: Number.isInteger(bend) ? Math.max(-2000, Math.min(2000, bend))' \
    'editor draft normalizer clips extreme arc bends'
reject_text "$EDITOR" 'from: -100; to: 100; stepSize: 1' \
    'old restrictive Arc Bend slider remains'

# Visualizer width is directly resizable on the canvas and exactly editable.
require_text "$EDITOR" 'function setDraftVisualizerWidth(' \
    'editor has no precise visualizer width setter'
require_text "$EDITOR" 'function beginVisualizerWidthResize(' \
    'editor has no direct horizontal visualizer resize interaction'
require_text "$EDITOR" 'function updateVisualizerWidthResize(' \
    'visualizer width handle cannot update width'
require_text "$EDITOR" 'function endVisualizerWidthResize()' \
    'visualizer width handle does not close its history transaction'
require_text "$EDITOR" 'id: visualizerWidthLeftHandle' \
    'left visualizer width handle is missing'
require_text "$EDITOR" 'id: visualizerWidthRightHandle' \
    'right visualizer width handle is missing'
require_text "$EDITOR" 'cursorShape: Qt.SizeHorCursor' \
    'visualizer width handles do not expose horizontal resize interaction'
require_text "$EDITOR" 'text: "Width"' \
    'visualizer has no precise width label'
require_text "$EDITOR" 'DoubleValidator { bottom: 25; top: 400; decimals: 1 }' \
    'visualizer width input is not precise over the persisted width range'
require_text "$EDITOR" 'onEditingFinished: root.setDraftVisualizerWidth(text)' \
    'visualizer width input does not update persisted stretch_x'

# Response choices expose their actual CAVA cadence and reset to the stronger stock profile.
require_text "$EDITOR" 'sensitivity: 180' \
    'editor stock visualizer sensitivity is not strengthened to 180'
require_text "$EDITOR" 'label: "Balanced 60"' \
    'editor does not identify Balanced cadence as 60 FPS'
require_text "$EDITOR" 'label: "Responsive 90"' \
    'editor does not identify Responsive cadence as 90 FPS'
require_text "$EDITOR" 'label: "High 120"' \
    'editor does not expose High 120 cadence'
require_text "$EDITOR" 'draftVisualizer = defaultVisualizer();' \
    'visualizer Reset to Default does not restore stock width/bend/sensitivity/performance'

printf '%s\n' 'PASS: lockscreen visualizer width, -2000..2000 bend, stronger sensitivity, and 60/90/120 response contracts'
