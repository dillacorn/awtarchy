#!/usr/bin/env bash
# shellcheck disable=SC2016
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCENE="$ROOT/config/quickshell/awtarchy-lock/LockScene.qml"
PREVIEW_SCENE="$ROOT/config/quickshell/awtarchy/LockPreviewScene.qml"
SURFACE="$ROOT/config/quickshell/awtarchy-lock/LockSurface.qml"
AUTH="$ROOT/config/quickshell/awtarchy-lock/LockAuth.qml"
ANALYZER="$ROOT/config/quickshell/awtarchy-lock/LockAudioAnalyzer.qml"
PREVIEW_ANALYZER="$ROOT/config/quickshell/awtarchy/LockPreviewAudioAnalyzer.qml"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
has() { grep -Fq -- "$2" "$1" || fail "$3"; }
lacks() { ! grep -Fq -- "$2" "$1" || fail "$3"; }

# Password presentation and input focus must remain independent of decorative transition timing.
has "$SURFACE" 'opacity: (root.unlocking ? 0 : root.entered ? 1 : 0) * scene.elementOpacity("password")' \
    'password presentation is not available independently of the decorative transition'
has "$SURFACE" 'Component.onCompleted: {' \
    'secure surface does not initialize password availability immediately'
has "$SURFACE" 'root.entered = true;' \
    'secure surface does not enter password-ready state immediately'
has "$SURFACE" 'root.focusPasswordWhenReady();' \
    'secure surface does not request password focus immediately'
lacks "$SURFACE" 'if (!root.transitionComplete || root.unlocking)' \
    'password focus is still gated on transition completion'
lacks "$SURFACE" 'scene.securePasswordEntryOpacity' \
    'password presentation is still coupled to scene transition opacity'
lacks "$AUTH" 'transitionComplete' \
    'transition presentation state leaked into LockAuth'

# Logo hover should map the pointer into wordmark coordinates once per solver tick.
has "$SCENE" 'function logoHoverTarget(row, column, localPointer)' \
    'logo hover target does not consume a cached local pointer'
has "$SCENE" 'const hoverLocal = logoHoverActive' \
    'logo solver does not cache the pointer coordinate once per tick'
has "$SCENE" 'logoHoverTarget(row, column, hoverLocal)' \
    'logo solver does not reuse the cached pointer coordinate'
lacks "$SCENE" 'const local = wordmarkItem.mapFromItem(root, lastPointerX, lastPointerY);' \
    'logo hover still remaps the pointer once per particle'

# CAVA frame parsing should publish one result array without a second normalization pass.
has "$ANALYZER" 'const result = [];' \
    'audio analyzer does not build one parsed-frame result'
has "$ANALYZER" 'while (start <= frame.length && result.length < maximumBands)' \
    'audio analyzer parser does not fill the result directly'
has "$ANALYZER" 'const delimiter = frame.indexOf(";", start);' \
    'audio analyzer parser does not scan the CAVA frame directly'
lacks "$ANALYZER" '.split(";")' \
    'audio analyzer still allocates a temporary CAVA fields array'
has "$ANALYZER" 'bands = result;' \
    'audio analyzer does not publish the parsed-frame result directly'
lacks "$ANALYZER" 'function normalizedSpectrum' \
    'audio analyzer still performs a second normalization pass'

cmp -s "$SCENE" "$PREVIEW_SCENE" || fail 'secure/editor scene parity is broken'
cmp -s "$ANALYZER" "$PREVIEW_ANALYZER" || fail 'secure/editor analyzer parity is broken'

printf '%s\n' 'PASS: lockscreen pre-test optimization contracts'