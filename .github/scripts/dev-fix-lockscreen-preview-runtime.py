#!/usr/bin/env python3
from pathlib import Path


def replace_once(path: str, old: str, new: str, label: str) -> None:
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    p.write_text(text.replace(old, new, 1))


preview_capture = r'''#!/usr/bin/env bash
# Capture the current unlocked Hyprland outputs for lockscreen editor preview.

set -euo pipefail
umask 077

RUNTIME_DIR="${XDG_RUNTIME_DIR:-}"
CAPTURE_ROOT="${RUNTIME_DIR}/awtarchy-lock-preview"

fail() {
    printf 'quickshell_lockscreen_preview_capture.sh: %s\n' "$*" >&2
    return 1
}

validate_runtime_dir() {
    [[ -n "$RUNTIME_DIR" ]] || fail 'XDG_RUNTIME_DIR is not set.'
    [[ -d "$RUNTIME_DIR" && ! -L "$RUNTIME_DIR" && -O "$RUNTIME_DIR" ]] \
        || fail 'XDG_RUNTIME_DIR is not an owned regular directory.'
}

ensure_capture_root() {
    validate_runtime_dir || return 1

    if [[ -e "$CAPTURE_ROOT" || -L "$CAPTURE_ROOT" ]]; then
        [[ -d "$CAPTURE_ROOT" && ! -L "$CAPTURE_ROOT" && -O "$CAPTURE_ROOT" ]] \
            || fail 'capture root is not an owned regular directory.'
    else
        mkdir -m 700 -- "$CAPTURE_ROOT"
    fi

    chmod 700 -- "$CAPTURE_ROOT"
}

safe_output_name() {
    [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]]
}

remove_owned_capture_dir() {
    local target="$1"
    local parent base

    ensure_capture_root || return 1
    parent="$(dirname -- "$target")"
    base="$(basename -- "$target")"

    [[ "$parent" == "$CAPTURE_ROOT" ]] || fail 'refusing cleanup outside the preview capture root.'
    [[ "$base" =~ ^capture\.[A-Za-z0-9]+$ ]] || fail 'refusing cleanup of a non-capture directory.'
    [[ -d "$target" && ! -L "$target" && -O "$target" ]] \
        || fail 'capture directory is not an owned regular directory.'

    rm -rf -- "$target"
}

remove_stale_captures() {
    local stale

    shopt -s nullglob
    for stale in "$CAPTURE_ROOT"/capture.*; do
        [[ -d "$stale" && ! -L "$stale" && -O "$stale" ]] || continue
        rm -rf -- "$stale"
    done
    shopt -u nullglob
}

prepare_capture() {
    local capture_dir output output_file
    local -a outputs=()

    ensure_capture_root || return 1
    remove_stale_captures

    mapfile -t outputs < <(hyprctl monitors -j | jq -er '.[].name')
    ((${#outputs[@]} > 0)) || fail 'Hyprland reported no active outputs.'

    for output in "${outputs[@]}"; do
        safe_output_name "$output" || fail "unsafe output name: $output"
    done

    capture_dir="$(mktemp -d "${CAPTURE_ROOT}/capture.XXXXXX")"
    chmod 700 -- "$capture_dir"

    for output in "${outputs[@]}"; do
        output_file="${capture_dir}/${output}.png"
        if ! grim -l 1 -o "$output" "$output_file"; then
            rm -rf -- "$capture_dir"
            fail "failed to capture output: $output"
            return 1
        fi
        chmod 600 -- "$output_file"
        if [[ ! -f "$output_file" || -L "$output_file" || ! -O "$output_file" \
            || ! -r "$output_file" || ! -s "$output_file" ]]; then
            rm -rf -- "$capture_dir"
            fail "invalid capture file for output: $output"
            return 1
        fi
    done

    printf '%s\n' "$capture_dir"
}

usage() {
    cat <<'EOF'
Usage: quickshell_lockscreen_preview_capture.sh <command> [argument]

Commands:
  prepare               Capture every active Hyprland output for editor preview.
  cleanup <capture-dir> Remove one validated preview capture directory.
EOF
}

case "${1:-}" in
    prepare)
        [[ $# -eq 1 ]] || { usage >&2; exit 2; }
        prepare_capture
        ;;
    cleanup)
        [[ $# -eq 2 ]] || { usage >&2; exit 2; }
        remove_owned_capture_dir "$2"
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
'''
Path("config/hypr/scripts/quickshell_lockscreen_preview_capture.sh").write_text(preview_capture)

# Isolate Iris mask staging from every visible transition layer.  The source is
# off-scene instead of relying on hideSource to suppress a full-frame Item.
transition_old = '''    Item {
        id: irisMaskShape
        anchors.fill: parent
        layer.enabled: true
        layer.smooth: true
        Rectangle {
            anchors.centerIn: parent
            width: root.irisDiameter
            height: width
            radius: width / 2
            color: "#ffffff"
        }
    }

    ShaderEffectSource {
        id: irisMaskTexture
        x: root.width + 64
        y: 0
        width: root.width
        height: root.height
        sourceItem: irisMaskShape
        hideSource: true
        live: true
        recursive: false
        smooth: true
    }
'''
transition_new = '''    Item {
        id: irisMaskShape
        x: root.width + 64
        y: 0
        width: root.width
        height: root.height
        visible: root.running && root.normalizedMode === "iris"
        Rectangle {
            anchors.centerIn: parent
            width: root.irisDiameter
            height: width
            radius: width / 2
            color: "#ffffff"
        }
    }

    ShaderEffectSource {
        id: irisMaskTexture
        x: root.width * 2 + 128
        y: 0
        width: root.width
        height: root.height
        sourceItem: irisMaskShape
        hideSource: false
        live: true
        recursive: false
        smooth: true
    }
'''
for path in (
    "config/quickshell/awtarchy-lock/LockTransitionLayer.qml",
    "config/quickshell/awtarchy/LockPreviewTransitionLayer.qml",
):
    replace_once(path, transition_old, transition_new, f"Iris staging in {path}")

editor = "config/quickshell/awtarchy/LockscreenEditor.qml"
replace_once(
    editor,
    '''    readonly property string wallpaperPickerBackend: configHome + "/hypr/scripts/quickshell_lockscreen_wallpaper_picker.sh"
    property bool editingActive: false
''',
    '''    readonly property string wallpaperPickerBackend: configHome + "/hypr/scripts/quickshell_lockscreen_wallpaper_picker.sh"
    readonly property string previewCaptureBackend: configHome + "/hypr/scripts/quickshell_lockscreen_preview_capture.sh"
    property string previewCaptureDirectory: ""
    property string previewCapturePendingDirectory: ""
    property bool editingActive: false
''',
    "editor preview capture properties",
)

replace_once(
    editor,
    '''    function toggleDrawer(name) {
''',
    '''    function previewCaptureSourceForScreen(screen) {
        if (previewCaptureDirectory.length === 0 || !screen || !screen.name)
            return "";
        const name = String(screen.name);
        if (!/^[A-Za-z0-9._-]+$/.test(name))
            return "";
        return "file://" + previewCaptureDirectory + "/" + name + ".png";
    }

    function presentEditorAfterPreviewCapture(message) {
        if (!open || pickerSuspended)
            return;
        if (message.length > 0)
            statusMessage = message;
        editorWindow.visible = true;
        FlyoutManager.claimOverlay("lockscreen-editor");
        scheduleContrastRefresh();
        Qt.callLater(() => {
            editorFocus.forceActiveFocus();
            replayEntryTransition();
        });
    }

    function cleanupPreviewCaptureDirectory(directory) {
        const value = String(directory || "");
        if (value.length === 0)
            return;
        Quickshell.execDetached(["bash", previewCaptureBackend, "cleanup", value]);
    }

    function toggleDrawer(name) {
''',
    "editor preview capture helpers",
)

replace_once(
    editor,
    '''        pickerSuspended = false;
        editingActive = true;
        editorWindow.visible = true;
        FlyoutManager.claimOverlay("lockscreen-editor");
        scheduleContrastRefresh();
        Qt.callLater(() => editorFocus.forceActiveFocus());
''',
    '''        pickerSuspended = false;
        editingActive = true;
        previewCaptureDirectory = "";
        previewCapturePendingDirectory = "";
        editorWindow.visible = false;
        statusMessage = "Capturing current desktop preview…";
        previewCaptureDelay.restart();
''',
    "deferred editor open capture",
)

replace_once(
    editor,
    '''        pickerSuspended = false;
        editingActive = false;
        FlyoutManager.releaseOverlay("lockscreen-editor");
        editorWindow.visible = false;
        loadPersistedDraft();
''',
    '''        pickerSuspended = false;
        editingActive = false;
        previewCaptureDelay.stop();
        const capturedPreview = previewCaptureDirectory;
        previewCaptureDirectory = "";
        previewCapturePendingDirectory = "";
        FlyoutManager.releaseOverlay("lockscreen-editor");
        editorWindow.visible = false;
        cleanupPreviewCaptureDirectory(capturedPreview);
        loadPersistedDraft();
''',
    "editor close capture cleanup",
)

replace_once(
    editor,
    '''    Timer {
        id: contrastRefreshDelay
''',
    '''    Timer {
        id: previewCaptureDelay
        interval: 120
        repeat: false
        onTriggered: {
            if (!root.open || root.pickerSuspended)
                return;
            root.previewCapturePendingDirectory = "";
            previewCaptureProcess.exec(["bash", root.previewCaptureBackend, "prepare"]);
        }
    }

    Process {
        id: previewCaptureProcess
        stdout: SplitParser {
            onRead: line => root.previewCapturePendingDirectory = String(line || "").trim()
        }
        onExited: (exitCode, exitStatus) => {
            const captured = root.previewCapturePendingDirectory;
            root.previewCapturePendingDirectory = "";
            if (!root.open || root.pickerSuspended) {
                root.cleanupPreviewCaptureDirectory(captured);
                return;
            }
            if (exitCode === 0 && captured.length > 0) {
                const previous = root.previewCaptureDirectory;
                root.previewCaptureDirectory = captured;
                root.cleanupPreviewCaptureDirectory(previous);
                root.presentEditorAfterPreviewCapture("");
            } else {
                root.previewCaptureDirectory = "";
                root.presentEditorAfterPreviewCapture(
                    "Desktop preview capture unavailable; using black fallback.");
            }
        }
    }

    Timer {
        id: contrastRefreshDelay
''',
    "editor preview capture process",
)

primary_old = '''            Item {
                id: editorTransitionStart
                x: editorFocus.width + 64
                y: 0
                width: editorFocus.width
                height: editorFocus.height

                Rectangle { anchors.fill: parent; color: "#101318" }
                Rectangle {
                    x: 0
                    y: 0
                    width: parent.width
                    height: Math.max(28, parent.height * 0.035)
                    color: "#1c222b"
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width * 0.62
                    height: parent.height * 0.56
                    radius: 8
                    color: "#202731"
                    border.width: 1
                    border.color: "#3a4657"
                    Rectangle {
                        x: 0
                        y: 0
                        width: parent.width
                        height: Math.max(26, parent.height * 0.07)
                        radius: parent.radius
                        color: "#2a3340"
                    }
                    Text {
                        anchors.centerIn: parent
                        text: "Synthetic desktop preview"
                        color: "#8d99aa"
                        font.family: Theme.fontFamily
                        font.pixelSize: Math.max(12, parent.height * 0.035)
                    }
                }
            }
'''
primary_new = '''            Item {
                id: editorTransitionStart
                x: editorFocus.width + 64
                y: 0
                width: editorFocus.width
                height: editorFocus.height

                Rectangle { anchors.fill: parent; color: "#000000" }
                Image {
                    anchors.fill: parent
                    source: root.previewCaptureSourceForScreen(editorWindow.screen)
                    fillMode: Image.Stretch
                    asynchronous: false
                    cache: false
                }
            }
'''
replace_once(editor, primary_old, primary_new, "primary real desktop preview")

secondary_old = '''            Item {
                id: secondaryTransitionStart; anchors.fill: parent
                Rectangle { anchors.fill: parent; color: "#101318" }
                Rectangle { anchors.centerIn: parent; width: parent.width*0.62; height: parent.height*0.56; radius: 8; color: "#202731"; border.width: 1; border.color: "#3a4657" }
            }
'''
secondary_new = '''            Item {
                id: secondaryTransitionStart
                x: parent.width + 64; y: 0; width: parent.width; height: parent.height
                Rectangle { anchors.fill: parent; color: "#000000" }
                Image {
                    anchors.fill: parent
                    source: root.previewCaptureSourceForScreen(modelData)
                    fillMode: Image.Stretch
                    asynchronous: false
                    cache: false
                }
            }
'''
replace_once(editor, secondary_old, secondary_new, "secondary real desktop preview")

drag_old = '''                MouseArea {
                    id: settingsBarAltDrag
                    anchors.fill: parent
                    z: 1000
                    acceptedButtons: Qt.LeftButton
                    property real dragStartSceneY: 0
                    property real dragStartOffsetY: 0

                    onPressed: mouse => {
                        if (!(mouse.modifiers & Qt.AltModifier)) {
                            mouse.accepted = false;
                            return;
                        }
                        const point = settingsBar.mapToItem(editorFocus, mouse.x, mouse.y);
                        dragStartSceneY = point.y;
                        dragStartOffsetY = root.settingsBarOffsetY;
                        mouse.accepted = true;
                    }
                    onPositionChanged: mouse => {
                        if (!pressed)
                            return;
                        const point = settingsBar.mapToItem(editorFocus, mouse.x, mouse.y);
                        const limit = Math.max(0, editorFocus.height - settingsBar.height);
                        root.settingsBarOffsetY = Math.max(0, Math.min(
                            limit, dragStartOffsetY + dragStartSceneY - point.y));
                    }
                }
'''
drag_new = '''                DragHandler {
                    id: settingsBarAltDrag
                    target: null
                    acceptedButtons: Qt.LeftButton
                    acceptedModifiers: Qt.AltModifier
                    dragThreshold: 0
                    xAxis.enabled: false
                    yAxis.enabled: true
                    yAxis.onActiveValueChanged: (delta) => {
                        const limit = Math.max(0, editorFocus.height - settingsBar.height);
                        root.settingsBarOffsetY = Math.max(0, Math.min(
                            limit, root.settingsBarOffsetY - delta));
                    }
                }
'''
replace_once(editor, drag_old, drag_new, "settings bar DragHandler")

# Retire stale synthetic-preview expectations.
entry_test = "tests/test-quickshell-lockscreen-entry-transitions.sh"
replace_once(
    entry_test,
    '''contains "$EDITOR" 'id: editorTransitionStart' \\
    'editor has no synthetic transition start source'
''',
    '''contains "$EDITOR" 'id: editorTransitionStart' \\
    'editor has no desktop transition start source'
''',
    "entry test transition start wording",
)
replace_once(
    entry_test,
    '''rejects "$EDITOR" 'AWTARCHY_LOCK_CAPTURE_DIR' \\
    'editor must not consume secure live desktop captures'
rejects "$EDITOR" 'quickshell_lockscreen_capture.sh' \\
    'editor Replay must use a synthetic source instead of capturing the desktop'
''',
    '''rejects "$EDITOR" 'AWTARCHY_LOCK_CAPTURE_DIR' \\
    'editor must not consume the secure lock capture environment'
rejects "$EDITOR" 'quickshell_lockscreen_capture.sh' \\
    'editor must not call the secure lock capture helper'
contains "$EDITOR" 'quickshell_lockscreen_preview_capture.sh' \\
    'editor Replay does not use its isolated unlocked desktop preview capture helper'
rejects "$EDITOR" 'Synthetic desktop preview' \\
    'editor Replay still uses the synthetic desktop placeholder'
''',
    "entry test capture contract",
)

blur_test = "tests/test-quickshell-lockscreen-blur-iris-editor-controls.sh"
replace_once(
    blur_test,
    '''require_text "$LAYER" 'hideSource: true' 'Iris Reveal mask source is not hidden safely'
''',
    '''require_text "$LAYER" 'hideSource: false' 'Iris Reveal mask staging still depends on hideSource suppression'
''',
    "Iris hideSource contract",
)

composition_test = "tests/test-quickshell-lockscreen-composition-blur-rendering.sh"
p = Path(composition_test)
text = p.read_text().replace(
    "# The unlocked editor cannot blur the live compositor behind a transparent\n# PanelWindow.  Its primary and secondary previews must feed their synthetic\n# desktop frames into the same desktopBackingSource input used by secure runtime,\n# so moving the Blur slider updates the complete preview composition live.\n",
    "# The unlocked editor captures each real output while its own windows are hidden.\n# Primary and secondary previews feed those frozen frames into the same\n# desktopBackingSource composition used by secure runtime, so Blur updates the\n# complete preview composition live without recursively capturing the editor UI.\n",
)
p.write_text(text)

# Managed history must now cover the new installed preview helper.
managed = "tests/test-quickshell-lockscreen-interactive-managed-history.sh"
replace_once(
    managed,
    "    'config/hypr/scripts/quickshell_lockscreen_contrast.sh:.config/hypr/scripts/quickshell_lockscreen_contrast.sh'\n",
    "    'config/hypr/scripts/quickshell_lockscreen_contrast.sh:.config/hypr/scripts/quickshell_lockscreen_contrast.sh'\n    'config/hypr/scripts/quickshell_lockscreen_preview_capture.sh:.config/hypr/scripts/quickshell_lockscreen_preview_capture.sh'\n",
    "managed preview capture helper",
)

# Permanent workflow owns the new regression and helper validation.
workflow = ".github/workflows/validate-quickshell-lockscreen-interactive-effects.yml"
replace_once(
    workflow,
    "          bash -n tests/test-quickshell-lockscreen-composition-blur-rendering.sh\n",
    "          bash -n tests/test-quickshell-lockscreen-composition-blur-rendering.sh\n          bash -n tests/test-quickshell-lockscreen-editor-preview-runtime.sh\n",
    "workflow test syntax",
)
replace_once(
    workflow,
    "          shellcheck tests/test-quickshell-lockscreen-composition-blur-rendering.sh\n",
    "          shellcheck tests/test-quickshell-lockscreen-composition-blur-rendering.sh\n          shellcheck tests/test-quickshell-lockscreen-editor-preview-runtime.sh\n",
    "workflow test shellcheck",
)
replace_once(
    workflow,
    '''          if [[ -f config/hypr/scripts/quickshell_lockscreen_capture.sh ]]; then
            bash -n config/hypr/scripts/quickshell_lockscreen_capture.sh
          fi
''',
    '''          if [[ -f config/hypr/scripts/quickshell_lockscreen_capture.sh ]]; then
            bash -n config/hypr/scripts/quickshell_lockscreen_capture.sh
          fi
          if [[ -f config/hypr/scripts/quickshell_lockscreen_preview_capture.sh ]]; then
            bash -n config/hypr/scripts/quickshell_lockscreen_preview_capture.sh
          fi
''',
    "workflow helper syntax",
)
replace_once(
    workflow,
    '''          if [[ -f config/hypr/scripts/quickshell_lockscreen_capture.sh ]]; then
            shellcheck config/hypr/scripts/quickshell_lockscreen_capture.sh
          fi
''',
    '''          if [[ -f config/hypr/scripts/quickshell_lockscreen_capture.sh ]]; then
            shellcheck config/hypr/scripts/quickshell_lockscreen_capture.sh
          fi
          if [[ -f config/hypr/scripts/quickshell_lockscreen_preview_capture.sh ]]; then
            shellcheck config/hypr/scripts/quickshell_lockscreen_preview_capture.sh
          fi
''',
    "workflow helper shellcheck",
)
replace_once(
    workflow,
    "          bash tests/test-quickshell-lockscreen-composition-blur-rendering.sh\n",
    "          bash tests/test-quickshell-lockscreen-composition-blur-rendering.sh\n          bash tests/test-quickshell-lockscreen-editor-preview-runtime.sh\n",
    "workflow focused regression",
)
