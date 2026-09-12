#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
EDITOR="$ROOT/config/quickshell/awtarchy/LockscreenEditor.qml"
QUICK_SETTINGS="$ROOT/config/quickshell/awtarchy/QuickSettings.qml"
LAYER="$ROOT/config/quickshell/awtarchy-lock/LockTransitionLayer.qml"
PREVIEW_LAYER="$ROOT/config/quickshell/awtarchy/LockPreviewTransitionLayer.qml"
PREVIEW_CAPTURE="$ROOT/config/hypr/scripts/quickshell_lockscreen_preview_capture.sh"
SECURE_CAPTURE="$ROOT/config/hypr/scripts/quickshell_lockscreen_capture.sh"

failures=0
check_text() {
    local file="$1" text="$2" message="$3"
    if [[ ! -f "$file" ]] || ! grep -Fq -- "$text" "$file"; then
        printf 'FAIL: %s\n' "$message" >&2
        failures=$((failures + 1))
    fi
}
reject_text() {
    local file="$1" text="$2" message="$3"
    if [[ -f "$file" ]] && grep -Fq -- "$text" "$file"; then
        printf 'FAIL: %s\n' "$message" >&2
        failures=$((failures + 1))
    fi
}

cmp -s "$LAYER" "$PREVIEW_LAYER" || {
    printf 'FAIL: secure/editor transition renderers diverged\n' >&2
    failures=$((failures + 1))
}

# Iris Reveal's mask must be texture-only staging. It must never remain as a
# visible scene item beneath Pixel/Fade/Edges/Wipe during partial alpha blends.
check_text "$LAYER" 'id: irisMaskShape' 'Iris Reveal mask shape is missing'
check_text "$LAYER" 'maskSource: irisMaskTexture' 'Iris Reveal effect is not driven by the mask texture'
python3 - "$LAYER" <<'PY' || failures=$((failures + 1))
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text()
try:
    shape_start = text.index("id: irisMaskShape")
    texture_start = text.index("id: irisMaskTexture", shape_start)
except ValueError as exc:
    raise SystemExit(f"FAIL: Iris Reveal mask staging block is incomplete: {exc}")
shape = text[shape_start:texture_start]
for needle, message in (
    ("x: root.width + 64", "Iris Reveal mask shape is not staged off-screen"),
    ("y: 0", "Iris Reveal mask shape lacks an explicit staging origin"),
    ("width: root.width", "Iris Reveal mask shape does not preserve transition width"),
    ("height: root.height", "Iris Reveal mask shape does not preserve transition height"),
    ('visible: root.running && root.normalizedMode === "iris"', "Iris Reveal mask shape is not mode-gated"),
):
    if needle not in shape:
        raise SystemExit(f"FAIL: {message}")
if "anchors.fill: parent" in shape:
    raise SystemExit("FAIL: Iris Reveal mask shape is still a visible in-scene full-frame item")
PY

# Editor preview must use a real per-output desktop snapshot captured after
# Quick Settings closes and while every editor preview window is hidden.
[[ -f "$PREVIEW_CAPTURE" ]] || {
    printf 'FAIL: editor desktop preview capture helper is missing\n' >&2
    failures=$((failures + 1))
}
if [[ -f "$PREVIEW_CAPTURE" ]]; then
    bash -n "$PREVIEW_CAPTURE" || {
        printf 'FAIL: editor desktop preview capture helper has invalid Bash syntax\n' >&2
        failures=$((failures + 1))
    }
    check_text "$PREVIEW_CAPTURE" 'awtarchy-lock-preview' 'editor capture does not use an isolated runtime root'
    reject_text "$PREVIEW_CAPTURE" 'awtarchy-lock-transition' 'editor capture can collide with secure lock capture storage'
fi
check_text "$QUICK_SETTINGS" 'root.close();' 'Quick Settings does not close before launching the lockscreen editor'
check_text "$EDITOR" 'quickshell_lockscreen_preview_capture.sh' 'editor does not call the desktop preview capture helper'
check_text "$EDITOR" 'property string previewCaptureDirectory: ""' 'editor does not retain its preview capture directory'
check_text "$EDITOR" 'function previewCaptureSourceForScreen(screen)' 'editor cannot resolve the captured frame for each output'
check_text "$EDITOR" 'id: previewCaptureDelay' 'editor does not wait for its windows to disappear before desktop capture'
check_text "$EDITOR" 'id: previewCaptureProcess' 'editor has no desktop preview capture process'
check_text "$EDITOR" 'source: root.previewCaptureSourceForScreen(editorWindow.screen)' 'primary preview does not render the captured current desktop'
check_text "$EDITOR" 'source: root.previewCaptureSourceForScreen(modelData)' 'secondary preview does not render each output capture'
reject_text "$EDITOR" 'Synthetic desktop preview' 'synthetic desktop placeholder still exists in the editor preview'

python3 - "$EDITOR" <<'PY' || failures=$((failures + 1))
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text()
try:
    start = text.index("function openForScreen(target)")
    end = text.index("function openFocused()", start)
    block = text[start:end]
    hidden = block.index("editorWindow.visible = false")
    delayed = block.index("previewCaptureDelay.restart()")
except ValueError as exc:
    raise SystemExit(f"FAIL: editor open path does not hide before deferred capture: {exc}")
if hidden > delayed:
    raise SystemExit("FAIL: editor starts desktop capture before hiding its own window")
if "editorWindow.visible = true" in block:
    raise SystemExit("FAIL: editor becomes visible in openForScreen before preview capture finishes")
PY

# Alt+Mouse1 bar dragging should use a modifier-filtered Pointer Handler so it
# can reliably coexist with the bar's child buttons and text fields.
check_text "$EDITOR" 'id: settingsBarAltDrag' 'settings bar Alt-drag handler is missing'
check_text "$EDITOR" 'DragHandler {' 'settings bar Alt-drag does not use DragHandler'
check_text "$EDITOR" 'acceptedModifiers: Qt.AltModifier' 'settings bar drag is not explicitly Alt-filtered'
check_text "$EDITOR" 'yAxis.onActiveValueChanged:' 'settings bar drag does not apply live vertical deltas'
reject_text "$EDITOR" 'property real dragStartSceneY: 0' 'legacy MouseArea settings-bar drag state still exists'
reject_text "$EDITOR" 'property real dragStartOffsetY: 0' 'legacy MouseArea settings-bar drag offset still exists'

# Secure capture remains separate and untouched by the editor-preview capture.
check_text "$SECURE_CAPTURE" 'awtarchy-lock-transition' 'secure lock capture root changed unexpectedly'

if (( failures > 0 )); then
    printf 'FAIL: %d editor preview/runtime regression contract(s) unmet\n' "$failures" >&2
    exit 1
fi

printf '%s\n' 'PASS: real desktop editor preview, isolated Iris mask, and Alt-drag settings bar contracts'
