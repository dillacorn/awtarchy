#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

printf '%s\n' 'DIAGNOSTIC: current managed stock SHA-256 values'
for rel in \
    config/quickshell/awtarchy-lock/LockScene.qml \
    config/quickshell/awtarchy-lock/LockSurface.qml \
    config/quickshell/awtarchy-lock/shell.qml \
    config/quickshell/awtarchy/LockPreviewScene.qml \
    config/quickshell/awtarchy/LockscreenCompactSelector.qml \
    config/quickshell/awtarchy/LockscreenEditor.qml; do
    printf 'MANAGED_HASH '
    sha256sum "$ROOT/$rel"
done

false
