#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCENE="${ROOT}/config/quickshell/awtarchy-lock/LockScene.qml"
PREVIEW_SCENE="${ROOT}/config/quickshell/awtarchy/LockPreviewScene.qml"
SURFACE="${ROOT}/config/quickshell/awtarchy-lock/LockSurface.qml"
AUTH="${ROOT}/config/quickshell/awtarchy-lock/LockAuth.qml"
EDITOR="${ROOT}/config/quickshell/awtarchy/LockscreenEditor.qml"
EDITOR_SAVE="${ROOT}/config/hypr/scripts/quickshell_lockscreen_editor_save.sh"
SECURE_SHELL="${ROOT}/config/quickshell/awtarchy-lock/shell.qml"
WORKFLOW="${ROOT}/.github/workflows/validate-quickshell-lockscreen-interactive-effects.yml"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    return 1
}

require_text() {
    local file="$1" text="$2" message="$3"
    grep -Fq -- "$text" "$file" || fail "$message"
}

require_absent() {
    local file="$1" text="$2" message="$3"
    if grep -Fq -- "$text" "$file"; then
        fail "$message"
    fi
}

# Explicit presentation phases prevent animated images from being painted at
# their settled position before their own entrance starts.
require_text "$SCENE" 'property string presentationPhase: "transition"' \
    'lock scene does not define an explicit presentation phase'
require_text "$SCENE" 'property int logoEntryEpoch: 0' \
    'lock scene does not expose a logo-entry epoch'
require_text "$SCENE" 'readonly property bool customImageEntryStarted:' \
    'lock scene does not explicitly gate animated custom-image presentation'
require_text "$SCENE" 'property real spawnProgress: spawnMode === "none" ? 1 : 0' \
    'animated custom images still initialize at their settled presentation'
require_text "$SCENE" 'function customImageSpawnTiming(image)' \
    'custom-image timing is not normalized in the shared scene'
require_text "$SCENE" 'readonly property bool customImageAnimationActive:' \
    'custom-image playback is not explicitly gated by active animation'
require_text "$SCENE" 'root.editorMode && !customImageAnimationActive' \
    'idle editor images are not forced to their settled presentation'
require_text "$SCENE" 'function onLogoEntryEpochChanged()' \
    'during-logo custom images do not start with logo entry'
require_text "$SCENE" 'function onCustomImageSpawnEpochChanged()' \
    'after-logo custom images do not start at the post-logo boundary'
require_text "$SCENE" 'function beginLogoEntry()' \
    'desktop transition completion is not explicitly sequenced into logo entry'
require_text "$SCENE" 'function beginCustomImageEntry()' \
    'logo entry is not explicitly sequenced into custom-image entry'
require_text "$SCENE" 'onLogoEntryEpochChanged' \
    'logo particles are not explicitly replayed from the logo-entry epoch'
require_text "$SCENE" 'id: logoEntryPhaseTimer' \
    'logo-entry phase does not have an explicit completion boundary'
require_text "$SCENE" 'id: customImageEntryPhaseTimer' \
    'custom-image phase does not settle explicitly'

# Preview and secure scene are intentionally kept byte-identical so editor
# Preview exercises the same presentation ordering as the real lock scene.
cmp -s "$SCENE" "$PREVIEW_SCENE" \
    || fail 'secure and preview lock scenes diverged'

# Logo spawn uses the existing lockscreen_animation setting; the editor must
# draft and preview it instead of creating a second runtime animation system.
require_text "$EDITOR" 'property string draftLogoSpawnAnimation: "split"' \
    'editor has no draft logo spawn preference'
require_text "$EDITOR" 'animationPreference: root.draftLogoSpawnAnimation' \
    'editor preview does not use the draft logo spawn preference'
require_text "$EDITOR" 'LockscreenCompactSelector' \
    'spawn controls still rely on a generic desktop ComboBox/menu'
require_text "$EDITOR" 'root.selectedElement === "logo"' \
    'logo selection has no editor-specific spawn controls'

# Password-feedback presentation and clock format are draftable and flow through
# the shared scene path. Password submission itself must remain in LockAuth.
require_text "$EDITOR" 'property string draftPasswordFeedbackMode: "squares"' \
    'password feedback does not default to current square behavior'
require_text "$EDITOR" 'property string draftPasswordMaskCharacter: "•"' \
    'editor has no normalized custom password mask character'
require_text "$EDITOR" 'property string draftClockFormat: "24h"' \
    'clock format does not preserve the existing 24-hour default'
require_absent "$EDITOR" 'Preview: 14:59' \
    'editor still uses a hardcoded one-off clock preview string'
require_text "$SCENE" 'required property string passwordMaskMode' \
    'shared scene has no password feedback mode input'
require_text "$SCENE" 'required property string passwordMaskCharacter' \
    'shared scene has no custom password mask character'
require_text "$SCENE" 'required property string clockFormat' \
    'shared scene has no clock format preference'
require_text "$SCENE" 'root.clockFormat === "12h" ? "h:mm AP" : "HH:mm"' \
    'shared scene does not format both 24-hour and 12-hour AM/PM clocks'
require_text "$SURFACE" 'passwordMaskMode: root.profile.lockscreen_password_feedback_mode' \
    'secure surface does not resolve password feedback from the effective monitor profile'
require_text "$SURFACE" 'passwordMaskCharacter: root.profile.lockscreen_password_mask_character' \
    'secure surface does not resolve custom password-mask presentation from the effective monitor profile'
require_text "$SURFACE" 'clockFormat: root.profile.lockscreen_clock_format' \
    'secure surface does not resolve clock format from the effective monitor profile'

# Secure settings loading must migrate legacy state by falling back to the old
# presentation defaults when the new keys are absent or malformed.
require_text "$SECURE_SHELL" 'lockPasswordMaskMode = normalizedPasswordMaskMode(parsed.lockscreen_password_feedback_mode);' \
    'secure shell does not read the migrated password feedback field'
require_text "$SECURE_SHELL" 'property string lockPasswordMaskCharacter: "•"' \
    'secure shell has no safe custom mask default'
require_text "$SECURE_SHELL" 'property string lockClockFormat: "24h"' \
    'secure shell does not preserve legacy 24-hour clock behavior'

# Authentication authority stays isolated from editor/presentation code.
require_text "$AUTH" 'import Quickshell.Services.Pam' \
    'LockAuth no longer owns the PAM integration'
require_text "$AUTH" 'PamContext' \
    'LockAuth no longer owns the PAM context'
require_absent "$EDITOR" 'Quickshell.Services.Pam' \
    'editor gained PAM authority'
require_absent "$EDITOR" 'PamContext' \
    'editor gained authentication context ownership'

# The new persistence wrapper itself is part of the tested validation surface.
require_text "$WORKFLOW" 'bash -n config/hypr/scripts/quickshell_lockscreen_editor_save.sh' \
    'editor save wrapper is missing from workflow syntax validation'
require_text "$WORKFLOW" 'shellcheck config/hypr/scripts/quickshell_lockscreen_editor_save.sh' \
    'editor save wrapper is missing from workflow ShellCheck coverage'

# Persistence/normalization contract: old state may omit all new keys; saving
# the editor writes normalized values without ever storing password contents.
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/cache/awtarchy" "$work/home"
printf '%s\n' '{"enabled":true,"monitors":{}}' >"$work/cache/awtarchy/quickshell-state.json"

layout='{"logo":{"x":0.5,"y":0.34,"scale":1,"stretch_x":1,"stretch_y":1,"opacity":100,"color":"auto"},"time":{"x":0.5,"y":0.51,"scale":1,"stretch_x":1,"stretch_y":1,"opacity":100,"color":"auto"},"date":{"x":0.5,"y":0.555,"scale":1,"stretch_x":1,"stretch_y":1,"opacity":100,"color":"auto"},"username":{"x":0.5,"y":0.595,"scale":1,"stretch_x":1,"stretch_y":1,"opacity":100,"color":"auto"},"weather":{"x":0.5,"y":0.635,"scale":1,"stretch_x":1,"stretch_y":1,"opacity":100,"color":"auto"},"password":{"x":0.5,"y":0.7,"scale":1,"stretch_x":1,"stretch_y":1,"opacity":100,"color":"auto"}}'
visibility='{"logo":true,"time":true,"date":false,"username":false,"weather":false,"password":true}'
visualizer='{"enabled":false,"x":0.5,"y":0.8,"scale":1,"stretch_x":1,"stretch_y":1,"opacity":100,"color":"auto","bands":16,"gap":4,"height":100,"sensitivity":180,"shape":"straight","bend":45,"performance":"balanced"}'

save_editor() {
    HOME="$work/home" XDG_CONFIG_HOME="$ROOT/config" XDG_CACHE_HOME="$work/cache" \
        bash "$EDITOR_SAVE" \
        "$layout" "$visibility" black '#000000' '' cover 0.5 0.5 none 0 0 auto \
        '[]' "$visualizer" 100 fade 1800 100 smooth edges dots 'AB' 12h
}

save_editor

state_file="$work/cache/awtarchy/quickshell-state.json"
jq -e '
    .lockscreen_animation == "edges"
    and .lockscreen_password_feedback_mode == "dots"
    and (has("lockscreen_password_mask_mode") | not)
    and .lockscreen_password_mask_character == "A"
    and .lockscreen_clock_format == "12h"
    and (has("password") | not)
    and (has("lockscreen_password") | not)
' "$state_file" >/dev/null \
    || fail 'lockscreen presentation settings were not normalized/persisted safely'

# Force only the wrapper's second-stage jq invocation to fail. The established
# state backend remains functional, and the wrapper must remove its staged file.
real_jq="$(command -v jq)"
mkdir -p "$work/bin"
cat >"$work/bin/jq" <<EOF
#!/usr/bin/env bash
set -euo pipefail
for arg in "\$@"; do
    if [[ "\$arg" == "logo_animation" ]]; then
        false
    fi
done
"$real_jq" "\$@"
EOF
chmod +x "$work/bin/jq"

if PATH="$work/bin:$PATH" save_editor >/dev/null 2>&1; then
    fail 'forced wrapper-stage jq failure unexpectedly succeeded'
fi

if compgen -G "$state_file.tmp.*" >/dev/null; then
    fail 'editor save wrapper leaked a temporary state file after failure'
fi

printf 'quickshell lockscreen presentation sequencing contracts passed\n'
