#!/usr/bin/env bash
# Toggle the Awtarchy Quickshell application launcher.

set -euo pipefail

SCRIPTS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts"

# Hot path: when the running Awtarchy shell already owns launcher IPC, toggle it
# directly. Avoid re-registering runtime rules and normalizing shell state on
# every keyboard shortcut invocation.
if ! qs -c awtarchy ipc call launcher toggle >/dev/null 2>&1; then
    "$SCRIPTS_DIR/quickshell_runtime_rules.sh" >/dev/null 2>&1 || true
    "$SCRIPTS_DIR/quickshell.sh" start >/dev/null
    exec qs -c awtarchy ipc call launcher toggle
fi
