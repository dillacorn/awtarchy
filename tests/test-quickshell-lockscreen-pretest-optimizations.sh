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

# Password presentation and input focus must remain behind the secure transition.
has "$SCENE" 'root.entered && !root.effectiveEntryTransitionRunning ? 1 : 0' \
    'password presentation can become visible before the entry transition completes'
has "$SURFACE" 'if (!root.transitionComplete || root.unlocking)' \
    'password focus is not gated on transition completion'
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
has "$ANALYZER" 'for (let i = 0; i < fields.length && result.length < maximumBands; ++i)' \
    'audio analyzer parser does not fill the result directly'
has "$ANALYZER" 'bands = result;' \
    'audio analyzer does not publish the parsed-frame result directly'
lacks "$ANALYZER" 'function normalizedSpectrum' \
    'audio analyzer still performs a second normalization pass'

cmp -s "$SCENE" "$PREVIEW_SCENE" || fail 'secure/editor scene parity is broken'
cmp -s "$ANALYZER" "$PREVIEW_ANALYZER" || fail 'secure/editor analyzer parity is broken'

printf '%s\n' 'PASS: lockscreen pre-test optimization contracts'
