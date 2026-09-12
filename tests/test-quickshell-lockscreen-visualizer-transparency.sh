#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
APP_STATE="${ROOT}/config/hypr/scripts/quickshell_application_state.sh"
BAR_STATE="${ROOT}/config/quickshell/awtarchy/BarState.qml"
EDITOR="${ROOT}/config/quickshell/awtarchy/LockscreenEditor.qml"
QUICK_SETTINGS="${ROOT}/config/quickshell/awtarchy/QuickSettings.qml"
SCENE="${ROOT}/config/quickshell/awtarchy-lock/LockScene.qml"
PREVIEW_SCENE="${ROOT}/config/quickshell/awtarchy/LockPreviewScene.qml"
SURFACE="${ROOT}/config/quickshell/awtarchy-lock/LockSurface.qml"
LOCK_SHELL="${ROOT}/config/quickshell/awtarchy-lock/shell.qml"
LOCK_AUTH="${ROOT}/config/quickshell/awtarchy-lock/LockAuth.qml"
ANALYZER="${ROOT}/config/quickshell/awtarchy-lock/LockAudioAnalyzer.qml"
PREVIEW_ANALYZER="${ROOT}/config/quickshell/awtarchy/LockPreviewAudioAnalyzer.qml"
CAVA_CONFIG="${ROOT}/config/quickshell/awtarchy-lock/cava.conf"
AUDIO_HELPER="${ROOT}/config/hypr/scripts/quickshell_lockscreen_audio.sh"
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

require_count() {
    local file="$1" text="$2" expected="$3" message="$4" count
    count="$(grep -Fc -- "$text" "$file" || true)"
    [[ "$count" == "$expected" ]] || fail "$message (expected $expected, got $count)"
}

run_state() {
    XDG_CACHE_HOME="$TMP/cache" XDG_CONFIG_HOME="$TMP/config" HOME="$TMP/home" \
        bash "$APP_STATE" "$@"
}

state_file="$TMP/cache/awtarchy/quickshell-state.json"
mkdir -p "$TMP/cache/awtarchy" "$TMP/config" "$TMP/home"
printf '%s\n' '{"enabled":true,"monitors":{},"launcher_sizes":{},"update_notifications_enabled":true}' >"$state_file"

# RED/GREEN contract: Pass 3 extends the single existing state owner.
require_text "$APP_STATE" 'lockscreen_visualizer' \
    'visualizer persistence is missing'
require_text "$APP_STATE" 'lockscreen_background_opacity' \
    'background-opacity persistence is missing'
require_text "$APP_STATE" 'normalize_lockscreen_visualizer_json()' \
    'visualizer persistence has no validator/normalizer'
require_text "$APP_STATE" 'set-lockscreen-visualizer-enabled' \
    'visualizer has no independent enable command'
require_text "$APP_STATE" 'set-lockscreen-background-opacity' \
    'background opacity has no independent setter'

# Independent setters must bootstrap safe defaults rather than depending on
# obsolete audio-reactive-logo state.
run_state set-lockscreen-visualizer-enabled true
run_state set-lockscreen-background-opacity 75
jq -e '
    .lockscreen_visualizer.enabled == true
    and .lockscreen_visualizer.x == 0.5
    and .lockscreen_visualizer.y == 0.8
    and .lockscreen_visualizer.scale == 1
    and .lockscreen_visualizer.stretch_x == 1
    and .lockscreen_visualizer.stretch_y == 1
    and .lockscreen_visualizer.opacity == 100
    and .lockscreen_visualizer.color == "auto"
    and .lockscreen_visualizer.bands == 16
    and .lockscreen_visualizer.gap == 4
    and .lockscreen_visualizer.height == 100
    and .lockscreen_visualizer.sensitivity == 180
    and .lockscreen_visualizer.shape == "straight"
    and .lockscreen_visualizer.bend == 45
    and .lockscreen_visualizer.performance == "balanced"
    and .lockscreen_background_opacity == 75
' "$state_file" >/dev/null || fail 'Pass 3 independent setters did not normalize safe defaults'

layout='{"logo":{"x":0.5,"y":0.34,"scale":1,"stretch_x":1,"stretch_y":1,"opacity":100,"color":"auto"},"time":{"x":0.5,"y":0.51,"scale":1,"stretch_x":1,"stretch_y":1,"opacity":100,"color":"auto"},"date":{"x":0.5,"y":0.555,"scale":1,"stretch_x":1,"stretch_y":1,"opacity":100,"color":"auto"},"username":{"x":0.5,"y":0.595,"scale":1,"stretch_x":1,"stretch_y":1,"opacity":100,"color":"auto"},"weather":{"x":0.5,"y":0.635,"scale":1,"stretch_x":1,"stretch_y":1,"opacity":100,"color":"auto"},"password":{"x":0.5,"y":0.7,"scale":1,"stretch_x":1,"stretch_y":1,"opacity":100,"color":"auto"}}'
visibility='{"logo":true,"time":false,"date":false,"username":false,"weather":false,"password":true}'
visualizer='{"enabled":true,"x":0.44,"y":0.79,"scale":1.25,"stretch_x":1.5,"stretch_y":0.75,"opacity":68,"color":"#33aaff","bands":24,"gap":6,"height":145,"sensitivity":130,"shape":"arc","bend":-55,"performance":"responsive"}'

run_state save-lockscreen-editor \
    "$layout" "$visibility" black '#000000' '' \
    cover 0.5 0.5 none 0 0 auto '[]' "$visualizer" 60

jq -e '
    .lockscreen_visualizer.enabled == true
    and .lockscreen_visualizer.x == 0.44
    and .lockscreen_visualizer.y == 0.79
    and .lockscreen_visualizer.scale == 1.25
    and .lockscreen_visualizer.stretch_x == 1.5
    and .lockscreen_visualizer.stretch_y == 0.75
    and .lockscreen_visualizer.opacity == 68
    and .lockscreen_visualizer.color == "#33aaff"
    and .lockscreen_visualizer.bands == 24
    and .lockscreen_visualizer.gap == 6
    and .lockscreen_visualizer.height == 145
    and .lockscreen_visualizer.sensitivity == 130
    and .lockscreen_visualizer.shape == "arc"
    and .lockscreen_visualizer.bend == -55
    and .lockscreen_visualizer.performance == "responsive"
    and .lockscreen_background_opacity == 60
' "$state_file" >/dev/null || fail 'atomic Pass 3 editor save did not persist visualizer/background opacity'

state_before="$(sha256sum "$state_file" | awk '{print $1}')"

bad_bands="${visualizer/\"bands\":24/\"bands\":3}"
if run_state save-lockscreen-editor \
    "$layout" "$visibility" black '#000000' '' \
    cover 0.5 0.5 none 0 0 auto '[]' "$bad_bands" 60 >/dev/null 2>&1; then
    fail 'visualizer band count below 4 was accepted'
fi

bad_shape="${visualizer/\"shape\":\"arc\"/\"shape\":\"spiral\"}"
if run_state save-lockscreen-editor \
    "$layout" "$visibility" black '#000000' '' \
    cover 0.5 0.5 none 0 0 auto '[]' "$bad_shape" 60 >/dev/null 2>&1; then
    fail 'unsupported visualizer shape was accepted'
fi

bad_bend="${visualizer/\"bend\":-55/\"bend\":2001}"
if run_state save-lockscreen-editor \
    "$layout" "$visibility" black '#000000' '' \
    cover 0.5 0.5 none 0 0 auto '[]' "$bad_bend" 60 >/dev/null 2>&1; then
    fail 'visualizer bend outside -2000..2000 was accepted'
fi

if run_state set-lockscreen-background-opacity 101 >/dev/null 2>&1; then
    fail 'background opacity above 100 was accepted'
fi

[[ "$(sha256sum "$state_file" | awk '{print $1}')" == "$state_before" ]] \
    || fail 'invalid Pass 3 state update partially mutated persistent state'

run_state reset-lockscreen-presentation
jq -e '
    .lockscreen_visualizer.enabled == false
    and .lockscreen_visualizer.bands == 16
    and .lockscreen_visualizer.shape == "straight"
    and .lockscreen_background_opacity == 100
' "$state_file" >/dev/null || fail 'Restore Defaults does not restore Pass 3 stock state'

# Unlocked state owner must expose normalized Pass 3 state independently from
# the obsolete audio-reactive logo preference.
require_text "$BAR_STATE" 'defaultLockscreenVisualizer' \
    'BarState has no stock visualizer definition'
require_text "$BAR_STATE" 'function lockscreenVisualizer()' \
    'BarState has no normalized visualizer reader'
require_text "$BAR_STATE" 'function lockscreenBackgroundOpacity()' \
    'BarState has no normalized background-opacity reader'

# Audio analyzer is one bounded spectrum source, not logo motion.
require_text "$CAVA_CONFIG" 'framerate = 60' \
    'balanced CAVA visualizer source is not 60 FPS'
require_text "$CAVA_CONFIG" 'bars = 64' \
    'CAVA visualizer source is not fixed at 64 bands'
require_text "$CAVA_CONFIG" 'method = pipewire' \
    'CAVA visualizer source is not PipeWire'
require_text "$CAVA_CONFIG" 'source = auto' \
    'CAVA visualizer source does not use the automatic output source'
require_text "$AUDIO_HELPER" 'responsive) framerate=90' \
    'audio helper has no explicit responsive mode'
require_text "$AUDIO_HELPER" 'high) framerate=120' \
    'audio helper has no explicit High 120 mode'
require_text "$ANALYZER" 'property var bands:' \
    'secure analyzer exposes no normalized band array'
require_text "$ANALYZER" 'onEnabledChanged:' \
    'secure analyzer lifecycle is not tied to enabled state'
[[ -f "$PREVIEW_ANALYZER" ]] || fail 'desktop preview has no config-local analyzer'
require_text "$PREVIEW_ANALYZER" 'property var bands:' \
    'preview analyzer exposes no normalized band array'

# Secure root owns exactly one analyzer and every surface receives only
# presentation data.
require_count "$LOCK_SHELL" 'LockAudioAnalyzer {' 1 \
    'secure shell does not own exactly one audio analyzer'
require_text "$LOCK_SHELL" 'enabled: root.lockVisualizer.enabled' \
    'secure analyzer lifecycle does not follow visualizer enabled state'
require_text "$LOCK_SHELL" 'audioBands: lockAudioAnalyzer.bands' \
    'secure surfaces do not receive the shared analyzer spectrum'
require_text "$LOCK_SHELL" 'visualizer: root.lockVisualizer' \
    'secure surfaces do not receive normalized visualizer state'
require_text "$LOCK_SHELL" 'backgroundOpacity: root.lockBackgroundOpacity' \
    'secure surfaces do not receive normalized background opacity'

# LockSurface remains the secure authority-facing surface. Transparency is
# backing/presentation only; auth and password ownership remain unchanged.
require_text "$SURFACE" 'WlSessionLockSurface {' \
    'secure surface is no longer a WlSessionLockSurface'
require_text "$SURFACE" 'color: "transparent"' \
    'secure surface backing still forces opaque black'
require_text "$SURFACE" 'required property var visualizer' \
    'secure surface has no visualizer presentation input'
require_text "$SURFACE" 'required property var audioBands' \
    'secure surface has no analyzer spectrum input'
require_text "$SURFACE" 'required property int backgroundOpacity' \
    'secure surface has no background-opacity input'
require_text "$SURFACE" 'TextInput {' \
    'secure password TextInput is missing'
require_text "$SURFACE" 'const response = password.text;' \
    'secure password submission no longer copies the in-memory TextInput response'
require_text "$SURFACE" 'if (auth.submit(response))' \
    'secure password submission path changed'
reject_text "$LOCK_AUTH" 'visualizer' \
    'visualizer state leaked into PAM/authentication owner'
reject_text "$LOCK_AUTH" 'audioBands' \
    'audio spectrum leaked into PAM/authentication owner'
reject_text "$LOCK_AUTH" 'backgroundOpacity' \
    'background transparency leaked into PAM/authentication owner'

# Scene receives presentation-only state, keeps alpha confined to the
# background layer, and exposes all three bounded shapes.
require_text "$SCENE" 'required property var visualizer' \
    'scene has no visualizer state input'
require_text "$SCENE" 'required property var audioBands' \
    'scene has no analyzer spectrum input'
require_text "$SCENE" 'required property int backgroundOpacity' \
    'scene has no background-opacity input'
require_text "$SCENE" 'id: backgroundLayer' \
    'scene has no isolated background composition layer'
require_text "$SCENE" 'root.backgroundOpacity' \
    'background layer does not consume configured opacity'
require_text "$SCENE" 'function visualizerBands()' \
    'scene does not resample analyzer data into visible bands'
require_text "$SCENE" '"straight"' \
    'straight visualizer mode is missing'
require_text "$SCENE" '"arc"' \
    'arc visualizer mode is missing'
require_text "$SCENE" '"circle"' \
    'circle visualizer mode is missing'
require_text "$SCENE" 'Math.min(64' \
    'visualizer delegate count is not structurally bounded to 64'
cmp -s "$SCENE" "$PREVIEW_SCENE" || fail 'secure/editor scene parity drifted in Pass 3'

# Editor must route visualizer through the generic transform/history model.
require_text "$EDITOR" 'property var draftVisualizer:' \
    'editor has no visualizer draft state'
require_text "$EDITOR" 'property int draftBackgroundOpacity:' \
    'editor has no background-opacity draft state'
require_text "$EDITOR" 'LockPreviewAudioAnalyzer {' \
    'editor does not own a config-local preview analyzer'
require_text "$EDITOR" 'root.editingActive && !root.pickerSuspended' \
    'preview analyzer lifecycle is not bounded to active editor state'
require_text "$EDITOR" '"visualizer"' \
    'visualizer is not part of generic editor element routing'
require_text "$EDITOR" 'visualizer: cloneSnapshot(draftVisualizer)' \
    'undo/redo snapshot does not include visualizer state'
require_text "$EDITOR" 'backgroundOpacity: draftBackgroundOpacity' \
    'undo/redo snapshot does not include background opacity'
require_text "$EDITOR" 'text: "Bands"' \
    'editor has no visualizer band-count control'
require_text "$EDITOR" 'text: "Gap"' \
    'editor has no visualizer gap control'
require_text "$EDITOR" 'text: "Height"' \
    'editor has no visualizer height control'
require_text "$EDITOR" 'text: "Sensitivity"' \
    'editor has no visualizer sensitivity control'
require_text "$EDITOR" 'label: "Straight"' \
    'editor has no straight visualizer shape selector'
require_text "$EDITOR" 'label: "Arc"' \
    'editor has no arc visualizer shape selector'
require_text "$EDITOR" 'label: "Circle"' \
    'editor has no circle visualizer shape selector'
require_text "$EDITOR" 'text: "Background Opacity"' \
    'editor has no background opacity control'
require_text "$EDITOR" 'Transparency can reveal content' \
    'editor has no transparency privacy warning'

# Quick Settings intentionally exposes only high-value global controls.
require_text "$QUICK_SETTINGS" 'text: "Visualizer"' \
    'Quick Settings has no visualizer toggle'
reject_text "$QUICK_SETTINGS" 'text: "Background Opacity"' \
    'detailed background opacity remains duplicated in Quick Settings'
reject_text "$QUICK_SETTINGS" 'Audio Reactive' \
    'obsolete audio-reactive logo control returned to Quick Settings'

printf 'PASS: lockscreen Pass 3 visualizer and background transparency contracts\n'
