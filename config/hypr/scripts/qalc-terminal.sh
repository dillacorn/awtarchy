#!/usr/bin/env bash
# Default to the bottom-input Qalc TUI; keep native Qalc available for testing.
set -euo pipefail

if [[ ${AWTARCHY_QALC_NATIVE:-0} == 1 ]]; then
    printf '\033[1mQalc\033[0m\n\n'
    exec qalc -s 'autocalc on'
fi

exec python3 "$(dirname -- "$0")/qalc-bottom.py"
