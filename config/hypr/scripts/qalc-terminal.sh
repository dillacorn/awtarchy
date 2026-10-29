#!/usr/bin/env bash
# Minimal Qalc heading; preserve Qalc's native readline/live-preview behavior.
set -euo pipefail

printf '\033[1mQalc\033[0m\n\n'
exec qalc -s "autocalc on"
