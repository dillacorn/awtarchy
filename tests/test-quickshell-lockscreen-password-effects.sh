#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SURFACE="$ROOT/config/quickshell/awtarchy-lock/LockSurface.qml"
SECURE_SCENE="$ROOT/config/quickshell/awtarchy-lock/LockScene.qml"
PREVIEW_SCENE="$ROOT/config/quickshell/awtarchy/LockPreviewScene.qml"
EDITOR="$ROOT/config/quickshell/awtarchy/LockscreenEditor.qml"
AUTH="$ROOT/config/quickshell/awtarchy-lock/LockAuth.qml"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
require_text() { grep -Fq -- "$2" "$1" || fail "$3"; }
reject_text() { if grep -Fq -- "$2" "$1"; then fail "$3"; fi; }

# Authentication ownership stays exactly where it was.
require_text "$AUTH" 'import Quickshell.Services.Pam' 'LockAuth no longer owns PAM'
require_text "$AUTH" 'PamContext {' 'LockAuth no longer constructs PamContext'
require_text "$AUTH" 'signal authenticationFailed()' 'LockAuth no longer exposes shared failure signal'
reject_text "$AUTH" 'passwordTypingEpoch' 'presentation state leaked into LockAuth'
reject_text "$AUTH" 'Spark' 'password effects leaked into LockAuth'

# Secure surface derives presentation epochs from length/failure only.
require_text "$SURFACE" 'property int passwordTypingEpoch: 0' 'secure surface has no typing effect epoch'
require_text "$SURFACE" 'property int passwordFailureEpoch: 0' 'secure surface has no failure effect epoch'
require_text "$SURFACE" 'property int previousPasswordLength: 0' 'secure surface does not track prior password length'
require_text "$SURFACE" 'const nextLength = text.length;' 'typing feedback is not based on password length'
require_text "$SURFACE" 'nextLength > root.previousPasswordLength' 'backspace/in-place changes can trigger typing effects'
require_text "$SURFACE" 'root.passwordTypingEpoch += 1;' 'typing does not trigger presentation epoch'
require_text "$SURFACE" 'passwordFeedbackEpoch: root.passwordTypingEpoch' 'secure scene does not receive typing epoch'
reject_text "$SURFACE" 'passwordFeedbackText:' 'password contents are passed to presentation'
reject_text "$SURFACE" 'passwordFeedbackEpoch: password.text' 'password contents drive presentation directly'

# Persistent masks render only for the three mask modes.
require_text "$SURFACE" 'id: passwordMaskRow' 'secure password mask row has no explicit identity'
require_text "$SURFACE" 'root.passwordMaskVisible' 'secure mask row is not gated by feedback mode'
require_text "$SURFACE" 'readonly property bool passwordMaskVisible:' 'secure surface has no mask visibility contract'
require_text "$SURFACE" '["squares", "dots", "custom"]' 'secure mask visibility does not distinguish effect/hidden modes'

# Failure signal reaches every LockSurface via the shared auth object and causes
# a local red edge pulse regardless of the selected feedback mode.
require_text "$SURFACE" 'function onAuthenticationFailed()' 'secure surface no longer listens for auth failure'
require_text "$SURFACE" 'root.passwordFailureEpoch += 1;' 'auth failure does not trigger edge-light epoch'
require_text "$SURFACE" 'id: passwordFailureEdge' 'secure surface has no red failure edge'
require_text "$SURFACE" 'color: "#ff3030"' 'failure edge is not red'
require_text "$SURFACE" 'id: passwordFailureEdgeAnimation' 'failure edge has no fade animation'
require_text "$SURFACE" 'onPasswordFailureEpochChanged:' 'failure edge is not driven by local failure epoch'

# Shared scene copies own the same clipped password-zone effect renderer.
cmp -s "$SECURE_SCENE" "$PREVIEW_SCENE" || fail 'secure/editor scene copies diverged'
for scene in "$SECURE_SCENE" "$PREVIEW_SCENE"; do
    require_text "$scene" 'property int passwordFeedbackEpoch: 0' 'scene has no password feedback epoch'
    require_text "$scene" '["squares", "dots", "custom", "sparks", "mini-flash", "hidden"]'       'scene does not recognize all password feedback modes'
    require_text "$scene" 'id: passwordFeedbackZone' 'scene has no password feedback zone'
    require_text "$scene" 'clip: true' 'password sparks/flashes are not clipped to password zone'
    require_text "$scene" 'id: passwordSparkRepeater' 'scene has no spark renderer'
    require_text "$scene" 'root.effectivePasswordMaskMode === "sparks"' 'spark renderer is not mode-gated'
    require_text "$scene" 'id: passwordMiniFlash' 'scene has no mini-flash renderer'
    require_text "$scene" 'root.effectivePasswordMaskMode === "mini-flash"' 'mini-flash renderer is not mode-gated'
    require_text "$scene" 'function passwordFeedbackCoordinate(' 'password effect positions are not bounded helpers'
done

# Editor can demonstrate the non-persistent modes without touching auth.
require_text "$EDITOR" 'property int previewPasswordFeedbackEpoch: 0' 'editor has no password feedback preview epoch'
require_text "$EDITOR" 'label: "Preview Feedback"' 'editor has no password feedback preview action'
require_text "$EDITOR" 'previewPasswordFeedbackEpoch += 1' 'editor preview action does not trigger effect epoch'
require_text "$EDITOR" 'passwordFeedbackEpoch: root.previewPasswordFeedbackEpoch'   'active preview does not receive password feedback epoch'

printf '%s\n' 'PASS: secure lockscreen password feedback effects remain presentation-only'
