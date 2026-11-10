#!/usr/bin/env bash
# Read-only first-login validation, saved modes vs live Jay, Quickshell IPC.
set -euo pipefail
home="${XDG_CONFIG_HOME:-$HOME/.config}"
script="$home/jay/awtarchy-trial/diagnose.py"
[[ -f "$script" && ! -L "$script" ]] || {
    printf 'Missing Jay diagnostic: %s\n' "$script" >&2
    exit 1
}
python3 "$script"
