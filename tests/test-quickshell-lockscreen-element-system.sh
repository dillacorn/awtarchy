#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
APP_STATE="${ROOT}/config/hypr/scripts/quickshell_application_state.sh"
BAR_STATE="${ROOT}/config/quickshell/awtarchy/BarState.qml"
EDITOR="${ROOT}/config/quickshell/awtarchy/LockscreenEditor.qml"
SCENE="${ROOT}/config/quickshell/awtarchy-lock/LockScene.qml"
PREVIEW_SCENE="${ROOT}/config/quickshell/awtarchy/LockPreviewScene.qml"
SURFACE="${ROOT}/config/quickshell/awtarchy-lock/LockSurface.qml"
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

# RED/GREEN contract: Pass 2 extends the persisted element model instead of
# inventing a second state owner.
require_text "$APP_STATE" 'LOCKSCREEN_CUSTOM_IMAGE_MAX=12' \
    'custom image persistence is missing its bounded maximum'
require_text "$APP_STATE" 'normalize_lockscreen_custom_images_json()' \
    'custom image persistence has no validator/normalizer'
require_text "$APP_STATE" 'lockscreen_custom_images' \
    'custom image persistence is missing'
require_text "$APP_STATE" 'stretch_x' \
    'built-in layout persistence has no horizontal stretch'
require_text "$APP_STATE" 'stretch_y' \
    'built-in layout persistence has no vertical stretch'
require_text "$APP_STATE" 'opacity' \
    'built-in layout persistence has no configurable opacity'

# Legacy layout remains valid and gains safe transform defaults.
legacy_layout='{"logo":{"x":0.5,"y":0.34},"time":{"x":0.5,"y":0.51,"scale":0.8,"color":"#ff6600"},"date":{"x":0.5,"y":0.555},"username":{"x":0.5,"y":0.595},"weather":{"x":0.5,"y":0.635},"password":{"x":0.5,"y":0.7,"scale":1.4,"color":"auto"}}'
run_state save-lockscreen-layout "$legacy_layout"
jq -e '
    .lockscreen_layout.logo.scale == 1
    and .lockscreen_layout.logo.stretch_x == 1
    and .lockscreen_layout.logo.stretch_y == 1
    and .lockscreen_layout.logo.opacity == 100
    and .lockscreen_layout.logo.color == "auto"
    and .lockscreen_layout.time.scale == 0.8
    and .lockscreen_layout.time.color == "#ff6600"
    and .lockscreen_layout.password.opacity == 100
' "$state_file" >/dev/null || fail 'legacy layout did not normalize to Pass 2 defaults'

expanded_layout='{"logo":{"x":0.5,"y":0.34,"scale":1.25,"stretch_x":1.5,"stretch_y":0.75,"opacity":55,"color":"auto"},"time":{"x":0.5,"y":0.51,"scale":0.8,"stretch_x":1,"stretch_y":1,"opacity":90,"color":"#ff6600"},"date":{"x":0.5,"y":0.555,"scale":1,"stretch_x":1,"stretch_y":1,"opacity":80,"color":"auto"},"username":{"x":0.5,"y":0.595,"scale":1,"stretch_x":1,"stretch_y":1,"opacity":70,"color":"auto"},"weather":{"x":0.5,"y":0.635,"scale":1.1,"stretch_x":1,"stretch_y":1,"opacity":60,"color":"auto"},"password":{"x":0.5,"y":0.7,"scale":1.4,"stretch_x":1.1,"stretch_y":0.9,"opacity":20,"color":"auto"}}'
valid_visibility='{"logo":true,"time":true,"date":false,"username":true,"weather":false,"password":true}'

image_path="$TMP/custom image.png"
printf 'not-a-real-png-but-readable-for-path-validation\n' >"$image_path"
custom_images="$(jq -cn --arg path "$image_path" '[{
    id:"image-test_1", path:$path, x:0.42, y:0.46, scale:6,
    stretch_x:1.4, stretch_y:0.8, opacity:65, visible:true
}]')"

run_state save-lockscreen-editor \
    "$expanded_layout" "$valid_visibility" black '#000000' '' \
    cover 0.5 0.5 none 0 0 auto "$custom_images"

jq -e --arg expected "$(readlink -f -- "$image_path")" '
    .lockscreen_layout.logo.stretch_x == 1.5
    and .lockscreen_layout.logo.stretch_y == 0.75
    and .lockscreen_layout.logo.opacity == 55
    and .lockscreen_layout.password.opacity == 20
    and (.lockscreen_custom_images | length) == 1
    and .lockscreen_custom_images[0].id == "image-test_1"
    and .lockscreen_custom_images[0].path == $expected
    and .lockscreen_custom_images[0].scale == 6
    and .lockscreen_custom_images[0].stretch_x == 1.4
    and .lockscreen_custom_images[0].stretch_y == 0.8
    and .lockscreen_custom_images[0].opacity == 65
    and .lockscreen_custom_images[0].visible == true
' "$state_file" >/dev/null || fail 'expanded element/custom-image state did not persist atomically'

state_before="$(sha256sum "$state_file" | awk '{print $1}')"

password_too_faint="${expanded_layout/\"opacity\":20/\"opacity\":19}"
if run_state save-lockscreen-editor \
    "$password_too_faint" "$valid_visibility" black '#000000' '' \
    cover 0.5 0.5 none 0 0 auto "$custom_images" >/dev/null 2>&1; then
    fail 'password presentation opacity below 20% was accepted'
fi

bad_path_images='[{"id":"image-bad","path":"https://example.com/a.png","x":0.5,"y":0.5,"scale":1,"stretch_x":1,"stretch_y":1,"opacity":100,"visible":true}]'
if run_state save-lockscreen-editor \
    "$expanded_layout" "$valid_visibility" black '#000000' '' \
    cover 0.5 0.5 none 0 0 auto "$bad_path_images" >/dev/null 2>&1; then
    fail 'remote custom image path was accepted'
fi

duplicate_images="$(jq -cn --arg path "$image_path" '[
    {id:"image-dup",path:$path,x:0.4,y:0.4,scale:1,stretch_x:1,stretch_y:1,opacity:100,visible:true},
    {id:"image-dup",path:$path,x:0.6,y:0.6,scale:1,stretch_x:1,stretch_y:1,opacity:100,visible:true}
]')"
if run_state save-lockscreen-editor \
    "$expanded_layout" "$valid_visibility" black '#000000' '' \
    cover 0.5 0.5 none 0 0 auto "$duplicate_images" >/dev/null 2>&1; then
    fail 'duplicate custom image IDs were accepted'
fi

overscale_images="$(jq -cn --arg path "$image_path" '[{
    id:"image-too-large",path:$path,x:0.5,y:0.5,scale:10.01,
    stretch_x:1,stretch_y:1,opacity:100,visible:true
}]')"
if run_state save-lockscreen-editor \
    "$expanded_layout" "$valid_visibility" black '#000000' '' \
    cover 0.5 0.5 none 0 0 auto "$overscale_images" >/dev/null 2>&1; then
    fail 'custom image scale above 10x was accepted'
fi

[[ "$(sha256sum "$state_file" | awk '{print $1}')" == "$state_before" ]] \
    || fail 'invalid Pass 2 editor save partially mutated persistent state'

run_state reset-lockscreen-presentation
jq -e '
    .lockscreen_custom_images == []
    and .lockscreen_layout.logo.opacity == 100
    and .lockscreen_layout.logo.stretch_x == 1
    and .lockscreen_layout.logo.stretch_y == 1
    and .lockscreen_layout.password.opacity == 100
' "$state_file" >/dev/null || fail 'Restore Defaults does not clear custom images/new transform state'

# Unlocked state owner must expose normalized custom images and transform defaults.
require_text "$BAR_STATE" 'function lockscreenCustomImages()' \
    'BarState has no normalized custom-image reader'
require_text "$BAR_STATE" 'stretch_x' \
    'BarState has no horizontal-stretch normalization'
require_text "$BAR_STATE" 'stretch_y' \
    'BarState has no vertical-stretch normalization'
require_text "$BAR_STATE" 'opacity' \
    'BarState has no opacity normalization'

# Secure and preview scenes consume the same generic presentation state.
require_text "$SCENE" 'required property var customImages' \
    'secure scene has no custom image input'
require_text "$SCENE" 'function elementStretchX(name)' \
    'scene has no generic horizontal-stretch reader'
require_text "$SCENE" 'function elementStretchY(name)' \
    'scene has no generic vertical-stretch reader'
require_text "$SCENE" 'function elementOpacity(name)' \
    'scene has no generic opacity reader'
require_text "$SCENE" 'id: customImageRepeater' \
    'scene does not render custom images'
require_text "$SCENE" 'z: 4' \
    'custom images are not pinned below built-in/password presentation'
cmp -s "$SCENE" "$PREVIEW_SCENE" || fail 'secure/editor lockscreen scene parity drifted'

require_text "$SURFACE" 'required property var customImages' \
    'secure lock surface does not pass custom images presentation-only'
require_text "$LOCK_SHELL" 'property var lockCustomImages: []' \
    'secure shell has no safe custom-image default'
require_text "$LOCK_SHELL" 'function normalizedCustomImages(value)' \
    'secure shell does not re-normalize persisted custom images'
require_text "$LOCK_SHELL" 'customImages: root.lockCustomImages' \
    'secure shell does not pass normalized images to the surface'
reject_text "$LOCK_AUTH" 'customImages' \
    'custom images leaked into PAM/authentication owner'
reject_text "$LOCK_AUTH" 'opacity' \
    'presentation opacity leaked into PAM/authentication owner'

# Editor uses one selection/transform model for built-ins and draft custom images.
require_text "$EDITOR" 'property var draftCustomImages: []' \
    'editor has no draft custom-image state'
require_text "$EDITOR" 'function addCustomImage(' \
    'editor cannot add custom images'
require_text "$EDITOR" 'function removeCustomImage(' \
    'editor cannot remove custom images'
require_text "$EDITOR" 'function isCustomImage(' \
    'editor cannot distinguish generic custom-image elements'
require_text "$EDITOR" 'function setDraftOpacity(' \
    'editor has no generic element opacity setter'
require_text "$EDITOR" 'function setDraftStretch(' \
    'editor has no generic element stretch setter'
require_text "$EDITOR" 'text: "Opacity"' \
    'editor has no visible opacity control'
require_text "$EDITOR" 'text: "Stretch X"' \
    'editor has no horizontal stretch precision control'
require_text "$EDITOR" 'text: "Stretch Y"' \
    'editor has no vertical stretch precision control'
require_text "$EDITOR" 'label: "Add Image"' \
    'editor has no local custom-image insertion action'
require_text "$EDITOR" 'label: "Remove Image"' \
    'editor has no custom-image removal action'
require_text "$EDITOR" 'JSON.stringify(draftCustomImages)' \
    'atomic editor save does not include custom images'

printf 'PASS: lockscreen Pass 2 generic transforms, opacity, and custom image contracts\n'
