#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
APP_STATE="${ROOT}/config/hypr/scripts/quickshell_application_state.sh"
BAR_STATE="${ROOT}/config/quickshell/awtarchy/BarState.qml"
EDITOR="${ROOT}/config/quickshell/awtarchy/LockscreenEditor.qml"
SCENE="${ROOT}/config/quickshell/awtarchy-lock/LockScene.qml"
PREVIEW_SCENE="${ROOT}/config/quickshell/awtarchy/LockPreviewScene.qml"
LOCK_SHELL="${ROOT}/config/quickshell/awtarchy-lock/shell.qml"
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
visualizer='{"enabled":true,"x":0.5,"y":0.8,"scale":1,"stretch_x":3.25,"stretch_y":1,"opacity":100,"color":"auto","bands":16,"gap":4,"height":100,"sensitivity":140,"shape":"arc","bend":300,"performance":"balanced"}'

# Wide signed arc curvature and precise visualizer width share the existing
# atomic visualizer object rather than creating another persistence owner.
run_state save-lockscreen-editor \
    "$layout" "$visibility" black '#000000' '' \
    cover 0.5 0.5 none 0 0 auto '[]' "$visualizer" 100

jq -e '
    .lockscreen_visualizer.stretch_x == 3.25
    and .lockscreen_visualizer.bend == 300
    and .lockscreen_visualizer.shape == "arc"
' "$state_file" >/dev/null || fail 'wide arc bend / precise visualizer width did not persist atomically'

bad_visualizer="${visualizer/\"bend\":300/\"bend\":361}"
state_before="$(sha256sum "$state_file" | awk '{print $1}')"
if run_state save-lockscreen-editor \
    "$layout" "$visibility" black '#000000' '' \
    cover 0.5 0.5 none 0 0 auto '[]' "$bad_visualizer" 100 >/dev/null 2>&1; then
    fail 'visualizer bend outside the signed -360..360 safety bound was accepted'
fi
[[ "$(sha256sum "$state_file" | awk '{print $1}')" == "$state_before" ]] \
    || fail 'invalid visualizer bend partially mutated persistent state'

require_text "$APP_STATE" '$bend >= -360 and $bend <= 360' \
    'state backend still uses the narrow arc bend range'
require_text "$BAR_STATE" 'bend < -360 || bend > 360' \
    'BarState still uses the narrow arc bend range'
require_text "$LOCK_SHELL" 'bend < -360 || bend > 360' \
    'secure shell still uses the narrow arc bend range'
require_text "$SCENE" 'visualizerNumber("bend", 45, -360, 360)' \
    'shared renderer still clips arc bend to the old range'
cmp -s "$SCENE" "$PREVIEW_SCENE" || fail 'secure/editor scene parity drifted in visualizer editing'

# Arc Bend is precision-first numeric input, not a restrictive slider.
require_text "$EDITOR" 'text: "Arc Bend"' \
    'editor has no explicit Arc Bend numeric label'
require_text "$EDITOR" 'DoubleValidator { bottom: -360; top: 360; decimals: 0 }' \
    'Arc Bend numeric input is not wide signed input'
require_text "$EDITOR" 'onEditingFinished: root.setDraftVisualizerSetting("bend", text)' \
    'Arc Bend numeric input does not update the existing visualizer state'
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
require_text "$EDITOR" 'draftVisualizer = defaultVisualizer();' \
    'visualizer Reset to Default does not restore stock width/bend'

printf '%s\n' 'PASS: lockscreen visualizer direct width and wide signed arc bend contracts'
