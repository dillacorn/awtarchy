#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
APP_STATE="${ROOT}/config/hypr/scripts/quickshell_application_state.sh"
EDITOR="${ROOT}/config/quickshell/awtarchy/LockscreenEditor.qml"
BAR_STATE="${ROOT}/config/quickshell/awtarchy/BarState.qml"
SCENE="${ROOT}/config/quickshell/awtarchy-lock/LockScene.qml"
PREVIEW_SCENE="${ROOT}/config/quickshell/awtarchy/LockPreviewScene.qml"
LOCK_SHELL="${ROOT}/config/quickshell/awtarchy-lock/shell.qml"
LOCK_AUTH="${ROOT}/config/quickshell/awtarchy-lock/LockAuth.qml"
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
visibility='{"logo":true,"time":true,"date":true,"username":true,"weather":true,"password":true}'
image_path="$TMP/custom image.png"
printf 'rotation-test\n' >"$image_path"
rotated_images="$(jq -cn --arg path "$image_path" '[{
    id:"image-rotation", path:$path, x:0.42, y:0.46, scale:1.5,
    stretch_x:1.2, stretch_y:0.8, opacity:70, rotation:-37, visible:true
}]')"

run_state save-lockscreen-editor \
    "$layout" "$visibility" black '#000000' '' \
    cover 0.5 0.5 none 0 0 auto "$rotated_images"

jq -e '
    (.lockscreen_custom_images | length) == 1
    and .lockscreen_custom_images[0].rotation == -37
' "$state_file" >/dev/null || fail 'custom image rotation did not persist atomically'

legacy_images="$(jq -cn --arg path "$image_path" '[{
    id:"image-legacy", path:$path, x:0.5, y:0.5, scale:1,
    stretch_x:1, stretch_y:1, opacity:100, visible:true
}]')"
run_state save-lockscreen-editor \
    "$layout" "$visibility" black '#000000' '' \
    cover 0.5 0.5 none 0 0 auto "$legacy_images"

jq -e '.lockscreen_custom_images[0].rotation == 0' "$state_file" >/dev/null \
    || fail 'legacy custom image did not gain a zero-degree rotation default'

bad_rotation="$(jq -cn --arg path "$image_path" '[{
    id:"image-bad-rotation", path:$path, x:0.5, y:0.5, scale:1,
    stretch_x:1, stretch_y:1, opacity:100, rotation:181, visible:true
}]')"
state_before="$(sha256sum "$state_file" | awk '{print $1}')"
if run_state save-lockscreen-editor \
    "$layout" "$visibility" black '#000000' '' \
    cover 0.5 0.5 none 0 0 auto "$bad_rotation" >/dev/null 2>&1; then
    fail 'custom image rotation outside the normalized signed range was accepted'
fi
[[ "$(sha256sum "$state_file" | awk '{print $1}')" == "$state_before" ]] \
    || fail 'invalid rotation partially mutated persistent state'

# State readers and secure presentation must share rotation semantics.
require_text "$BAR_STATE" 'rotation:' 'BarState custom-image normalization has no rotation field'
require_text "$LOCK_SHELL" 'rotation:' 'secure shell custom-image normalization has no rotation field'
require_text "$SCENE" 'function elementRotation(name)' 'shared scene has no rotation reader'
require_text "$SCENE" 'rotation: root.elementRotation(elementName)' 'custom images are not rotated in the shared scene'
cmp -s "$SCENE" "$PREVIEW_SCENE" || fail 'secure/editor scene parity drifted after rotation support'
reject_text "$LOCK_AUTH" 'rotation' 'presentation rotation leaked into the PAM/authentication owner'

# Editor rotation is direct, numeric, undoable, and part of the same draft image object.
require_text "$EDITOR" 'property string rotationElementName: ""' 'editor has no rotation interaction owner'
require_text "$EDITOR" 'function setDraftRotation(' 'editor has no custom-image rotation setter'
require_text "$EDITOR" 'function beginRotateElement(' 'editor has no visible rotation-handle interaction'
require_text "$EDITOR" 'function updateRotateElement(' 'editor rotation handle does not update the draft transform'
require_text "$EDITOR" 'function endRotateElement()' 'editor rotation handle does not close its history transaction'
require_text "$EDITOR" 'text: "Rotation"' 'editor has no signed numeric rotation control'
require_text "$EDITOR" 'Qt.SizeAllCursor' 'editor has no visible custom-image rotation handle cursor'
require_text "$EDITOR" 'rotation: 0' 'new custom images do not start at zero rotation'

# Every selectable presentation element gets a complete reset without replacing Reset Position/Reset All.
require_text "$EDITOR" 'function resetElementToDefault(name)' 'editor has no per-element Reset to Default action'
require_text "$EDITOR" 'label: "Reset to Default"' 'per-element Reset to Default control is missing'
require_text "$EDITOR" 'label: "Reset Position"' 'Reset Position was removed instead of preserved'
require_text "$EDITOR" 'label: "Restore Defaults"' 'Reset All/Restore Defaults was removed'
require_text "$EDITOR" 'if (name === "visualizer")' 'per-element reset does not cover the visualizer'
require_text "$EDITOR" 'if (isCustomImage(name))' 'per-element reset does not cover custom images'

printf '%s\n' 'PASS: lockscreen custom-image rotation and per-element reset contracts'
